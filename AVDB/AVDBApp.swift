//
//  AVDBApp.swift
//  AVDB
//
//  App 入口。官方 App 为浅色界面。
//

import SwiftUI

@main
struct AVDBApp: App {
    @StateObject private var appState = AppState()

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
