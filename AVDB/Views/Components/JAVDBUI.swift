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

/// 官方下划线 Tab（全部 / 有碼 / 無碼 …）——滑动指示条带弹簧过渡
struct UnderlineTabBar<Tab: Hashable>: View {
    let tabs: [(Tab, String)]
    @Binding var selection: Tab
    /// 排行等少量标签应铺满且不可拖；类别/演员字母多时才横向滚动。
    var scrolls: Bool = true
    @Namespace private var underlineNS

    var body: some View {
        VStack(spacing: 0) {
            if scrolls {
                ScrollView(.horizontal, showsIndicators: false) {
                    tabRow(flexible: false)
                        .padding(.horizontal, 8)
                }
            } else {
                tabRow(flexible: true)
                    .padding(.horizontal, 4)
                    .tabSwipe(tabs: tabs.map(\.0), selection: $selection)
            }
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
    }

    private func tabRow(flexible: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.0) { tab, title in
                Button {
                    GlassHaptic.tap()
                    withAnimation(GlassMotion.select) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 8) {
                        Text(title)
                            .font(.subheadline.weight(selection == tab ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(flexible ? 0.7 : 1)
                            .foregroundStyle(selection == tab ? Color.accentColor : Color.primary)
                            .frame(maxWidth: flexible ? .infinity : nil)
                        ZStack {
                            if selection == tab {
                                Capsule(style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.accentColor, Color.accentColor.opacity(0.55)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .matchedGeometryEffect(id: "tab-underline", in: underlineNS)
                            } else {
                                Color.clear.frame(height: 2)
                            }
                        }
                        .frame(height: 2)
                    }
                    .padding(.horizontal, flexible ? 2 : 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
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
    @Namespace private var chipNS

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.0) { tab, title in
                Button {
                    GlassHaptic.tap()
                    withAnimation(GlassMotion.select) {
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
                                    .matchedGeometryEffect(id: "chip-seg", in: chipNS)
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
        .tabSwipe(tabs: tabs.map(\.0), selection: $selection)
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
    @Namespace private var chipNS

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.0) { tab, title in
                Button {
                    GlassHaptic.tap()
                    withAnimation(GlassMotion.select) {
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
                                    .matchedGeometryEffect(id: "chip-seg", in: chipNS)
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
        .tabSwipe(tabs: tabs.map(\.0), selection: $selection)
    }
}

/// 条子固定，左右滑只切选中项，不把按钮拖走。
private struct TabSwipeModifier<Tab: Hashable>: ViewModifier {
    let tabs: [Tab]
    @Binding var selection: Tab

    func body(content: Content) -> some View {
        content.highPriorityGesture(
            DragGesture(minimumDistance: 24, coordinateSpace: .local)
                .onEnded { value in
                    let dx = value.translation.width
                    guard abs(dx) > abs(value.translation.height), abs(dx) > 40 else { return }
                    guard let idx = tabs.firstIndex(of: selection) else { return }
                    let next = dx < 0 ? idx + 1 : idx - 1
                    guard tabs.indices.contains(next) else { return }
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        selection = tabs[next]
                    }
                }
        )
    }
}

private extension View {
    func tabSwipe<Tab: Hashable>(tabs: [Tab], selection: Binding<Tab>) -> some View {
        modifier(TabSwipeModifier(tabs: tabs, selection: selection))
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

/// 三列海报卡 —— 内容干净，封面带高光边、角标玻璃化、按压回弹
struct MoviePosterCard: View {
    let movie: Movie
    var rank: Int? = nil
    @State private var pressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ClippedAspectFill(aspectRatio: 0.72) {
                JavDBImage(url: movie.coverURL ?? movie.thumbURL)
                    .overlay {
                        LinearGradient(
                            colors: [.white.opacity(0.18), .clear, .black.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                    .overlay(alignment: .topLeading) {
                        if let rank {
                            Text("\(rank)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    rank <= 3
                                        ? AnyShapeStyle(
                                            LinearGradient(
                                                colors: [Color.orange, Color.orange.opacity(0.75)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        : AnyShapeStyle(.ultraThinMaterial)
                                )
                                .foregroundStyle(rank <= 3 ? Color.white : Color.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
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
                                .background(
                                    badge.contains("中字")
                                        ? JAVDBPalette.cnsubOrange
                                        : JAVDBPalette.playRed
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .strokeBorder(.white.opacity(0.28), lineWidth: 0.5)
                                }
                                .padding(5)
                        }
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.4), .white.opacity(0.05), .black.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.7
                    )
            }
            .shadow(color: .black.opacity(pressed ? 0.04 : 0.12), radius: pressed ? 2 : 8, y: pressed ? 1 : 4)
            .scaleEffect(pressed ? 0.96 : 1)
            .animation(GlassMotion.press, value: pressed)

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
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(JAVDBPalette.magnetGreen)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(JAVDBPalette.magnetGreen.opacity(0.14), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.01, pressing: { pressing in
            pressed = pressing
        }, perform: {})
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
                .staggerAppear(index: idx % 12)
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
        GlassSectionHeader(
            title: title,
            trailingTitle: trailing,
            action: action
        )
        .padding(.horizontal, AdaptiveLayout.horizontalPadding)
    }
}

struct EmptyStateView: View {
    let text: String
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                SoftPulseRing(color: .blue.opacity(0.45))
                    .frame(width: 56, height: 56)
                ProgressView()
            }
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
