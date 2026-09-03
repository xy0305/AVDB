//
//  RankingsView.swift
//  AVDB
//
//  排行榜：TOP250 / 看熱播 / 有碼 / 無碼 / 歐美 / FC2。
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
    var catalogType: MovieCatalogType {
        switch self {
        case .top250, .playback, .censored: return .censored
        case .uncensored: return .uncensored
        case .western: return .western
        case .fc2: return .fc2
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
                Button { showSearch = true } label: {
                    Image(systemName: "magnifyingglass")
                }
            }
        }
        .navigationDestination(isPresented: $showSearch) {
            SearchView()
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
            EmptyStateView(text: "載入排行榜…")
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
                ForEach(Array(vm.movies.enumerated()), id: \.element.id) { idx, movie in
                    NavigationLink {
                        MovieDetailView(movieID: movie.id)
                    } label: {
                        top250Row(rank: idx + 1, movie: movie)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if movie.id == vm.movies.last?.id {
                            Task { await vm.loadMore() }
                        }
                    }
                }
                if vm.isLoading { ProgressView().padding() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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
    private var page = 1
    private var hasMore = true
    private var currentTab: RankingTab = .top250
    private var currentPeriod: RankPeriod = .daily
    private var currentPlayback = "rated"
    private let sdk = JavDBSDK.shared

    func load(tab: RankingTab, period: RankPeriod, playbackFilter: String, force: Bool = false) async {
        if !force, tab == currentTab, period == currentPeriod, playbackFilter == currentPlayback, !movies.isEmpty {
            return
        }
        currentTab = tab
        currentPeriod = period
        currentPlayback = playbackFilter
        page = 1
        hasMore = true
        movies = []
        await fetch()
    }

    func loadMore() async {
        guard hasMore, !isLoading else { return }
        page += 1
        await fetch()
    }

    private func fetch() async {
        isLoading = true
        defer { isLoading = false }
        let list: [Movie]
        switch currentTab {
        case .top250:
            list = (try? await sdk.rankings(type: "0", period: "daily", page: page)) ?? []
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
