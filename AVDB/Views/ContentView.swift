//
//  ContentView.swift
//  AVDB
//
//  主界面：底部 Tab 导航（首页/搜索/片单/演员/我的）。
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }
                .tag(0)

            SearchView()
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
                .tag(1)

            ListsView()
                .tabItem { Label("片单", systemImage: "list.bullet") }
                .tag(2)

            ActorsView()
                .tabItem { Label("演员", systemImage: "person.2.fill") }
                .tag(3)

            UserView()
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
                .tag(4)
        }
        .tint(.orange)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
