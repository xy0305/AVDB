//
//  JAVDBUI.swift
//  AVDB
//
//  共用 UI：原生 segmented 选择器、海报卡、网格、区块标题。
//  iOS 26 液态玻璃风格：镜面高光描边 + 内发光 + 流体圆角。
//

import SwiftUI

enum JAVDBPalette {
    static let accent = Color.accentColor
    static let magnetGreen = Color(red: 0.20, green: 0.62, blue: 0.38)
    static let cnsubOrange = Color(red: 0.90, green: 0.55, blue: 0.12)
    static let playRed = Color(red: 0.78, green: 0.22, blue: 0.28)
    static let chipGray = Color(.systemGray6)
    static let chipSelected = Color.accentColor
}

enum MovieCatalogType: String, CaseIterable, Identifiable {
    case censored = "0"
    case uncensored = "1"
    case western = "2"
    case fc2 = "3"
    case anime = "4"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .censored: return "有碼"
        case .uncensored: return "無碼"
        case .western: return "歐美"
        case .fc2: return "FC2"
        case .anime: return "動漫"
        }
    }
}

enum RankPeriod: String, CaseIterable, Identifiable {
    case daily, weekly, monthly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .daily: return "日榜"
        case .weekly: return "周榜"
        case .monthly: return "月榜"
        }
    }
}

/// 顶部文字 Tab（原生分段选择器；项多时横向原生按钮）。保留旧名以兼容调用点。
struct UnderlineTabBar<Tab: Hashable>: View {
    let tabs: [(Tab, String)]
    @Binding var selection: Tab

    var body: some View {
        SegmentedTabBar(tabs: tabs, selection: $selection)
    }
}

/// 胶囊筛选条（系统原生分段控件，不滚动、不拖动）。
struct CapsuleChipBar<Tab: Hashable>: View {
    let tabs: [(Tab, String)]
    @Binding var selection: Tab

    var body: some View {
        if tabs.count <= 4 {
            HStack(spacing: 0) {
                ForEach(tabs, id: \.0) { tab, title in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            selection = tab
                        }
                    } label: {
                        Text(title)
                            .font(.footnote.weight(selection == tab ? .semibold : .regular))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(selection == tab ? Color.white : Color.secondary)
                            .background {
                                if selection == tab {
                                    Capsule(style: .continuous)
                                        .fill(Color.accentColor.gradient)
                                        .overlay {
                                            Capsule(style: .continuous)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [.white.opacity(0.28), .clear],
                                                        startPoint: .top,
                                                        endPoint: .center
                                                    )
                                                )
                                        }
                                        .overlay {
                                            Capsule(style: .continuous)
                                                .strokeBorder(.white.opacity(0.35), lineWidth: 0.6)
                                        }
                                        .shadow(color: Color.accentColor.opacity(0.3), radius: 6, y: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .liquidCapsule(glowOpacity: 0.16, shadowRadius: 10, shadowY: 4)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        } else {
            SegmentChipBar(tabs: tabs, selection: $selection)
        }
    }
}

/// 顶部分段选择器（原生 SegmentedControl 风格）。
struct SegmentedTabBar<Tab: Hashable>: View {
    let tabs: [(Tab, String)]
    @Binding var selection: Tab

    var body: some View {
        if tabs.count <= 4 {
            HStack(spacing: 0) {
                ForEach(tabs, id: \.0) { tab, title in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            selection = tab
                        }
                    } label: {
                        Text(title)
                            .font(.footnote.weight(selection == tab ? .semibold : .regular))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(selection == tab ? Color.white : Color.secondary)
                            .background {
                                if selection == tab {
                                    Capsule(style: .continuous)
                                        .fill(Color.accentColor.gradient)
                                        .overlay {
                                            Capsule(style: .continuous)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [.white.opacity(0.28), .clear],
                                                        startPoint: .top,
                                                        endPoint: .center
                                                    )
                                                )
                                        }
                                        .overlay {
                                            Capsule(style: .continuous)
                                                .strokeBorder(.white.opacity(0.35), lineWidth: 0.6)
                                        }
                                        .shadow(color: Color.accentColor.opacity(0.3), radius: 6, y: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .liquidCapsule(glowOpacity: 0.16, shadowRadius: 10, shadowY: 4)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        } else {
            // 多标签：非滚动、等宽原生按钮，底部玻璃指示条
            HStack(spacing: 0) {
                ForEach(tabs, id: \.0) { tab, title in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            selection = tab
                        }
                    } label: {
                        Text(title)
                            .font(.footnote.weight(selection == tab ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(selection == tab ? Color.accentColor : Color.secondary)
                            .background {
                                if selection == tab {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.1))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [.white.opacity(0.3), .clear],
                                                        startPoint: .top,
                                                        endPoint: .center
                                                    )
                                                )
                                        }
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
    }
}

/// 分段筛选（原生 SegmentedControl，最多 4 项）。
struct SegmentChipBar<Tab: Hashable>: View {
    let tabs: [(Tab, String)]
    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tabs, id: \.0) { tab, title in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        selection = tab
                    }
                } label: {
                    Text(title)
                        .font(.subheadline.weight(selection == tab ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundStyle(selection == tab ? Color.white : Color.primary)
                        .background {
                            if selection == tab {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.accentColor.gradient)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(
                                                LinearGradient(
                                                    colors: [.white.opacity(0.28), .clear],
                                                    startPoint: .top,
                                                    endPoint: .center
                                                )
                                            )
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(.white.opacity(0.35), lineWidth: 0.6)
                                    }
                                    .shadow(color: Color.accentColor.opacity(0.25), radius: 5, y: 2)
                            } else {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(
                                                LinearGradient(
                                                    colors: [.white.opacity(0.2), .clear],
                                                    startPoint: .top,
                                                    endPoint: .center
                                                )
                                            )
                                    }
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .liquidCapsule(glowOpacity: 0.14, shadowRadius: 10, shadowY: 4)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

/// 三列海报卡（液态玻璃镜面边缘 + 语义字体）。
struct MoviePosterCard: View {
    let movie: Movie
    var rank: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                JavDBImage(url: movie.coverURL ?? movie.thumbURL)
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .aspectRatio(0.72, contentMode: .fill)
                    .frame(minHeight: 140)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .glassEdge(cornerRadius: 10, opacity: 0.35)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)

                // 排名角标
                if let rank {
                    Text("\(rank)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(rank <= 3 ? Color.orange.gradient : Color.black.opacity(0.6).gradient)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [.white.opacity(0.25), .clear],
                                                startPoint: .top,
                                                endPoint: .center
                                            )
                                        )
                                }
                        }
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let badge = movie.playBadge {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(
                                    (badge.contains("中字")
                                        ? JAVDBPalette.cnsubOrange
                                        : JAVDBPalette.playRed
                                    ).gradient
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [.white.opacity(0.25), .clear],
                                                startPoint: .top,
                                                endPoint: .center
                                            )
                                        )
                                }
                        }
                        .padding(5)
                }
            }

            Text(movie.displayTitle)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 36, alignment: .top)

            Text(movie.displayNumber)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
                .lineLimit(1)

            if let date = movie.releaseDate, !date.isEmpty {
                Text(date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                if let status = movie.magnetStatusText {
                    Text(status)
                        .font(.caption2)
                        .foregroundColor(movie.hasCnsub == true ? JAVDBPalette.cnsubOrange : JAVDBPalette.magnetGreen)
                }
                if movie.isNewMagnet {
                    Text("新種")
                        .font(.caption2)
                        .foregroundColor(JAVDBPalette.magnetGreen)
                }
            }
        }
    }
}

/// 三列网格
struct MoviePosterGrid: View {
    let movies: [Movie]
    var showRank: Bool = false
    var onAppearLast: ((Movie) -> Void)? = nil

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(Array(movies.enumerated()), id: \.element.id) { idx, movie in
                NavigationLink {
                    MovieDetailView(movieID: movie.id)
                } label: {
                    MoviePosterCard(movie: movie, rank: showRank ? idx + 1 : nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onAppear {
                    if movie.id == movies.last?.id {
                        onAppearLast?(movie)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
    }
}

struct SectionHeaderBar: View {
    let title: String
    var trailing: String? = "全部"
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            if let trailing {
                Button(action: { action?() }) {
                    HStack(spacing: 2) {
                        Text(trailing)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .liquidGlassFlat(cornerRadius: 12, material: .thinMaterial)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }
}

struct EmptyStateView: View {
    let text: String
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// 液态玻璃筛选芯片（通用）
struct LiquidFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(isSelected ? .semibold : .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background {
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(Color.accentColor.gradient)
                            .overlay {
                                Capsule(style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [.white.opacity(0.28), .clear],
                                            startPoint: .top,
                                            endPoint: .center
                                        )
                                    )
                            }
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(.white.opacity(0.35), lineWidth: 0.6)
                            }
                            .shadow(color: Color.accentColor.opacity(0.3), radius: 5, y: 2)
                    } else {
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Capsule(style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [.white.opacity(0.22), .clear],
                                            startPoint: .top,
                                            endPoint: .center
                                        )
                                    )
                            }
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [
                                                .white.opacity(0.4),
                                                .white.opacity(0.15),
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 0.6
                                    )
                            }
                    }
                }
        }
        .buttonStyle(.plain)
    }
}
