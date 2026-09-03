//
//  RankingsView.swift
//  AVDB
//
//  排行榜：TOP250 / 看熱播 / 有碼 / 無碼 / 歐美 / FC2。
//  TOP250 底部篩選對齊官方：類型 / 年份 / 起始排名 / 未看過。
//

import SwiftUI

enum RankingTab: String, CaseIterable, Identifiable {
    case top250, playback, censored, uncensored, western, fc2
    var id: String { rawValue }
    var title: String {
        switch self {
        case .top250: return "TOP250"
        case .playback: return "看熱播"
        case .censored: return "有碼"
        case .uncensored: return "無碼"
        case .western: return "歐美"
        case .fc2: return "FC2"
        }
    }
}

struct RankingsView: View {
    var embedded: Bool = false
    var initialTab: RankingTab = .top250
    @State private var tab: RankingTab
    @State private var period: RankPeriod = .daily
    @State private var playbackFilter: String = "rated"
    @StateObject private var vm = RankingsViewModel()
    @State private var showSearch = false
    @State private var showTopFilter = false

    init(embedded: Bool = false, initialTab: RankingTab = .top250) {
        self.embedded = embedded
        self.initialTab = initialTab
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        Group {
            if embedded {
                rankingBody
            } else {
                NavigationStack { rankingBody }
            }
        }
    }

    private var rankingBody: some View {
        VStack(spacing: 0) {
            UnderlineTabBar(tabs: RankingTab.allCases.map { ($0, $0.title) }, selection: $tab)
                .padding(.top, 4)

            if tab == .playback {
                CapsuleChipBar(
                    tabs: [("rated", "高評價"), ("all", "全部"), ("daily", "日榜"), ("weekly", "周榜"), ("monthly", "月榜")],
                    selection: $playbackFilter
                )
            } else if tab != .top250 {
                CapsuleChipBar(
                    tabs: RankPeriod.allCases.map { ($0, $0.title) },
                    selection: $period
                )
            }

            content
        }
        .background(Color(.systemBackground))
        .navigationTitle("排行榜")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    if tab == .top250 {
                        Button { showTopFilter = true } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                    }
                    Button { showSearch = true } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
        }
        .navigationDestination(isPresented: $showSearch) { SearchView() }
        .sheet(isPresented: $showTopFilter) {
            Top250FilterSheet(vm: vm)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task { await vm.load(tab: tab, period: period, playbackFilter: playbackFilter) }
        .onChange(of: tab) { _, new in
            Task { await vm.load(tab: new, period: period, playbackFilter: playbackFilter) }
        }
        .onChange(of: period) { _, new in
            Task { await vm.load(tab: tab, period: new, playbackFilter: playbackFilter) }
        }
        .onChange(of: playbackFilter) { _, new in
            Task { await vm.load(tab: tab, period: period, playbackFilter: new) }
        }
        .refreshable {
            await vm.load(tab: tab, period: period, playbackFilter: playbackFilter, force: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.movies.isEmpty {
            ContentUnavailableView {
                ProgressView()
            } description: {
                Text("載入排行榜…")
            }
            .frame(maxHeight: .infinity)
        } else if tab == .top250 {
            top250List
        } else {
            ScrollView {
                MoviePosterGrid(
                    movies: vm.movies,
                    showRank: false,
                    onAppearLast: { _ in Task { await vm.loadMore() } }
                )
                .padding(.top, 8)
                if vm.isLoading { ProgressView().padding() }
            }
        }
    }

    private var top250List: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(Array(vm.displayed.enumerated()), id: \.element.id) { idx, movie in
                    NavigationLink {
                        MovieDetailView(movieID: movie.id)
                    } label: {
                        top250Row(rank: vm.startRank + idx, movie: movie)
                    }
                    .buttonStyle(.plain)
                }
                if vm.isLoading { ProgressView().padding() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .safeAreaInset(edge: .bottom) {
            Button { showTopFilter = true } label: {
                Text("篩選")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .background(.bar)
        }
    }

    private func top250Row(rank: Int, movie: Movie) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    JavDBImage(url: movie.coverURL ?? movie.thumbURL)
                        .frame(width: 150, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text("\(rank)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(rank <= 3 ? Color.orange : Color.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                    if let badge = movie.playBadge {
                        Text(badge)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(badge.contains("中字") ? JAVDBPalette.cnsubOrange : JAVDBPalette.playRed)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(6)
                    }
                }
                JavDBImage(url: movie.previewImages?.first?.largeURL ?? movie.coverURL, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Text(movie.displayTitle)
                .font(.system(size: 15))
                .foregroundColor(.primary)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(movie.displayNumber)
                    .foregroundColor(JAVDBPalette.accent)
                if let date = movie.releaseDate {
                    Text("/ \(date)")
                        .foregroundColor(.secondary)
                }
                if let status = movie.magnetStatusText {
                    Text("/ \(status)")
                        .foregroundColor(movie.hasCnsub == true ? JAVDBPalette.cnsubOrange : JAVDBPalette.magnetGreen)
                }
            }
            .font(.system(size: 13))
        }
    }
}

@MainActor
final class RankingsViewModel: ObservableObject {
    @Published var movies: [Movie] = []
    @Published var isLoading = false
    @Published var catalog: String = "all"
    @Published var year: String = ""
    @Published var startRank: Int = 1
    @Published var hideWatched = false

    private var page = 1
    private var hasMore = true
    private var currentTab: RankingTab = .top250
    private var currentPeriod: RankPeriod = .daily
    private var currentPlayback = "rated"
    private var pool: [Movie] = []
    private let sdk = JavDBSDK.shared

    var displayed: [Movie] {
        var list = pool
        if catalog != "all" {
            // 類型篩選走重新拉榜，這裡只做年份 / 看過
        }
        if !year.isEmpty {
            list = list.filter { ($0.releaseDate ?? "").hasPrefix(year) }
        }
        if hideWatched {
            let seen = WatchedStore.ids
            list = list.filter { !seen.contains($0.id) }
        }
        let start = max(startRank - 1, 0)
        if start < list.count {
            return Array(list[start...])
        }
        return []
    }

    func load(tab: RankingTab, period: RankPeriod, playbackFilter: String, force: Bool = false) async {
        if !force, tab == currentTab, period == currentPeriod, playbackFilter == currentPlayback, !movies.isEmpty, tab != .top250 {
            return
        }
        currentTab = tab
        currentPeriod = period
        currentPlayback = playbackFilter
        page = 1
        hasMore = true
        movies = []
        pool = []
        await fetch()
    }

    func loadMore() async {
        guard currentTab != .top250, hasMore, !isLoading else { return }
        page += 1
        await fetch()
    }

    func applyTopFilter() async {
        page = 1
        hasMore = true
        movies = []
        pool = []
        await fetchTop250()
    }

    private func fetch() async {
        if currentTab == .top250 {
            await fetchTop250()
            return
        }
        isLoading = true
        defer { isLoading = false }
        let list: [Movie]
        switch currentTab {
        case .top250:
            list = []
        case .playback:
            let filter = currentPlayback == "rated" ? "all" : currentPlayback
            let period = ["daily", "weekly", "monthly"].contains(currentPlayback) ? currentPlayback : "daily"
            list = (try? await sdk.playbackRankings(filterBy: filter, period: period, page: page)) ?? []
        case .censored:
            list = (try? await sdk.rankings(type: "0", period: currentPeriod.rawValue, page: page)) ?? []
        case .uncensored:
            list = (try? await sdk.rankings(type: "1", period: currentPeriod.rawValue, page: page)) ?? []
        case .western:
            list = (try? await sdk.rankings(type: "2", period: currentPeriod.rawValue, page: page)) ?? []
        case .fc2:
            list = (try? await sdk.rankings(type: "3", period: currentPeriod.rawValue, page: page)) ?? []
        }
        append(list)
    }

    private func fetchTop250() async {
        isLoading = true
        defer { isLoading = false }
        let type: String
        switch catalog {
        case "0", "1", "2", "3": type = catalog
        default: type = "0"
        }
        var all: [Movie] = []
        var seen = Set<String>()
        for p in 1...6 {
            let chunk = (try? await sdk.rankings(type: type, period: "daily", page: p)) ?? []
            if chunk.isEmpty { break }
            for m in chunk where seen.insert(m.id).inserted {
                all.append(m)
            }
            if all.count >= 250 { break }
        }
        pool = Array(all.prefix(250))
        movies = pool
    }

    private func append(_ list: [Movie]) {
        if list.isEmpty {
            hasMore = false
        } else if page == 1 {
            movies = list
        } else {
            let ids = Set(movies.map(\.id))
            movies.append(contentsOf: list.filter { !ids.contains($0.id) })
        }
    }
}

struct Top250FilterSheet: View {
    @ObservedObject var vm: RankingsViewModel
    @Environment(\.dismiss) private var dismiss

    private let types: [(String, String)] = [
        ("all", "全部"), ("0", "有碼"), ("1", "無碼"), ("2", "歐美"), ("3", "FC2"),
    ]
    private let years: [String] = (2008...2026).reversed().map(String.init)
    private let ranks = [1, 51, 101, 151, 201]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("篩選")
                        .font(.title2.bold())

                    chipRow(types.map { ($0.0, $0.1) }, selected: vm.catalog) { vm.catalog = $0 }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                        ForEach(years, id: \.self) { y in
                            chip(y, on: vm.year == y) {
                                vm.year = vm.year == y ? "" : y
                            }
                        }
                    }

                    Text("起始排名:")
                        .font(.headline)
                    chipRow(ranks.map { ("\($0)", "\($0)") }, selected: "\(vm.startRank)") {
                        vm.startRank = Int($0) ?? 1
                    }

                    Toggle(isOn: $vm.hideWatched) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("未標「看過」")
                                .font(.headline)
                            Text("僅查看還未被標記「看過」的影片")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(JAVDBPalette.accent)
                }
                .padding(16)
            }
            .background(Color(.systemGray6))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        Task {
                            await vm.applyTopFilter()
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private func chipRow(_ items: [(String, String)], selected: String, onPick: @escaping (String) -> Void) -> some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.0) { id, title in
                chip(title, on: selected == id) { onPick(id) }
            }
            Spacer(minLength: 0)
        }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(on ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(on ? JAVDBPalette.chipSelected : Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

enum WatchedStore {
    private static let key = "avdb.watched.ids"
    static var ids: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }
    static func mark(_ id: String) {
        var s = ids
        s.insert(id)
        UserDefaults.standard.set(Array(s), forKey: key)
    }
}
