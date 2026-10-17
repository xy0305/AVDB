//
//  ContentView.swift
//  AVDB
//
//  系统 TabView：iOS 26 自动使用 Liquid Glass Tab Bar，
//  不再手绘悬浮条。
//

import SwiftUI

enum AppTab: Int, CaseIterable, Identifiable {
    case home, rankings, categories, actors, me
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home: return "首頁"
        case .rankings: return "排行"
        case .categories: return "類別"
        case .actors: return "演員"
        case .me: return "我的"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .rankings: return "trophy"
        case .categories: return "square.grid.2x2"
        case .actors: return "person.2"
        case .me: return "person.crop.circle"
        }
    }
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .home

    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--subtitle-controls-fixture"),
           let url = Bundle.main.url(forResource: "neutral-subtitle", withExtension: "mp4") {
            // Exercise the production route-owned orientation host, not a DEBUG-only
            // .all mask that can leave the iPhone event window portrait.
            KSChromePlayer(url: url, title: "中性播放器测试", subtitle: "原文件 / 原画", onSelectSource: {})
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
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label(
                        AppTab.home.title,
                        systemImage: selectedTab == .home ? "house.fill" : AppTab.home.icon
                    )
                }
                .tag(AppTab.home)

            RankingsView()
                .tabItem {
                    Label(
                        AppTab.rankings.title,
                        systemImage: selectedTab == .rankings ? "trophy.fill" : AppTab.rankings.icon
                    )
                }
                .tag(AppTab.rankings)

            CategoriesView()
                .tabItem {
                    Label(
                        AppTab.categories.title,
                        systemImage: selectedTab == .categories ? "square.grid.2x2.fill" : AppTab.categories.icon
                    )
                }
                .tag(AppTab.categories)

            ActorsView()
                .tabItem {
                    Label(
                        AppTab.actors.title,
                        systemImage: selectedTab == .actors ? "person.2.fill" : AppTab.actors.icon
                    )
                }
                .tag(AppTab.actors)

            UserView()
                .tabItem {
                    Label(
                        AppTab.me.title,
                        systemImage: selectedTab == .me ? "person.crop.circle.fill" : AppTab.me.icon
                    )
                }
                .tag(AppTab.me)
        }
        .modifier(SceneLayoutReader())
        .tint(JAVDBPalette.accent)
        .sensoryFeedback(.selection, trigger: selectedTab)
        .modifier(LiquidGlassTabBarModifier())
    }
}

/// iOS 26：滚动时系统液态玻璃 Tab Bar 自动收起。
private struct LiquidGlassTabBarModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !AdaptiveLayout.isPad {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
