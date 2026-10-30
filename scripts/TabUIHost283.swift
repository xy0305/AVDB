import SwiftUI

// Build 283 UI host: production FloatingTabContainer + AVDBNativeTabBar + HidesFloatingTabBar
// + KeyboardVisibilityReader. Screen contents are neutral fixtures shaped like 首頁/搜索.
@main
struct TabUIHost283: App {
    var body: some Scene { WindowGroup { Root() } }
}

private struct Root: View {
    @State private var tab: AppTab = .home
    var body: some View {
        FloatingTabContainer(selection: $tab) {
            ZStack {
                ForEach(AppTab.allCases) { t in
                    Group {
                        if t == .me { MeFixture() } else if t == tab || t == .home { HomeFixture(title: t.title) }
                    }
                    .environment(\.appTab, t)
                    .opacity(tab == t ? 1 : 0).allowsHitTesting(tab == t).zIndex(tab == t ? 1 : 0)
                    .accessibilityHidden(tab != t)
                }
            }
        }
    }
}

private let chips = ["VR","ID-020","ID-033","SSIS-001","ID-029","ID-038","snos","ID-017","jur","连裤袜","BT-107","GS-199","巨乳","SB-001",
                     "洗脑","熟女","无码流出","深喉","母子","ID-036","Redia","ID-023","黑人","ipzz","mida","角色扮演","abf","mism","ID-026","DC-005","AP-029"]

private struct HomeFixture: View {
    let title: String
    @State private var search = false
    var body: some View {
        NavigationStack {
            List {
                Button { search = true } label: { Label("搜索番號 / 關鍵詞", systemImage: "magnifyingglass") }
                    .accessibilityIdentifier("fixture.search.\(title)")
                ForEach(0..<30, id: \.self) { Text("\(title) 列表项 \($0)") }
            }
            .navigationTitle(title)
            .navigationDestination(isPresented: $search) { SearchFixture() }
        }
    }
}

private struct SearchFixture: View {
    @Environment(\.dismiss) private var dismiss
    @State private var keyword = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack { Image(systemName: "magnifyingglass"); TextField("搜索番號 / 關鍵詞", text: $keyword).focused($focused).accessibilityIdentifier("search.field") }
                    .padding(12).background(.thinMaterial, in: Capsule())
                Button("取消") { dismiss() }.accessibilityIdentifier("search.cancel")
            }
            Text("近期熱搜").font(.headline)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(chips, id: \.self) { Text($0).font(.subheadline).padding(.horizontal, 12).padding(.vertical, 8).background(.thinMaterial, in: Capsule()) }
                }
            }
        }
        .padding(.horizontal, 16)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { focused = true }
        .modifier(HidesFloatingTabBar())      // production modifier, as in SearchView
    }
}

private struct MeFixture: View {
    @State private var text = ""
    var body: some View {
        NavigationStack {
            Form { TextField("备注（其它页面的文本框）", text: $text).accessibilityIdentifier("me.field") }
                .navigationTitle("我的")
        }
    }
}
