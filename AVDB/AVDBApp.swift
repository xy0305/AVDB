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
        KSOptions.supportedInterfaceOrientations
    }
}

@main
struct AVDBApp: App {
    @UIApplicationDelegateAdaptor(AVDBAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    init() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {}
    }

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

    init() {
        // 检查本地是否有保存的 Token
        if APIClient.shared.hasToken {
            isLoggedIn = true
            // 异步验证 Token 并拉取用户信息
            Task {
                do {
                    let (user, _) = try await JavDBSDK.shared.userInfo()
                    self.currentUser = user
                    self.isLoggedIn = true
                } catch {
                    // Token 无效或过期，清除登录状态
                    JavDBSDK.shared.logout()
                    self.isLoggedIn = false
                    self.currentUser = nil
                }
            }
        }
    }
}
