//
//  JAVDBUI.swift
//  AVDB
//
//  共用 UI：原生 segmented 选择器、海报卡、网格、区块标题。
//  全部使用系统控件与语义字体，避免自绘下划线 / 胶囊造成的低质感。
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
            Picker("", selection: $selection) {
                ForEach(tabs, id: \.0) { tab, title in
                    Text(title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
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
            Picker("", selection: $selection) {
                ForEach(tabs, id: \.0) { tab, title in
                    Text(title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        } else {
            // 多标签：非滚动、等宽原生按钮，避免横向拖动
            HStack(spacing: 0) {
                ForEach(tabs, id: \.0) { tab, title in
                    Button {
                        selection = tab
                    } label: {
                        Text(title)
                            .font(.footnote.weight(selection == tab ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(selection == tab ? Color.accentColor : Color.secondary)
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(selection == tab ? Color.accentColor : Color.clear)
                                    .frame(height: 2)
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
        HStack(spacing: 8) {
            ForEach(tabs, id: \.0) { tab, title in
                Button {
                    selection = tab
                } label: {
                    Text(title)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            selection == tab ? Color(.tertiarySystemFill) : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(.secondarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

/// 三列海报卡（系统语义字体 + 原生圆角）。
struct MoviePosterCard: View {
    let movie: Movie
    var rank: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                JavDBImage(url: movie.coverURL ?? movie.thumbURL)
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .aspectRatio(0.72, contentMode: .fill)
                    .frame(minHeight: 140)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if let rank {
                    Text("\(rank)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(rank <= 3 ? Color.orange : Color.black.opacity(0.65))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(6)
                }

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

