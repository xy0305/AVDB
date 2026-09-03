//
//  JAVDBUI.swift
//  AVDB
//
//  对齐官方 App 的共用 UI：下划线 Tab、胶囊筛选、三列海报卡。
//

import SwiftUI

enum JAVDBPalette {
    static let accent = Color(red: 0.18, green: 0.45, blue: 0.95)
    static let magnetGreen = Color(red: 0.20, green: 0.62, blue: 0.38)
    static let cnsubOrange = Color(red: 0.90, green: 0.55, blue: 0.12)
    static let playRed = Color(red: 0.78, green: 0.22, blue: 0.28)
    static let chipGray = Color(white: 0.93)
    static let chipSelected = Color(red: 0.22, green: 0.48, blue: 0.90)
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

/// 顶部文字 Tab（下划线）
struct UnderlineTabBar<Tab: Hashable>: View {
    let tabs: [(Tab, String)]
    @Binding var selection: Tab

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(tabs, id: \.0) { tab, title in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { selection = tab }
                    } label: {
                        VStack(spacing: 8) {
                            Text(title)
                                .font(.system(size: 16, weight: selection == tab ? .semibold : .regular))
                                .foregroundColor(selection == tab ? JAVDBPalette.accent : .secondary)
                            Rectangle()
                                .fill(selection == tab ? JAVDBPalette.accent : Color.clear)
                                .frame(height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

/// 胶囊筛选条
struct CapsuleChipBar<Tab: Hashable>: View {
    let tabs: [(Tab, String)]
    @Binding var selection: Tab

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tabs, id: \.0) { tab, title in
                    Button {
                        selection = tab
                    } label: {
                        Text(title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(selection == tab ? .primary : .secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(selection == tab ? Color(.systemGray5) : Color(.systemGray6))
                            )
                            .overlay(
                                Capsule().stroke(selection == tab ? Color(.systemGray3) : Color.clear, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

/// 三列海报卡（番号蓝字 + 日期 + 磁链状态 + 播放角标）
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
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                if let rank {
                    Text("\(rank)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(rank <= 3 ? Color.orange : Color.black.opacity(0.65))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(6)
                }

                if let badge = movie.playBadge {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(badge.contains("中字") ? JAVDBPalette.cnsubOrange : JAVDBPalette.playRed)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .padding(5)
                }
            }

            Text(movie.displayTitle)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 32, alignment: .top)

            Text(movie.displayNumber)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(JAVDBPalette.accent)
                .lineLimit(1)

            if let date = movie.releaseDate, !date.isEmpty {
                Text(date)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 4) {
                if let status = movie.magnetStatusText {
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundColor(movie.hasCnsub == true ? JAVDBPalette.cnsubOrange : JAVDBPalette.magnetGreen)
                }
                if movie.isNewMagnet {
                    Text("新種")
                        .font(.system(size: 11))
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
                .font(.system(size: 17, weight: .semibold))
            Spacer()
            if let trailing {
                Button(action: { action?() }) {
                    HStack(spacing: 2) {
                        Text(trailing)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
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
            Text(text).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
