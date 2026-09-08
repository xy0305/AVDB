//
//  AVDBApp.swift
//  AVDB
//
//  App 入口。官方 App 为浅色界面。
//

import AVFoundation
import SwiftUI

@main
struct AVDBApp: App {
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
                    let user = try await JavDBSDK.shared.userInfo()
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
