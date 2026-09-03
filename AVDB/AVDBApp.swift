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
        isLoggedIn = APIClient.shared.hasToken
        currentUser = APIClient.shared.currentUser
    }
}
