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
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label(AppTab.home.title, systemImage: AppTab.home.icon) }
                .tag(AppTab.home)

            RankingsView()
                .tabItem { Label(AppTab.rankings.title, systemImage: AppTab.rankings.icon) }
                .tag(AppTab.rankings)

            CategoriesView()
                .tabItem { Label(AppTab.categories.title, systemImage: AppTab.categories.icon) }
                .tag(AppTab.categories)

            ActorsView()
                .tabItem { Label(AppTab.actors.title, systemImage: AppTab.actors.icon) }
                .tag(AppTab.actors)

            UserView()
                .tabItem { Label(AppTab.me.title, systemImage: AppTab.me.icon) }
                .tag(AppTab.me)
        }
        .tint(JAVDBPalette.accent)
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
