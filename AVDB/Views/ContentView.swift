//
//  ContentView.swift
//  AVDB
//
//  原生六栏容器：iOS 26 Liquid Glass、iOS 17 material 回退。
//  不使用系统五项溢出 More，避免新增栏目产生双重导航。
//

import SwiftUI

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

struct ContentView: View {
    var tangxinClient: TangxinClient = TangxinClient()
    @State private var selectedTab: AppTab = .home
    @State private var visitedTabs: Set<AppTab> = [.home]

    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--subtitle-controls-fixture"),
           let url = Bundle.main.url(forResource: "neutral-subtitle", withExtension: "mp4") {
            // Exercise the production route-owned orientation host, not a DEBUG-only
            // .all mask that can leave the iPhone event window portrait.
            KSChromePlayer(url: url, title: "中性播放器测试", subtitle: "原文件 / 原画", onSelectSource: {}, onSelectEpisode: {}, publicSubtitleQuery: "公开测试片名")
        } else if ProcessInfo.processInfo.arguments.contains("--online-subtitle-fixture") {
            OnlineSubtitleFixtureView()
        } else if ProcessInfo.processInfo.arguments.contains("--detail-hero-fixture") {
            NavigationStack { DetailHeroFixtureGallery() }.modifier(SceneLayoutReader())
        } else if ProcessInfo.processInfo.arguments.contains("--catalog-navigation-fixture") {
            NavigationStack { CatalogListView(title: "近期磁鏈更新", source: .magnets) }
                .modifier(SceneLayoutReader())
        } else if ProcessInfo.processInfo.arguments.contains("--poster-size-fixture") {
            PosterSizeRegressionGallery()
        } else if ProcessInfo.processInfo.arguments.contains("--javlibrary-navigation-fixture") {
            NavigationStack { JAVLibraryRankingView() }
                .modifier(SceneLayoutReader())
        } else if ProcessInfo.processInfo.arguments.contains("--missav-scroll-fixture") {
            NavigationStack { MissAVRankingView() }
                .modifier(SceneLayoutReader())
        } else if ProcessInfo.processInfo.arguments.contains("--jr-design-fixture") {
            RankingsView().modifier(SceneLayoutReader())
        } else if ProcessInfo.processInfo.arguments.contains("--jr-navigation-fixture") {
            NavigationStack { JRPageView(path: "/neutral/ranking/") }
                .modifier(SceneLayoutReader())
        } else {
            mainTabs
        }
        #else
        mainTabs
        #endif
    }

    private var mainTabs: some View {
        ZStack {
            ForEach(AppTab.allCases) { tab in
                if visitedTabs.contains(tab) {
                    tabContent(tab)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(selectedTab == tab ? 1 : 0)
                        .allowsHitTesting(selectedTab == tab)
                        .accessibilityHidden(selectedTab != tab)
                        .zIndex(selectedTab == tab ? 1 : 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AVDBNativeTabBar(selection: $selectedTab)
        }
        .onChange(of: selectedTab) { _, tab in visitedTabs.insert(tab) }
        .modifier(SceneLayoutReader())
        .tint(JAVDBPalette.accent)
        .sensoryFeedback(.selection, trigger: selectedTab)
    }

    @ViewBuilder private func tabContent(_ tab: AppTab) -> some View {
        switch tab {
        case .home: HomeView()
        case .rankings: RankingsView()
        case .categories: CategoriesView()
        case .actors: ActorsView()
        case .tangxin: TangxinRootView(client: tangxinClient)
        case .me: UserView()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
