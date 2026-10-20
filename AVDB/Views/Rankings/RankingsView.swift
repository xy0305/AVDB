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
    @State private var playbackFilter: String = "high_score"
    @State private var playbackPeriod: RankPeriod = .daily
    @State private var rankingKind: String = "movies"
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
            Text("排行榜")
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AdaptiveLayout.horizontalPadding)
                .padding(.vertical, 8)
            HStack {
                Text("当前来源 · JavDB").font(.caption).foregroundStyle(.secondary)
                Spacer()
                NavigationLink { JavRankingView(rankingsOnly: true) } label: {
                    Label("JAV Ranking 完整首页", systemImage: "house")
                        .font(.subheadline)
                }.accessibilityIdentifier("javranking-home-entry")
                NavigationLink { JRBackendView(route: "topics", title: "全部榜单") } label: {
                    Text("全部榜单").font(.caption)
                }.accessibilityIdentifier("javranking-topics-shortcut")
            }.padding(.horizontal, AdaptiveLayout.horizontalPadding).padding(.bottom, 8)
            HStack {
                Text("新增来源 · MissAV").font(.caption).foregroundStyle(.secondary)
                Spacer()
                NavigationLink { MissAVRankingView() } label: {
                    Label("MissAV 日 / 周 / 月排行", systemImage: "list.number")
                        .font(.subheadline)
                }
            }.padding(.horizontal, AdaptiveLayout.horizontalPadding).padding(.bottom, 8)
            HStack {
                Text("新增来源 · JAVLibrary").font(.caption).foregroundStyle(.secondary)
                Spacer()
                NavigationLink { JAVLibraryRankingView() } label: {
                    Label("JAVLibrary 最想要 / 高评价 / 女优收藏", systemImage: "list.number")
                        .font(.subheadline)
                }.accessibilityIdentifier("javlibrary-ranking-entry")
            }.padding(.horizontal, AdaptiveLayout.horizontalPadding).padding(.bottom, 8)
            UnderlineTabBar(tabs: RankingTab.allCases.map { ($0, $0.title) }, selection: $tab, scrolls: false)
                .padding(.top, 4)

            if tab == .playback {
                VStack(spacing: 0) {
                    CapsuleChipBar(
                        tabs: [("high_score", "高評價"), ("all", "全部")],
                        selection: $playbackFilter
                    )
                    CapsuleChipBar(
                        tabs: RankPeriod.allCases.map { ($0, $0.title) },
                        selection: $playbackPeriod
                    )
                }
            } else if tab != .top250 {
                VStack(spacing: 0) {
                    CapsuleChipBar(
                        tabs: RankPeriod.allCases.map { ($0, $0.title) },
                        selection: $period
                    )
                    if tab == .censored {
                        CapsuleChipBar(
                            tabs: [("movies", "作品"), ("actors", "演員月榜")],
                            selection: $rankingKind
                        )
                    }
                }
            }

            if let error = vm.errorMessage {
                VStack(spacing: 8) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout).multilineTextAlignment(.center)
                    Button("重试") {
                        Task {
                            if vm.movies.isEmpty && vm.actors.isEmpty { await reload(force: true) }
                            else { await vm.loadMore() }
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .accessibilityIdentifier("native-ranking-error")
            }
            content
        }
        .background {
            LiquidGlassBackground()
        }
        .frame(maxWidth: AdaptiveLayout.contentMaxWidth)
        .frame(maxWidth: .infinity)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if tab == .top250 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showTopFilter = true } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSearch = true } label: {
                    Image(systemName: "magnifyingglass")
                }
            }
        }
        .navigationDestination(isPresented: $showSearch) { SearchView() }
        .sheet(isPresented: $showTopFilter) {
            Top250FilterSheet(vm: vm)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task { await reload() }
        .onChange(of: tab) { _, _ in Task { await reload() } }
        .onChange(of: period) { _, _ in Task { await reload() } }
        .onChange(of: playbackFilter) { _, _ in Task { await reload() } }
        .onChange(of: playbackPeriod) { _, _ in Task { await reload() } }
        .onChange(of: rankingKind) { _, _ in Task { await reload() } }
        .refreshable { await reload(force: true) }
    }

    private func reload(force: Bool = false) async {
        await vm.load(
            tab: tab,
            period: period,
            playbackFilter: playbackFilter,
            playbackPeriod: playbackPeriod,
            rankingKind: rankingKind,
            force: force
        )
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.movies.isEmpty && vm.actors.isEmpty {
            ContentUnavailableView {
                ProgressView()
            } description: {
                Text("載入排行榜…")
            }
            .frame(maxHeight: .infinity)
        } else if tab == .top250 {
            if !APIClient.shared.hasToken {
                ContentUnavailableView {
                    Label("需要登录", systemImage: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text("TOP250 需要 JAVDB 账号登录后才能显示")
                }
            } else if vm.movies.isEmpty {
                ContentUnavailableView(
                    vm.errorMessage == nil ? "暂无符合条件的作品" : "TOP250 加载失败",
                    systemImage: vm.errorMessage == nil ? "line.3.horizontal.decrease.circle" : "exclamationmark.triangle",
                    description: Text(vm.errorMessage == nil ? "请调整筛选条件或下拉刷新" : "请检查登录状态或重试；不会自动退出账号")
                )
                .frame(maxHeight: .infinity)
            } else {
                top250List
            }
        } else if vm.showingActors {
            actorRankingGrid
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

    private var actorRankingGrid: some View {
        ActorRankingGridContent(vm: vm)
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
                    .onAppear {
                        if movie.id == vm.displayed.last?.id {
                            Task { await vm.loadMore() }
                        }
                    }
                }
                if vm.isLoading { ProgressView().padding() }
            }
            .padding(.horizontal, AdaptiveLayout.gridPadding)
            .padding(.vertical, 8)
            .frame(maxWidth: AdaptiveLayout.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 8) {
            Button {
                GlassHaptic.tap()
                showTopFilter = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text("篩選")
                        .font(.headline)
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .pressableGlass(scale: 0.97)
            .liquidGlass(interactive: false)
            .padding(.horizontal, 20)
            .padding(.bottom, AdaptiveLayout.isPad ? 4 : 6)
        }
    }

    private func top250Row(rank: Int, movie: Movie) -> some View {
        let coverW: CGFloat = AdaptiveLayout.isPad ? 180 : 150
        let coverH: CGFloat = coverW / 0.7
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    MoviePosterImage(movie: movie)
                        .frame(width: coverW, height: coverH)
                        .clipped()
                        .liquidCover(cornerRadius: 12)
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    GlassChip(
                        text: "\(rank)",
                        tint: rank <= 3 ? .orange : .blue,
                        font: .system(size: 13, weight: .bold),
                        foreground: rank <= 3 ? .white : .primary,
                        compact: true,
                        tintStrength: rank <= 3 ? 0.68 : 0.12
                    )
                    .padding(8)
                    if let badge = movie.playBadge {
                        GlassChip(
                            text: badge,
                            tint: badge.contains("中字") ? JAVDBPalette.cnsubOrange : JAVDBPalette.playRed,
                            font: .system(size: 10, weight: .semibold),
                            foreground: .white,
                            compact: true,
                            tintStrength: 0.66
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(6)
                    }
                }
                .frame(width: coverW, height: coverH)
                RankingPreviewCarousel(movie: movie)
                    .frame(maxWidth: .infinity)
                    .frame(height: coverH)
                    .liquidCover(cornerRadius: 8)
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


/// 排行榜右侧剧照轮播。使用系统分页手势，横滑翻图，圆点显示当前位置。
private struct RankingPreviewCarousel: View {
    let movie: Movie
    @State private var selection = 0
    @State private var slides: [String] = []

    private var fallbackURLs: [String] {
        var urls = (movie.previewImages ?? []).compactMap { $0.largeURL ?? $0.thumbURL }
        if urls.isEmpty, let backdrop = movie.hdBackdropURL ?? movie.coverURL ?? movie.thumbURL {
            urls = [backdrop]
        }
        return Array(urls.prefix(8))
    }

    private var imageURLs: [String] { slides.isEmpty ? fallbackURLs : slides }

    var body: some View {
        ZStack(alignment: .bottom) {
            if imageURLs.isEmpty {
                Color(.systemGray5)
            } else {
                TabView(selection: $selection) {
                    ForEach(Array(imageURLs.enumerated()), id: \.offset) { index, url in
                        JavDBImage(url: url, contentMode: .fill, maxPixelSize: 1600)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

            if imageURLs.count > 1 {
                HStack(spacing: 5) {
                    ForEach(imageURLs.indices, id: \.self) { index in
                        Circle()
                            .fill(index == selection ? Color.accentColor : .white.opacity(0.72))
                            .frame(width: index == selection ? 7 : 5, height: index == selection ? 7 : 5)
                            .animation(GlassMotion.select, value: selection)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
                }
                .padding(.bottom, 10)
                .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .task(id: movie.id) { await loadSlides() }
    }

    private func loadSlides() async {
        let current = fallbackURLs
        if slides.isEmpty { slides = current }
        guard current.count < 8 else { return }
        guard let detail = try? await JavDBSDK.shared.movieDetail(movie.id, fromRankings: true) else { return }
        var urls = (detail.previewImages ?? []).compactMap { $0.largeURL ?? $0.thumbURL }
        if urls.isEmpty { urls = current }
        let next = Array(urls.prefix(8))
        guard next.count > slides.count else { return }
        slides = next
        if selection >= next.count { selection = 0 }
    }
}

/// 演员排行网格（自适应列数，不用 GeometryReader）
private struct ActorRankingGridContent: View {
    @ObservedObject var vm: RankingsViewModel
    @Environment(\.availableLayoutSize) private var layoutSize

    private var columns: [GridItem] {
        let count = AdaptiveLayout.columnCount(width: layoutSize.width, padding: AdaptiveLayout.gridPadding, spacing: 14)
        return Array(repeating: GridItem(.flexible(), spacing: 14), count: count)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(Array(vm.actors.enumerated()), id: \.element.id) { idx, actor in
                    NavigationLink {
                        ActorDetailView(actorID: actor.id)
                    } label: {
                        VStack(spacing: 8) {
                            ZStack(alignment: .topLeading) {
                                ClippedAspectFill(aspectRatio: 1) {
                                    JavDBImage(url: actor.avatarURL ?? actor.coverURL)
                                }
                                .liquidCover(cornerRadius: 8)
                                GlassChip(
                                    text: "\(idx + 1)",
                                    tint: idx < 3 ? .orange : .blue,
                                    font: .system(size: 12, weight: .bold),
                                    foreground: idx < 3 ? .white : .primary,
                                    compact: true,
                                    tintStrength: idx < 3 ? 0.68 : 0.12
                                )
                                .padding(6)
                            }
                            Text(actor.displayName)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if actor.id == vm.actors.last?.id {
                            Task { await vm.loadMore() }
                        }
                    }
                }
            }
            .padding(.horizontal, AdaptiveLayout.gridPadding)
            .padding(.vertical, 12)
            if vm.isLoading { ProgressView().padding() }
        }
    }
}

@MainActor
final class RankingsViewModel: ObservableObject {
    @Published var movies: [Movie] = []
    @Published var actors: [Actor] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var catalog = "all"
    @Published var year = ""
    @Published var startRank = 1
    @Published var hideWatched = false

    struct Request: Equatable {
        var tab: RankingTab
        var period: String
        var playback: String
        var kind: String
        var catalog: String
        var year: String
        var startRank: Int
        var hideWatched: Bool
        var page: Int
    }
    typealias MovieLoader = (Request) async throws -> [Movie]
    typealias ActorLoader = (Request) async throws -> [Actor]
    private let movieLoader: MovieLoader
    private let actorLoader: ActorLoader
    private var request: Request?
    private var generation = 0
    private var hasMore = true
    private var page = 0

    init(movieLoader: @escaping MovieLoader = RankingsViewModel.requestMovies,
         actorLoader: @escaping ActorLoader = { r in
             try await JavDBSDK.shared.actorRankings(type: "0", period: "monthly", page: r.page)
         }) {
        self.movieLoader = movieLoader
        self.actorLoader = actorLoader
    }

    var displayed: [Movie] { movies }
    var showingActors: Bool { request?.tab == .censored && request?.kind == "actors" }

    func load(tab: RankingTab, period: RankPeriod, playbackFilter: String,
              playbackPeriod: RankPeriod = .daily, rankingKind: String = "movies", force: Bool = false) async {
        let next = Request(tab: tab, period: tab == .playback ? playbackPeriod.rawValue : period.rawValue,
                           playback: playbackFilter, kind: rankingKind, catalog: catalog, year: year,
                           startRank: startRank, hideWatched: hideWatched, page: 1)
        if !force, request == next, (!movies.isEmpty || !actors.isEmpty) { return }
        let same = request == next
        generation += 1
        request = next
        page = 0
        hasMore = true
        // Refresh errors retain visible content; a different tab/filter must not show stale rows.
        if !same { movies = []; actors = [] }
        await fetch(next, generation: generation)
    }

    func loadMore() async {
        guard hasMore, !isLoading, var next = request else { return }
        next.page = page + 1
        await fetch(next, generation: generation)
    }

    func applyTopFilter() async {
        guard var next = request, next.tab == .top250 else { return }
        next.catalog = catalog; next.year = year
        next.startRank = startRank; next.hideWatched = hideWatched; next.page = 1
        generation += 1
        request = next; page = 0; hasMore = true
        movies = []; actors = []
        await fetch(next, generation: generation)
    }

    private func fetch(_ next: Request, generation ticket: Int) async {
        isLoading = true
        errorMessage = nil
        defer { if generation == ticket { isLoading = false } }
        do {
            if next.tab == .censored && next.kind == "actors" {
                let list = try await actorLoader(next)
                guard generation == ticket, !Task.isCancelled else { return }
                if next.page == 1 { actors = list }
                else { let ids = Set(actors.map(\.id)); actors += list.filter { !ids.contains($0.id) } }
                hasMore = !list.isEmpty
            } else {
                let list = try await movieLoader(next)
                guard generation == ticket, !Task.isCancelled else { return }
                if next.page == 1 { movies = list }
                else { let ids = Set(movies.map(\.id)); movies += list.filter { !ids.contains($0.id) } }
                hasMore = !list.isEmpty
            }
            // Advance only after success; retries cannot skip a failed page.
            page = next.page
        } catch {
            guard generation == ticket, !Task.isCancelled else { return }
            if error is CancellationError { return }
            errorMessage = error.localizedDescription
        }
    }

    nonisolated static func requestMovies(_ r: Request) async throws -> [Movie] {
        let sdk = await JavDBSDK.shared
        switch r.tab {
        case .top250:
            let type = !r.year.isEmpty ? "year" : (["0", "1", "2", "3"].contains(r.catalog) ? "video_type" : "all")
            let value = !r.year.isEmpty ? r.year : (type == "video_type" ? r.catalog : "")
            return try await sdk.topMovies(startRank: r.startRank, type: type, typeValue: value,
                                           ignoreWatched: r.hideWatched, page: r.page, limit: 25)
        case .playback:
            return try await sdk.playbackRankings(filterBy: r.playback, period: r.period, page: r.page)
        case .censored, .uncensored, .western, .fc2:
            let type: String
            switch r.tab { case .uncensored: type = "1"; case .western: type = "2"; case .fc2: type = "3"; default: type = "0" }
            return try await sdk.rankings(type: type, period: r.period, page: r.page)
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
                VStack(alignment: .leading, spacing: 18) {
                    Text("篩選")
                        .font(.title2.bold())

                    VStack(alignment: .leading, spacing: 10) {
                        Text("類型").font(.subheadline.weight(.semibold))
                        chipRow(types.map { ($0.0, $0.1) }, selected: vm.year.isEmpty ? vm.catalog : "") { id in
                            GlassHaptic.tap()
                            vm.catalog = id
                            vm.year = ""
                        }
                    }
                    .padding(12)
                    .glassSurface(in: RoundedRectangle(cornerRadius: 14, style: .continuous), elevation: 0.35)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("年份").font(.subheadline.weight(.semibold))
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                            ForEach(years, id: \.self) { y in
                                chip(y, on: vm.year == y) {
                                    GlassHaptic.tap()
                                    if vm.year == y {
                                        vm.year = ""
                                    } else {
                                        vm.year = y
                                        vm.catalog = "all"
                                    }
                                }
                            }
                        }
                    }
                    .padding(12)
                    .glassSurface(in: RoundedRectangle(cornerRadius: 14, style: .continuous), elevation: 0.35)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("起始排名")
                            .font(.subheadline.weight(.semibold))
                        chipRow(ranks.map { ("\($0)", "\($0)") }, selected: "\(vm.startRank)") {
                            GlassHaptic.tap()
                            vm.startRank = Int($0) ?? 1
                        }
                    }
                    .padding(12)
                    .glassSurface(in: RoundedRectangle(cornerRadius: 14, style: .continuous), elevation: 0.35)

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
                    .padding(12)
                    .glassSurface(in: RoundedRectangle(cornerRadius: 14, style: .continuous), elevation: 0.35)
                }
                .padding(16)
                .staggerAppear(index: 0)
            }
            .background {
                LiquidGlassBackground()
            }
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
        Button {
            GlassHaptic.tap()
            action()
        } label: {
            Text(title)
                .font(.system(size: 14, weight: on ? .semibold : .medium))
                .foregroundColor(on ? .white : .primary)
                .shadow(color: on ? .black.opacity(0.18) : .clear, radius: 1, y: 0.5)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if on {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.ultraThinMaterial)
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(JAVDBPalette.chipSelected.opacity(0.75))
                            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.28), .clear, .black.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.white.opacity(on ? 0.4 : 0.2), lineWidth: 0.5)
                }
        }
        .pressableGlass(scale: 0.95)
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
