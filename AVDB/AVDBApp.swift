//
//  AVDBApp.swift
//  AVDB
//
//  App 入口。
//

import SwiftUI

@main
struct AVDBApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
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
