//
//  ContentView.swift
//  AVDB
//
//  底部悬浮液态玻璃 Tab（iOS 26 风格），图标更醒目。
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
            // 液态玻璃氛围背景：柔和渐变洗色
            LiquidGlassBackground()
                .ignoresSafeArea()

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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 88)
            }

            FloatingGlassTabBar(selection: $selectedTab)
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
        }
        .ignoresSafeArea(.keyboard)
        .tint(JAVDBPalette.accent)
    }
}

/// 全局液态玻璃氛围背景：极淡的多色渐变洗色
struct LiquidGlassBackground: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)

            // 左上淡蓝光晕
            RadialGradient(
                colors: [Color(red: 0.45, green: 0.65, blue: 0.95).opacity(0.12), .clear],
                center: UnitPoint(x: 0.15, y: 0.05),
                startRadius: 0,
                endRadius: 320
            )

            // 右上淡紫光晕
            RadialGradient(
                colors: [Color(red: 0.65, green: 0.5, blue: 0.9).opacity(0.08), .clear],
                center: UnitPoint(x: 0.9, y: 0.0),
                startRadius: 0,
                endRadius: 280
            )

            // 底部淡青光晕
            RadialGradient(
                colors: [Color(red: 0.3, green: 0.75, blue: 0.8).opacity(0.06), .clear],
                center: UnitPoint(x: 0.5, y: 1.0),
                startRadius: 0,
                endRadius: 300
            )
        }
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
                        ZStack {
                            if selection == tab {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.18))
                                    .frame(width: 40, height: 40)
                                    .overlay {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [.white.opacity(0.35), .clear],
                                                    startPoint: .top,
                                                    endPoint: .center
                                                )
                                            )
                                    }
                                    .overlay {
                                        Circle()
                                            .strokeBorder(.white.opacity(0.4), lineWidth: 0.6)
                                    }
                            }
                            Image(systemName: selection == tab ? tab.selectedIcon : tab.icon)
                                .font(.system(size: 20, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .scaleEffect(selection == tab ? 1.1 : 1)
                        }
                        .frame(height: 40)
                        Text(tab.title)
                            .font(.system(size: 10, weight: selection == tab ? .semibold : .medium))
                    }
                    .foregroundStyle(selection == tab ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .liquidCapsule(
            material: .ultraThinMaterial,
            edgeOpacity: 0.52,
            glowOpacity: 0.24,
            shadowRadius: 20,
            shadowY: 10
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
