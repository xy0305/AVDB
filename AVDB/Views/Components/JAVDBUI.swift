//
//  JAVDBUI.swift
//  AVDB
//
//  共用 UI：分段选择器、海报卡、网格、区块标题。
//  原则：内容（海报、文字）用正常底；悬浮控件（Tab、芯片）用玻璃。
//

import SwiftUI

// MARK: - iPad / 自适应布局

/// 根据设备提供自适应布局参数。
enum AdaptiveLayout {
    /// 是否 iPad（或 Mac Catalyst 等大屏）
    static var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// 内容区最大宽度（iPad 居中限制，避免无限拉伸）
    static var contentMaxWidth: CGFloat { 1100 }

    /// 水平内边距
    static var horizontalPadding: CGFloat { isPad ? 24 : 16 }

    /// 网格水平内边距
    static var gridPadding: CGFloat { isPad ? 20 : 12 }
}

enum JAVDBPalette {
    static let accent = Color.accentColor
    static let magnetGreen = Color(red: 0.20, green: 0.62, blue: 0.38)
    static let cnsubOrange = Color(red: 0.90, green: 0.55, blue: 0.12)
    static let playRed = Color(red: 0.78, green: 0.22, blue: 0.28)
    static let chipGray = Color(.systemGray6)
    static let chipSelected = Color.accentColor
}

enum MovieCatalogType: String, CaseIterable, Identifiable {
    case all = "all"
    case censored = "0"
    case uncensored = "1"
    case western = "2"
    case fc2 = "3"
    case anime = "4"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .censored: return "有碼"
        case .uncensored: return "無碼"
        case .western: return "歐美"
        case .fc2: return "FC2"
        case .anime: return "動漫"
        }
    }

    /// 類別頁不展示「全部」，只保留有碼/無碼/歐美/FC2/動漫。
    static var categoryTabs: [MovieCatalogType] {
        [.censored, .uncensored, .western, .fc2, .anime]
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

/// 官方下划线 Tab（全部 / 有碼 / 無碼 …）
struct UnderlineTabBar<Tab: Hashable>: View {
    let tabs: [(Tab, String)]
    @Binding var selection: Tab

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(tabs, id: \.0) { tab, title in
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                selection = tab
                            }
                        } label: {
                            VStack(spacing: 8) {
                                Text(title)
                                    .font(.subheadline.weight(selection == tab ? .semibold : .regular))
                                    .foregroundStyle(selection == tab ? Color.accentColor : Color.primary)
                                Rectangle()
                                    .fill(selection == tab ? Color.accentColor : Color.clear)
                                    .frame(height: 2)
                            }
                            .padding(.horizontal, 14)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
            }
            Divider()
        }
    }
}

/// 胶囊筛选条（≤4 项用分段控件，>4 用等宽按钮）。
struct CapsuleChipBar<Tab: Hashable>: View {
    let tabs: [(Tab, String)]
    @Binding var selection: Tab

    var body: some View {
        if tabs.count <= 4 {
            SegmentedControlBar(tabs: tabs, selection: $selection)
        } else {
            SegmentChipBar(tabs: tabs, selection: $selection)
        }
    }
}

/// ≤4 项分段控件：悬浮玻璃底 + 选中实心胶囊
private struct SegmentedControlBar<Tab: Hashable>: View {
    let tabs: [(Tab, String)]
    @Binding var selection: Tab

    var body: some View {
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
                        .padding(.vertical, 7)
                        .foregroundStyle(selection == tab ? Color.white : Color.secondary)
                        .background {
                            if selection == tab {
                                Capsule(style: .continuous)
                                    .fill(Color.accentColor)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .liquidGlass()
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

/// 顶部分段选择器（兼容旧名）。
struct SegmentedTabBar<Tab: Hashable>: View {
    let tabs: [(Tab, String)]
    @Binding var selection: Tab

    var body: some View {
        if tabs.count <= 4 {
            SegmentedControlBar(tabs: tabs, selection: $selection)
        } else {
            // 多标签：等宽按钮，选中态用轻底色指示（非悬浮，不用玻璃）
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
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.1))
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

/// >4 项的分段筛选。
struct SegmentChipBar<Tab: Hashable>: View {
    let tabs: [(Tab, String)]
    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.0) { tab, title in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        selection = tab
                    }
                } label: {
                    Text(title)
                        .font(.subheadline.weight(selection == tab ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .foregroundStyle(selection == tab ? Color.white : Color.primary)
                        .background {
                            if selection == tab {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.accentColor)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .liquidGlass()
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

/// 先用无内容视图定宽高，再 overlay 图片。避免 Image 按原图像素撑开格子。
struct ClippedAspectFill<Content: View>: View {
    var aspectRatio: CGFloat
    var cornerRadius: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay { content() }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// 三列海报卡 —— 内容，不用玻璃，干净的圆角图片 + 文字
struct MoviePosterCard: View {
    let movie: Movie
    var rank: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ClippedAspectFill(aspectRatio: 0.72) {
                JavDBImage(url: movie.coverURL ?? movie.thumbURL)
                    .overlay(alignment: .topLeading) {
                        if let rank {
                            Text("\(rank)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(rank <= 3 ? Color.orange : Color.black.opacity(0.65))
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
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
                                .background(
                                    badge.contains("中字")
                                        ? JAVDBPalette.cnsubOrange
                                        : JAVDBPalette.playRed
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .padding(5)
                        }
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
                .frame(maxWidth: .infinity, alignment: .leading)

            if let date = movie.releaseDate, !date.isEmpty {
                Text(date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 自适应列数海报网格（iPhone 3 列，iPad 4–5 列）
struct MoviePosterGrid: View {
    let movies: [Movie]
    var showRank: Bool = false
    var onAppearLast: ((Movie) -> Void)? = nil

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var columnCount: Int {
        sizeClass == .regular ? 5 : 3
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12), count: columnCount)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(Array(movies.enumerated()), id: \.element.id) { idx, movie in
                NavigationLink {
                    MovieDetailView(movieID: movie.id)
                } label: {
                    MoviePosterCard(movie: movie, rank: showRank ? idx + 1 : nil)
                }
                .buttonStyle(.plain)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onAppear {
                    if movie.id == movies.last?.id {
                        onAppearLast?(movie)
                    }
                }
            }
        }
        .padding(.horizontal, AdaptiveLayout.gridPadding)
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
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AdaptiveLayout.horizontalPadding)
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
