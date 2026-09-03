//
//  ContentView.swift
//  AVDB
//
//  底部悬浮液态玻璃 Tab（对齐 CamWeb），图标更醒目。
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

    var selectedIcon: String {
        switch self {
        case .home: return "house.fill"
        case .rankings: return "trophy.fill"
        case .categories: return "square.grid.2x2.fill"
        case .actors: return "person.2.fill"
        case .me: return "person.crop.circle.fill"
        }
    }
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .home: HomeView()
                case .rankings: RankingsView()
                case .categories: CategoriesView()
                case .actors: ActorsView()
                case .me: UserView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaPadding(.bottom, 76)

            FloatingGlassTabBar(selection: $selectedTab)
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
        }
        .ignoresSafeArea(.keyboard)
        .tint(JAVDBPalette.accent)
    }
}

struct FloatingGlassTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: selection == tab ? tab.selectedIcon : tab.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .scaleEffect(selection == tab ? 1.12 : 1)
                        Text(tab.title)
                            .font(.system(size: 10, weight: selection == tab ? .semibold : .medium))
                    }
                    .foregroundStyle(selection == tab ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.42),
                                    Color.white.opacity(0.08),
                                    Color.white.opacity(0.18),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.overlay)
                }
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.38), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
