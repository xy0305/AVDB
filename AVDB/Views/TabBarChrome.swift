import SwiftUI
import UIKit

/// Build 283: visibility of the custom floating tab bar (首頁/排行/類別/演員/糖心/我的).
/// The bar lives in a bottom `safeAreaInset`, which follows the keyboard safe area, so it
/// used to float above the keyboard and cover search chips. It is now hidden while a
/// search screen is active in the selected tab, or whenever the software keyboard is up.
enum AppTab: Int, CaseIterable, Identifiable, Hashable {
    case home, rankings, categories, actors, tangxin, me
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home: return "首頁"
        case .rankings: return "排行"
        case .categories: return "類別"
        case .actors: return "演員"
        case .tangxin: return "糖心"
        case .me: return "我的"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .rankings: return "trophy"
        case .categories: return "square.grid.2x2"
        case .actors: return "person.2"
        case .tangxin: return "play.rectangle"
        case .me: return "person.crop.circle"
        }
    }
}

@MainActor
final class TabBarChrome: ObservableObject {
    @Published private(set) var searchDepth: [AppTab: Int] = [:]
    @Published private(set) var keyboardVisible = false

    func enterSearch(_ tab: AppTab?) { guard let tab else { return }; searchDepth[tab, default: 0] += 1 }
    func leaveSearch(_ tab: AppTab?) {
        guard let tab else { return }
        searchDepth[tab] = max(0, (searchDepth[tab] ?? 0) - 1)
    }
    func setKeyboard(_ visible: Bool) { if keyboardVisible != visible { keyboardVisible = visible } }

    nonisolated static func hidden(selected: AppTab, searchDepth: [AppTab: Int], keyboardVisible: Bool) -> Bool {
        keyboardVisible || (searchDepth[selected] ?? 0) > 0
    }
    func hidden(selected: AppTab) -> Bool { Self.hidden(selected: selected, searchDepth: searchDepth, keyboardVisible: keyboardVisible) }

    /// A docked (software) keyboard overlapping the bottom of the screen. Hardware keyboards
    /// report only a short accessory bar, which must not hide navigation.
    nonisolated static func keyboardCovers(endFrame: CGRect, screenHeight: CGFloat) -> Bool {
        endFrame.height > 120 && endFrame.minY < screenHeight - 1
    }
}

private struct AppTabKey: EnvironmentKey { static let defaultValue: AppTab? = nil }
private struct TabBarChromeKey: EnvironmentKey { static let defaultValue: TabBarChrome? = nil }
extension EnvironmentValues {
    /// Optional so fixtures / previews / sheets without the tab container never crash.
    var tabBarChrome: TabBarChrome? {
        get { self[TabBarChromeKey.self] }
        set { self[TabBarChromeKey.self] = newValue }
    }
    /// Which root tab a view belongs to (set by ContentView per tab).
    var appTab: AppTab? {
        get { self[AppTabKey.self] }
        set { self[AppTabKey.self] = newValue }
    }
}

/// Marks a screen as "search active" for its tab while it is on screen.
struct HidesFloatingTabBar: ViewModifier {
    @Environment(\.appTab) private var tab
    @Environment(\.tabBarChrome) private var chrome
    @State private var registered = false
    func body(content: Content) -> some View {
        content
            .onAppear { if !registered, let chrome { registered = true; chrome.enterSearch(tab) } }
            .onDisappear { if registered { registered = false; chrome?.leaveSearch(tab) } }
    }
}

/// Tracks the software keyboard for the whole window.
struct KeyboardVisibilityReader: ViewModifier {
    let chrome: TabBarChrome
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                let height = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.height ?? frame.maxY
                withAnimation(.easeInOut(duration: 0.22)) { chrome.setKeyboard(TabBarChrome.keyboardCovers(endFrame: frame, screenHeight: height)) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.easeInOut(duration: 0.22)) { chrome.setKeyboard(false) }
            }
    }
}

/// Production container for the six root tabs: content + floating bar in a bottom inset.
struct FloatingTabContainer<Content: View>: View {
    @Binding var selection: AppTab
    @StateObject private var chrome = TabBarChrome()
    private let content: Content
    init(selection: Binding<AppTab>, @ViewBuilder content: () -> Content) {
        _selection = selection; self.content = content()
    }
    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Build 283: hidden while search is active in the selected tab or the keyboard
                // is up, so it never floats above the keyboard over search content.
                if !chrome.hidden(selected: selection) {
                    AVDBNativeTabBar(selection: $selection)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        // No container identifier: it would override the app.tab.N button ids.
                }
            }
            .animation(.easeInOut(duration: 0.22), value: chrome.hidden(selected: selection))
            .modifier(KeyboardVisibilityReader(chrome: chrome))
            .environment(\.tabBarChrome, chrome)
    }
}
