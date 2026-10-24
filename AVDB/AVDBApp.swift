//
//  AVDBApp.swift
//  AVDB
//
//  App 入口。官方 App 为浅色界面。
//

import AVFoundation
import SwiftUI
import KSPlayer
import UIKit
import Network
import CryptoKit

final class AVDBAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : KSOptions.supportedInterfaceOrientations
    }
}

@main
struct AVDBApp: App {
    @UIApplicationDelegateAdaptor(AVDBAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    // Audio is intentionally untouched at launch. Only a concrete player may own the session.

    var body: some Scene {
        WindowGroup {
            Group {
                if JavVerseReleaseProbe.enabled {
                    NavigationStack { JavVerseView() }
                } else {
                    ContentView()
                }
            }
                .environmentObject(appState)
                .preferredColorScheme(.light)
                .tint(Color(red: 0.12, green: 0.48, blue: 0.96))
                .liquidGlassChrome()
                .onChange(of: appState.currentUser?.id, initial: true) { _, accountID in
                    PlaybackHistoryStore.shared.activate(accountID: accountID)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { appState.restoreLogin() }
                }
        }
    }
}

/// Cached identity is UI data, never proof of server authentication.
@MainActor
final class AppState: ObservableObject {
    enum SessionStatus { case signedOut, restoring, cached, validated, unavailable, needsReauth }
    @Published var isLoggedIn = false
    @Published var currentUser: User?
    @Published private(set) var sessionStatus: SessionStatus = .signedOut
    private(set) var restoreTask: Task<Void, Never>?
    private var epoch = UUID()
    private var activeToken: String?
    private var monitor: NWPathMonitor?
    private let defaults: UserDefaults
    private let readToken: () -> String?
    private let fetchProfile: () async throws -> User
    private let pause: (UInt64) async throws -> Void

    init(defaults: UserDefaults = .standard,
         readToken: @escaping () -> String? = { APIClient.shared.token },
         fetchProfile: @escaping () async throws -> User = { try await JavDBSDK.shared.profile() },
         pause: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
         observeNetwork: Bool = true) {
        self.defaults = defaults
        self.readToken = readToken
        self.fetchProfile = fetchProfile
        self.pause = pause
        guard !JavVerseReleaseProbe.enabled else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--poster-navigation-fixture") { return }
        #endif
        restoreLogin()
        if observeNetwork {
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] path in
                guard path.status == .satisfied else { return }
                Task { @MainActor [weak self] in self?.resumeValidation() }
            }
            monitor.start(queue: DispatchQueue(label: "avdb.session.network"))
            self.monitor = monitor
        }
    }

    deinit { monitor?.cancel(); restoreTask?.cancel() }

    private func key(_ token: String) -> String {
        "avdb.profile.v1." + SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func save(_ user: User, token: String) {
        // Whitelist only fields rendered by the native account page. No email,
        // password, token, avatar URL (which could contain credentials), or bio.
        var value: [String: Any] = ["id": user.id]
        value["username"] = user.username
        value["is_vip"] = user.isVip
        value["want_watch_count"] = user.wantWatchCount
        value["watched_count"] = user.watchedCount
        if let data = try? JSONSerialization.data(withJSONObject: value) {
            defaults.set(data, forKey: key(token))
        }
    }

    func acceptLogin(_ user: User) {
        restoreTask?.cancel(); restoreTask = nil; epoch = UUID()
        activeToken = readToken()
        guard let token = activeToken, !token.isEmpty else { return }
        save(user, token: token)
        currentUser = user; isLoggedIn = true; sessionStatus = .validated
    }

    func logout() {
        if let token = activeToken ?? readToken() { defaults.removeObject(forKey: key(token)) }
        restoreTask?.cancel(); restoreTask = nil; epoch = UUID(); activeToken = nil
        currentUser = nil; isLoggedIn = false; sessionStatus = .signedOut
        JavDBSDK.shared.logout()
    }

    func restoreLogin() {
        guard !JavVerseReleaseProbe.enabled else { return }
        let token = readToken().flatMap { $0.isEmpty ? nil : $0 }
        if token != activeToken {
            restoreTask?.cancel(); restoreTask = nil; epoch = UUID()
            activeToken = token; currentUser = nil
            if let token, let data = defaults.data(forKey: key(token)) {
                currentUser = try? JSONDecoder().decode(User.self, from: data)
            }
            sessionStatus = currentUser == nil ? .restoring : .cached
        }
        guard token != nil else {
            currentUser = nil; isLoggedIn = false; sessionStatus = .signedOut; return
        }
        isLoggedIn = sessionStatus != .needsReauth
        resumeValidation()
    }

    func resumeValidation() {
        guard readToken() == activeToken else { restoreLogin(); return }
        guard let token = activeToken, restoreTask == nil,
              sessionStatus != .needsReauth else { return }
        let generation = epoch
        restoreTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.epoch == generation { self.restoreTask = nil } }
            // One bounded burst; a new foreground/network recovery starts another.
            for attempt in 0..<4 {
                do {
                    if attempt > 0 { try await self.pause(UInt64([2, 5, 15][attempt - 1]) * 1_000_000_000) }
                    try Task.checkCancellation()
                    let user = try await self.fetchProfile()
                    guard !Task.isCancelled, self.epoch == generation, self.readToken() == token else { return }
                    self.save(user, token: token)
                    self.currentUser = user; self.isLoggedIn = true; self.sessionStatus = .validated
                    return
                } catch {
                    guard !Task.isCancelled, self.epoch == generation, self.readToken() == token else { return }
                    if case JavDBError.httpError(401, _) = error {
                        self.defaults.removeObject(forKey: self.key(token))
                        self.currentUser = nil; self.isLoggedIn = false; self.sessionStatus = .needsReauth
                        // Retain the credential under the existing explicit-logout policy,
                        // but never present it as valid or retry a known 401 automatically.
                        return
                    }
                    self.sessionStatus = self.currentUser == nil ? .unavailable : .cached
                }
            }
        }
    }
}
