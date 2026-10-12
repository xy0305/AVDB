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

final class AVDBAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : KSOptions.supportedInterfaceOrientations
    }
}

@main
struct AVDBApp: App {
    @UIApplicationDelegateAdaptor(AVDBAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    // Audio is intentionally untouched at launch. Only a concrete player may own the session.

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(.light)
                .tint(Color(red: 0.12, green: 0.48, blue: 0.96))
                .liquidGlassChrome()
        }
    }
}

/// 全局状态
@MainActor
final class AppState: ObservableObject {
    @Published var isLoggedIn = false
    @Published var currentUser: User?
    private(set) var restoreTask: Task<Void, Never>?

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--poster-navigation-fixture") { return }
        #endif
        restoreLogin()
    }

    func restoreLogin() {
        restoreTask?.cancel()
        // 检查本地是否有保存的 Token
        if let restoredToken = APIClient.shared.token, !restoredToken.isEmpty {
            isLoggedIn = true
            restoreTask = Task {
                do {
                    let (user, _) = try await JavDBSDK.shared.userInfo()
                    // A delayed launch request must not resurrect a logged-out/replaced account.
                    guard !Task.isCancelled, APIClient.shared.token == restoredToken else { return }
                    self.currentUser = user
                    self.isLoggedIn = true
                } catch {
                    guard !Task.isCancelled, APIClient.shared.token == restoredToken else { return }
                    // Offline, timeout, decoding, signing and 403 errors do not prove expiry.
                    // Even a 401 must not destroy the saved credential: allow explicit re-login
                    // and retry on next launch without deleting any account data.
                    if case JavDBError.httpError(401, _) = error {
                        self.isLoggedIn = false
                        self.currentUser = nil
                    }
                }
            }
        }
    }
}
