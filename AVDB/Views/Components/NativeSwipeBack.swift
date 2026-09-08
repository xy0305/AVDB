import SwiftUI
import UIKit

/// 页面级安全桥接：只恢复当前 UINavigationController 已有的系统边缘返回手势。
/// 不交换方法、不继承或扩展系统类；获取失败时静默退出，不影响启动。
struct NativeSwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.enableWhenAvailable()
    }

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enableWhenAvailable()
        }

        func enableWhenAvailable() {
            DispatchQueue.main.async { [weak self] in
                guard let navigationController = self?.navigationController,
                      navigationController.viewControllers.count > 1,
                      let gesture = navigationController.interactivePopGestureRecognizer else { return }
                gesture.delegate = nil
                gesture.isEnabled = true
            }
        }
    }
}

extension View {
    func nativeSwipeBackEnabled() -> some View {
        background(NativeSwipeBackEnabler().frame(width: 0, height: 0))
    }
}
