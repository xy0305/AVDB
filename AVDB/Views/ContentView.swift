//
//  ContentView.swift
//  AVDB
//
//  主界面：底部 Tab 对齐官方 App（首页 / 排行榜 / 類別 / 演員 / 我的）。
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("首頁", systemImage: selectedTab == 0 ? "heart.fill" : "heart") }
                .tag(0)

            RankingsView()
                .tabItem { Label("排行榜", systemImage: "chart.bar.fill") }
                .tag(1)

            CategoriesView()
                .tabItem { Label("類別", systemImage: "pyramid.fill") }
                .tag(2)

            ActorsView()
                .tabItem { Label("演員", systemImage: "person.crop.rectangle.stack.fill") }
                .tag(3)

            UserView()
                .tabItem { Label("我的", systemImage: "person.circle") }
                .tag(4)
        }
        .tint(JAVDBPalette.accent)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
