//
//  AVDBApp.swift
//  AVDB
//
//  App 入口。官方 App 为浅色界面。
//

import AVFoundation
import SwiftUI
import UIKit
import ObjectiveC.runtime

@main
struct AVDBApp: App {
    @StateObject private var appState = AppState()

    init() {
        UINavigationController.enableNativeEdgeSwipeBack()
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


/// SwiftUI 隐藏返回按钮时也保留 UINavigationController 原生左边缘右滑返回。
/// 只使用系统 interactivePopGestureRecognizer，不添加全屏拖动，避免与横向轮播冲突。
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    private static let installEdgeSwipeBack: Void = {
        guard let original = class_getInstanceMethod(UINavigationController.self, #selector(UINavigationController.viewDidLoad)),
              let replacement = class_getInstanceMethod(UINavigationController.self, #selector(UINavigationController.avdb_viewDidLoad)) else { return }
        method_exchangeImplementations(original, replacement)
    }()

    static func enableNativeEdgeSwipeBack() {
        _ = installEdgeSwipeBack
    }

    @objc private func avdb_viewDidLoad() {
        avdb_viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
        interactivePopGestureRecognizer?.isEnabled = true
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === interactivePopGestureRecognizer else { return true }
        return viewControllers.count > 1 && transitionCoordinator == nil
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
