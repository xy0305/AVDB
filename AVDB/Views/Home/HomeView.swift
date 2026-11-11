//
//  HomeView.swift
//  AVDB
//
//  首页（Build 329）：英雄地板层有图就清晰画出（不施加 blur）；栏位改为
//  三列上下浏览、每栏最多 9 张；往期推薦 / 我的關注无「換一組」。
//

import SwiftUI
import UIKit


#if DEBUG
extension FollowingTag {
    /// Neutral home fixture for Build 329 UI tests (3×3 我的關注 grid).
    static var fixtureHome: FollowingTag {
        FollowingTag(id: 329, name: "字幕", value: "0:t:fixture:", priority: 0)
    }
}
#endif

struct HomeView: View {
    @StateObject private var vm = HomeViewModel()
    // Build 325: reference objects held in @State (not @StateObject) on purpose — HomeView
    // must not re-render its rails on every scroll tick; only the hero / search button /
    // ambient background observe them.
    @State private var scroll = HomeScrollState()
    @State private var ambient = HomeAmbient()
    @Environment(\.selectedAppTab) private var selectedTab
    @State private var goSearch = false
    @State private var goRankings = false
    @State private var goHot = false
    @State private var goLatest = false
    @State private var goMagnets = false
    @State private var goArticles = false
    @State private var goReviews = false
    @State private var goSeries = false
    @State private var goMakers = false
    @State private var goDirectors = false
    @State private var goDailyDraw = false
    @State private var goWatchLater = false
    @State private var goUpdates = false
    @State private var goChallenge = false
    @State private var goPast = false
    @State private var goFollowManage = false
    @State private var goFollowing = false
    @State private var openMovie: Movie?

    /// Home root is on screen (nothing pushed from it).
    private var atRoot: Bool {
        openMovie == nil && ![goSearch, goRankings, goHot, goLatest, goMagnets, goArticles, goReviews,
                              goSeries, goMakers, goDirectors, goDailyDraw, goWatchLater, goUpdates,
                              goChallenge, goPast, goFollowManage, goFollowing].contains(true)
    }

    /// Immersive dark home is the visible screen: home tab selected and at its root.
    private var immersiveActive: Bool {
        (selectedTab == nil || selectedTab == .home) && atRoot
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                homeRoot(HomeMetrics(width: proxy.size.width, safeTop: proxy.safeAreaInsets.top))
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(AdaptiveLayout.isPad ? .visible : .automatic, for: .tabBar)
            .task {
                // Prefetch search suggestions on the home tab so opening search is cheap.
                SearchSuggestStore.shared.prefetch()
                await vm.initialLoad()
            }
            .navigationDestination(isPresented: $goSearch) {
                SearchView()
            }
            .navigationDestination(isPresented: $goRankings) {
                RankingsView(embedded: true, initialTab: .top250)
            }
            .navigationDestination(isPresented: $goHot) {
                RankingsView(embedded: true, initialTab: .playback,
                             initialPlaybackFilter: "high_score",
                             initialPlaybackPeriod: .daily)
            }
            .navigationDestination(isPresented: $goLatest) {
                CatalogListView(title: "最新上架", source: .latest)
            }
            .navigationDestination(isPresented: $goMagnets) {
                CatalogListView(title: "近期磁鏈更新", source: .magnets)
            }
            .navigationDestination(isPresented: $goArticles) {
                ArticlesView()
            }
            .navigationDestination(isPresented: $goReviews) {
                HotReviewsView()
            }
            .navigationDestination(isPresented: $goSeries) {
                SeriesView()
            }
            .navigationDestination(isPresented: $goMakers) {
                MakersView()
            }
            .navigationDestination(isPresented: $goDirectors) {
                DirectorsView()
            }
            .navigationDestination(isPresented: $goDailyDraw) {
                DailyDrawView()
            }
            .navigationDestination(isPresented: $goWatchLater) { WatchLaterView() }
            .navigationDestination(isPresented: $goUpdates) { UpdateNoticesView() }
            .navigationDestination(isPresented: $goChallenge) { TripleDrawView() }
            .navigationDestination(isPresented: $goPast) { PastRecommendView() }
            .navigationDestination(isPresented: $goFollowManage) { FollowingTagsView() }
            .navigationDestination(isPresented: $goFollowing) {
                if let tag = vm.selectedFollowTag {
                    FollowingTagDestination(tag: tag)
                } else {
                    FollowingTagsView()
                }
            }
            .navigationDestination(item: $openMovie) { movie in
                homeMovieDestination(movie)
            }
        }
        // Status bar style is applied inside homeRoot (light content over the
        // hero image, dark content over the light rails) without forcing the
        // page color scheme dark.
    }

    @ViewBuilder
    private func homeMovieDestination(_ movie: Movie) -> some View {
        let movieID = movie.id
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--poster-navigation-fixture") {
            Text("Neutral detail \(movieID)")
                .accessibilityIdentifier("detail-\(movieID)")
                .navigationTitle("Neutral detail")
                .toolbar(.visible, for: .navigationBar)
        } else {
            MovieDetailView(movie: movie)
        }
        #else
        MovieDetailView(movie: movie)
        #endif
    }

    private func homeRoot(_ m: HomeMetrics) -> some View {
        ZStack(alignment: .top) {
            Color(.systemBackground)
                .ignoresSafeArea()
            // Ambient color only behind the hero itself and the top overscroll
            // area. It must not paint #14100D / #2A2019 under the rails.
            HomeAmbientBackground(ambient: ambient, heroHeight: m.heroHeight, scroll: scroll)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        heroSection(m, scrollToShortcuts: {
                            withAnimation(.easeInOut(duration: 0.38)) {
                                proxy.scrollTo("home-shortcuts", anchor: .top)
                            }
                        })
                        VStack(alignment: .leading, spacing: 0) {
                            quickActionRow(m)
                                .padding(.top, 18)
                                .id("home-shortcuts")
                            pastRecommendSection(m)
                                .padding(.top, 22)
                            latestSection(m)
                                .padding(.top, 22)
                            top250Banner(m)
                                .padding(.top, 26)
                            magnetSection(m)
                                .padding(.top, 26)
                            followingSection(m)
                                .padding(.top, 26)
                        }
                        .background(Color(.systemBackground))
                        // iPad: sections capped at 1100 and centered; the hero stays full width.
                        .frame(maxWidth: m.contentWidth, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        // Build 332: pull the light shortcuts/rails block up to cover the hero's bottom edge.
                        .padding(.top, -HomeMetrics.heroContentOverlap)
                        .padding(.bottom, 28)
                    }
                }
                .scrollIndicators(.hidden)
                .coordinateSpace(.named(HomeScrollState.space))
                .onPreferenceChange(HomeScrollOffsetKey.self) { value in
                    scroll.update(value)
                }
                // Full-bleed: the hero runs under the status bar. Bottom safe area (floating
                // tab bar inset) is kept so the last rail scrolls clear of the bar.
                .ignoresSafeArea(.container, edges: .top)
                .refreshable {
                    if !HeroCoverStore.appCallsSuspended { HeroCoverStore.shared.clearNegativesAndRetry() }
                    await vm.initialLoad()
                }
            }

            HomeTopScrim(scroll: scroll, start: max(0, m.heroHeight - m.safeTop - 90))

            HomeSearchButton(scroll: scroll) {
                GlassHaptic.tap()
                // Warm 近期熱搜 / 歷史搜索 before the push so the idle page does not
                // hitch mid-transition waiting on startup.recent_keywords.
                SearchSuggestStore.shared.prefetch()
                goSearch = true
            }
            .padding(.top, 6)
            .padding(.trailing, m.padding)
            .frame(maxWidth: .infinity, alignment: .trailing)

            HomeStatusBarObserver(scroll: scroll, active: immersiveActive,
                                  cutoff: max(40, m.heroHeight - m.safeTop - 80))
        }
        .foregroundStyle(HomeTheme.primary)
    }

    // MARK: Hero

    @ViewBuilder
    private func heroSection(_ m: HomeMetrics, scrollToShortcuts: @escaping () -> Void) -> some View {
        Group {
            if !vm.playback.isEmpty {
                HomeHeroCarousel(
                    movies: vm.playback,
                    metrics: m,
                    scroll: scroll,
                    ambient: ambient,
                    isActive: immersiveActive,
                    onOpen: { openMovie = $0 },
                    onHot: { goHot = true },
                    onMore: scrollToShortcuts
                )
            } else if vm.playbackState == .loading || vm.playbackState == .failed {
                homeListStatus(vm.playbackState, hasItems: !vm.playback.isEmpty, placeholder: .hero(m)) {
                    Task { await vm.retry(.playback) }
                }
            } else {
                // Empty playback list: keep the full hero height (never collapse).
                // Neutral systemGray floor — never brand brown #2A2019.
                ZStack(alignment: .topLeading) {
                    HomeTheme.heroLoadingFloor
                    HomeHotChip { goHot = true }
                        .padding(.leading, m.padding)
                        .padding(.top, m.safeTop + 13)
                }
                .frame(width: m.width, height: m.heroHeight)
            }
        }
        .background {
            GeometryReader { g in
                Color.clear.preference(key: HomeScrollOffsetKey.self,
                                       value: g.frame(in: .named(HomeScrollState.space)).minY)
            }
        }
    }

    // MARK: Quick actions (12 destinations, frosted glass circles)

    @ViewBuilder
    private func quickActionRow(_ m: HomeMetrics) -> some View {
        // iPad: do not wrap in LiquidGlassContainer — GlassEffectContainer ate taps.
        if AdaptiveLayout.isPad {
            quickActionScroll(m)
        } else {
            LiquidGlassContainer { quickActionScroll(m) }
        }
    }

    private func quickActionScroll(_ m: HomeMetrics) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: m.quickSpacing) {
                quickAction("稍後再看", "clock.fill", m) { goWatchLater = true }
                quickAction("新作提醒", "bell.fill", m) { goUpdates = true }
                quickAction("三連挑戰", "rectangle.stack.fill", m) { goChallenge = true }
                quickAction("每日抽簽", "sparkles", m) { goDailyDraw = true }
                quickAction("看熱播", "play.rectangle.fill", m) { goHot = true }
                quickAction("AV資訊", "newspaper.fill", m) { goArticles = true }
                quickAction("看短評", "text.bubble.fill", m) { goReviews = true }
                quickAction("找磁鏈", "link", m) { goMagnets = true }
                quickAction("系列", "square.stack.3d.up.fill", m) { goSeries = true }
                quickAction("片商", "building.2.fill", m) { goMakers = true }
                quickAction("導演", "person.3.fill", m) { goDirectors = true }
                quickAction("TOP250", "crown.fill", m) { goRankings = true }
            }
            .padding(.vertical, 2)
        }
        .contentMargins(.horizontal, m.padding, for: .scrollContent)
    }

    private func quickAction(_ title: String, _ icon: String, _ m: HomeMetrics,
                             action: @escaping () -> Void) -> some View {
        Button {
            GlassHaptic.tap()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: m.quickCircle, height: m.quickCircle)
                    .liquidGlassCircle(interactive: true)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: m.quickItem)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle(scale: 0.92))
        .accessibilityLabel(title)
    }

    // MARK: Rails

    private func pastRecommendSection(_ m: HomeMetrics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeRailHeader(title: "往期推薦", padding: m.padding,
                           titleIdentifier: "home-past-header",
                           more: { goPast = true })
            if !vm.recommended.isEmpty {
                HomePosterGrid(upgradesVisibleHQ: true, movies: vm.recommended, metrics: m) { openMovie = $0 }
            }
            homeListStatus(vm.recommendedState, hasItems: !vm.recommended.isEmpty, placeholder: .rail(m)) {
                Task { await vm.retry(.recommended) }
            }
        }
    }

    private func latestSection(_ m: HomeMetrics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeRailHeader(title: "最新上架", padding: m.padding,
                           titleIdentifier: "home-latest-header",
                           shuffle: { Task { await vm.shuffleLatest() } },
                           more: { goLatest = true })
            if !vm.latest.isEmpty {
                HomePosterGrid(upgradesVisibleHQ: true, movies: vm.latest, metrics: m) { openMovie = $0 }
            }
            homeListStatus(vm.latestState, hasItems: !vm.latest.isEmpty, placeholder: .rail(m)) {
                Task { await vm.retry(.latest) }
            }
        }
    }

    private func magnetSection(_ m: HomeMetrics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeRailHeader(title: "近期磁鏈更新", padding: m.padding,
                           shuffle: { Task { await vm.shuffleMagnets() } },
                           more: { goMagnets = true })
            if !vm.magnets.isEmpty {
                HomePosterGrid(upgradesVisibleHQ: true, movies: vm.magnets, metrics: m) { openMovie = $0 }
            }
            homeListStatus(vm.magnetsState, hasItems: !vm.magnets.isEmpty, placeholder: .rail(m)) {
                Task { await vm.retry(.magnets) }
            }
        }
    }

    @ViewBuilder
    private func homeListStatus(_ state: HomeListState, hasItems: Bool, placeholder: HomePlaceholder,
                                retry: @escaping () -> Void) -> some View {
        switch state {
        case .loading:
            if !hasItems {
                HomePlaceholderView(kind: placeholder, failed: false, retry: retry)
            }
        case .failed:
            if hasItems {
                HStack(spacing: 8) {
                    Text("更新失敗，顯示上次內容")
                        .foregroundStyle(HomeTheme.secondary)
                    Button("重試", action: retry)
                        .foregroundStyle(HomeTheme.accent)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .font(.caption)
                .frame(maxWidth: .infinity)
            } else {
                HomePlaceholderView(kind: placeholder, failed: true, retry: retry)
            }
        case .empty:
            if !hasItems {
                Text("暫無內容")
                    .font(.caption)
                    .foregroundStyle(HomeTheme.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        case .loaded:
            EmptyView()
        }
    }

    private func top250Banner(_ m: HomeMetrics) -> some View {
        let height: CGFloat = m.isPadWidth ? 132 : 104
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button {
            GlassHaptic.tap()
            goRankings = true
        } label: {
            ZStack(alignment: .leading) {
                JavDBImage(url: vm.latest.first?.coverURL, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipped()
                    .overlay {
                        LinearGradient(
                            colors: [HomeTheme.floor.opacity(0.94), HomeTheme.floor.opacity(0.62), HomeTheme.floor.opacity(0.30)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
                HStack(spacing: 12) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(HomeTheme.accent)
                        .frame(width: 44, height: 44)
                        .homeGlass(in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("TOP250")
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(HomeTheme.primary)
                        Text("本季口碑榜 · 每日更新")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(HomeTheme.secondary)
                    }
                    Spacer(minLength: 8)
                    HomeChevronCircle(onDark: true)
                }
                .padding(.horizontal, 16)
            }
            .frame(height: height)
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            .contentShape(shape)
        }
        .buttonStyle(HomePressStyle(scale: 0.98, spring: true))
        .accessibilityLabel("TOP250 本季口碑榜")
        .padding(.horizontal, m.padding)
    }

    private func followingSection(_ m: HomeMetrics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("我的關注")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(HomeTheme.primary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("home-following-header")
                Spacer(minLength: 8)
                Menu {
                    ForEach([CatalogSort.releaseDesc, CatalogSort.updateDesc]) { item in
                        Button {
                            Task { await vm.selectFollowSort(item) }
                        } label: {
                            if vm.followSort == item {
                                Label(item.title, systemImage: "checkmark")
                            } else {
                                Text(item.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(vm.followSort.title)
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HomeTheme.secondary)
                    .padding(.horizontal, 6)
                    .frame(height: 26)
                    .contentShape(Rectangle().inset(by: -9))
                }
                Button {
                    GlassHaptic.tap()
                    goFollowManage = true
                } label: {
                    HStack(spacing: 3) {
                        Text("管理")
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HomeTheme.secondary)
                    .padding(.horizontal, 6)
                    .frame(height: 26)
                    .contentShape(Rectangle().inset(by: -9))
                }
                .buttonStyle(HomePressStyle(scale: 0.94))
                Button {
                    GlassHaptic.tap()
                    goFollowing = true
                } label: {
                    HomeChevronCircle()
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle().inset(by: -9))
                }
                .buttonStyle(HomePressStyle(scale: 0.9))
                .accessibilityLabel("我的關注 全部")
                .accessibilityIdentifier("home-following-more")
            }
            .padding(.horizontal, m.padding)
            .frame(minHeight: 26)

            if vm.followTags.isEmpty {
                Text("登入後顯示關注內容")
                    .font(.caption)
                    .foregroundStyle(HomeTheme.secondary)
                    .padding(.horizontal, m.padding)
                    .padding(.bottom, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(vm.followTags) { tag in
                            let selected = vm.selectedFollowTag?.id == tag.id
                            Button {
                                GlassHaptic.tap()
                                withAnimation(GlassMotion.select) {
                                    Task { await vm.selectFollowTag(tag) }
                                }
                            } label: {
                                Text(tag.displayName)
                                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? Color.white : Color.primary)
                                    .padding(.horizontal, 12)
                                    .frame(height: 30)
                                    .background(Capsule().fill(selected ? HomeTheme.accent : Color(.systemGray5)))
                                    .contentShape(Capsule().inset(by: -7))
                            }
                            .buttonStyle(HomePressStyle(scale: 0.94))
                            .accessibilityAddTraits(selected ? [.isSelected] : [])
                        }
                    }
                    .padding(.vertical, 7)
                }
                .contentMargins(.horizontal, m.padding, for: .scrollContent)

                if vm.following.isEmpty && vm.followLoading {
                    HomePlaceholderView(kind: .rail(m), failed: false, retry: {})
                } else if vm.following.isEmpty {
                    Text("暫無更新")
                        .font(.caption)
                        .foregroundStyle(HomeTheme.secondary)
                        .padding(.horizontal, m.padding)
                        .padding(.bottom, 12)
                } else {
                    HomePosterGrid(upgradesVisibleHQ: true, movies: vm.following, metrics: m) { openMovie = $0 }
                }
            }
        }
    }
}

// Small list-only snapshot. Original image URLs and all card badges are retained.
// Uses the API wire names so restoring follows Movie's existing tolerant decoder.
private struct HomeMovieSnapshot: Codable {
    let id: String
    let type: String?
    let number: String?
    let title: String?
    let thumb_url: String?
    let cover_url: String?
    let duration: Int?
    let score: Double?
    let rating: Double?
    let release_date: String?
    let magnets_count: Int?
    let can_play: Bool?
    let play_subtitle: String?
    let has_cnsub: Bool?
    let has_preview_video: Bool?
    let has_preview_images: Bool?
    let new_magnets: Bool
    let actor_names: [String]?
    let maker_id: String?
    let maker_name: String?
    let series_id: String?
    let series_name: String?
    init(_ movie: Movie) {
        id = movie.id
        type = movie.type
        number = movie.number
        title = movie.title
        thumb_url = movie.thumbURL
        cover_url = movie.coverURL
        duration = movie.duration
        score = movie.score
        rating = movie.rating
        release_date = movie.releaseDate
        magnets_count = movie.magnetsCount
        can_play = movie.canPlay
        play_subtitle = movie.playSubtitle
        has_cnsub = movie.hasCnsub
        has_preview_video = movie.hasPreviewVideo
        has_preview_images = movie.hasPreviewImages
        new_magnets = movie.hasNewMagnets
        actor_names = movie.actorNames
        maker_id = movie.makerID
        maker_name = movie.makerName
        series_id = movie.seriesID
        series_name = movie.seriesName
    }
    var movie: Movie? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return try? JSONDecoder().decode(Movie.self, from: data)
    }
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var recommended: [Movie] = []
    @Published var playback: [Movie] = []
    @Published var latest: [Movie] = []
    @Published var magnets: [Movie] = []
    @Published private(set) var recommendedState: HomeListState = .loading
    @Published private(set) var playbackState: HomeListState = .loading
    @Published private(set) var latestState: HomeListState = .loading
    @Published private(set) var magnetsState: HomeListState = .loading
    enum Section: CaseIterable { case recommended, playback, latest, magnets }
    static let playbackHeroCap = 10
    /// Home page poster grids are 3×3; full lists are opened via 「>」 / 更多.
    static let homeGridCap = 9
    private let recommendedLoader = HomeListLoader<HomeMovieSnapshot>()
    private let playbackLoader = HomeListLoader<HomeMovieSnapshot>()
    private let latestLoader = HomeListLoader<HomeMovieSnapshot>()
    private let magnetsLoader = HomeListLoader<HomeMovieSnapshot>()
    private var loadGeneration = UUID()
    private var context: String?
    private let unresolvedAccountID = UUID().uuidString
    @Published var following: [Movie] = []
    @Published var followTags: [FollowingTag] = []
    @Published var selectedFollowTag: FollowingTag?
    @Published var followLoading = false
    @Published var followSort: CatalogSort = .updateDesc
    @Published var periodLabel = "週一/四更新"
    @Published var periods: [RecommendPeriod] = []
    private var latestPage = 1
    private var magnetPage = 2
    private let sdk = JavDBSDK.shared
    /// Plan C: bumped once when a home HQ prefetch learns new covers, so the
    /// poster grids re-read ListCoverPolicy sources and swap in the HQ URLs.
    @Published private(set) var hqRevision = 0
    private var hqPrefetchTasks: [String: Task<Void, Never>] = [:]

    func initialLoad() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--poster-navigation-fixture") {
            latest = (1...9).map { Movie(id: "fixture-\($0)", number: "TEST-\($0)", title: "Neutral film \($0)", coverURL: "fixture://poster/\($0)") }
            magnets = (1...9).map { Movie(id: "magnet-\($0)", number: "TEST-M\($0)", title: "Neutral magnet \($0)", coverURL: "fixture://poster/\($0)") }
            latestState = .loaded; magnetsState = .loaded; recommendedState = .empty
            playbackState = .empty
            if ProcessInfo.processInfo.arguments.contains("--home326-fixture")
                || ProcessInfo.processInfo.arguments.contains("--home325-fixture")
                || ProcessInfo.processInfo.arguments.contains("--home328-fixture")
                || ProcessInfo.processInfo.arguments.contains("--home329-fixture") {
                // Neutral 700×1000 B-tier portrait rasters (no network). Hero is the
                // playback array; 往期推薦 / 栏位 keep recommend fixtures as a 3×3 grid.
                playback = (1...5).map { Movie(id: "hero-\($0)", number: "TEST-H\($0)", title: "Neutral hero film \($0)", coverURL: "fixture://poster/portrait-hero-\($0)") }
                playbackState = .loaded
                recommended = (1...5).map { Movie(id: "past-\($0)", number: "TEST-P\($0)", title: "Neutral past film \($0)", coverURL: "fixture://poster/\($0)") }
                recommendedState = .loaded
                periodLabel = "2026-11-09"
                recommended = (1...12).map { Movie(id: "past-\($0)", number: "TEST-P\($0)", title: "Neutral past film \($0)", coverURL: "fixture://poster/\($0)") }
                latest = (1...9).map { Movie(id: "fixture-\($0)", number: "TEST-\($0)", title: "Neutral film \($0)", coverURL: "fixture://poster/\($0)") }
                magnets = (1...9).map { Movie(id: "magnet-\($0)", number: "TEST-M\($0)", title: "Neutral magnet \($0)", coverURL: "fixture://poster/\($0)") }
                followTags = [FollowingTag.fixtureHome]
                selectedFollowTag = followTags.first
                following = (1...9).map { Movie(id: "follow-\($0)", number: "TEST-F\($0)", title: "Neutral follow film \($0)", coverURL: "fixture://poster/thumb147-\($0)") }
                latestState = .loaded; magnetsState = .loaded
                if !HeroCoverStore.appCallsSuspended { HeroCoverStore.shared.start(movies: playback, currentIndex: 0) }
            }
            return
        }
        #endif
        let generation = UUID()
        loadGeneration = generation
        let scope = cacheContext
        let changedContext = context != scope
        context = scope
        recommendedLoader.cancel(clear: changedContext)
        playbackLoader.cancel(clear: changedContext)
        latestLoader.cancel(clear: changedContext)
        magnetsLoader.cancel(clear: changedContext)
        if changedContext {
            for task in hqPrefetchTasks.values { task.cancel() }
            hqPrefetchTasks = [:]
            recommended = []; playback = []; latest = []; magnets = []
        }
        latestPage = 1
        magnetPage = 2
        // Children publish inside their own load, never in sequential await order.
        await withTaskGroup(of: Void.self) { group in
            for section in Section.allCases {
                group.addTask { [weak self] in
                    guard let self else { return }
                    await self.load(section, page: section == .magnets ? 2 : 1,
                                    generation: generation, scope: scope)
                }
            }
            group.addTask { [weak self] in
                guard let self else { return }
                await self.loadPeriods(generation: generation, scope: scope)
            }
        }
        guard loadGeneration == generation, !Task.isCancelled, cacheContext == scope else { return }
        await loadFollowTags()
    }

    private var cacheAccountID: String {
        if let user = APIClient.shared.currentUser { return String(user.id) }
        // Never share an anonymous disk snapshot with an authenticated but unresolved user.
        return APIClient.shared.token == nil ? "anonymous" : "session-" + unresolvedAccountID
    }

    private var cacheContext: String {
        // Token only lives in memory for change detection, never in the disk key/payload.
        JavDBConstants.baseURL + "|" + cacheAccountID + "|" + (APIClient.shared.token ?? "")
    }

    private func loadPeriods(generation: UUID, scope: String) async {
        guard let result = try? await sdk.recommendPeriods(),
              loadGeneration == generation, !Task.isCancelled, cacheContext == scope else { return }
        periods = result
        if let created = periods.first?.createdAt, created.count >= 10 {
            periodLabel = String(created.prefix(10))
        }
    }

    func retry(_ section: Section) async {
        await load(section, page: section == .latest ? latestPage : section == .magnets ? magnetPage : 1,
                   generation: loadGeneration, scope: cacheContext)
    }

    private func load(_ section: Section, page: Int, generation: UUID, scope: String,
                      restore: Bool = true) async {
        guard loadGeneration == generation, cacheContext == scope, !Task.isCancelled else { return }
        let loader: HomeListLoader<HomeMovieSnapshot>
        switch section {
        case .recommended: loader = recommendedLoader
        case .playback: loader = playbackLoader
        case .latest: loader = latestLoader
        case .magnets: loader = magnetsLoader
        }
        let query = section == .recommended ? "/movies/recommend?page=1" :
            section == .playback ? "/rankings/playback?filter_by=high_score&period=daily&page=1" :
            "/movies?page=\(page)&limit=9&type=all&filter_by=can_play&sort_by=update&home=\(section == .magnets ? "magnets" : "latest")"
        let key = HomeListKey(base: JavDBConstants.baseURL,
                              accountID: cacheAccountID, query: query)
        await loader.load(key: key, restore: restore, isCurrent: { [weak self] in
            guard let self else { return false }
            return self.loadGeneration == generation && self.cacheContext == scope
        }, fetch: { [sdk] in
            let result: [Movie]
            switch section {
            case .recommended: result = try await sdk.recommendMovies(page: 1)
            case .playback:
                // Must match the 看熱播 tab defaults (high_score + daily), not the
                // SDK's filterBy: "all" default. Cap the carousel at 10 titles.
                result = Array((try await sdk.playbackRankings(filterBy: "high_score", period: "daily", page: 1)).prefix(Self.playbackHeroCap))
            case .latest, .magnets:
                result = try await sdk.latestMovies(page: page, limit: 9, type: "all", filterBy: "can_play", sortBy: "update")
            }
            let items = section == .magnets ? result.filter { ($0.magnetsCount ?? 0) > 0 } : result
            // A genuinely empty magnet response is empty, not a copy of another section.
            return items.map(HomeMovieSnapshot.init)
        }, changed: { [weak self] items, state in
            guard let self else { return }
            let movies = items.compactMap { $0.movie }
            let previous: [Movie]
            switch section {
            case .recommended:
                previous = self.recommended
                self.recommended = movies
                self.recommendedState = state
                // 往期推薦 rail only. Image success/failure never mutates this array.
            case .playback:
                previous = self.playback
                self.playback = movies
                self.playbackState = state
                // Prefetch starts when the playback list returns. Image success/failure
                // never mutates this array (dot count stays fixed).
                if !HeroCoverStore.appCallsSuspended { HeroCoverStore.shared.start(movies: movies, currentIndex: 0) }
            case .latest: previous = self.latest; self.latest = movies; self.latestState = state
            case .magnets: previous = self.magnets; self.magnets = movies; self.magnetsState = state
            }
            if !movies.isEmpty, movies != previous {
                self.startHQPrefetch(movies, section: String(describing: section))
                self.startThumbPreheat(movies, section: String(describing: section))
            }
        })
    }

    func loadFollowTags() async {
        let tags = await FollowingTagsStore.shared.refreshFromServer()
        followTags = tags
        if let current = selectedFollowTag, tags.contains(where: { $0.id == current.id }) {
            await selectFollowTag(current)
        } else if let first = tags.first {
            await selectFollowTag(first)
        } else {
            selectedFollowTag = nil
            following = []
        }
    }

    func selectFollowTag(_ tag: FollowingTag) async {
        selectedFollowTag = tag
        followLoading = true
        defer { followLoading = false }
        following = await movies(for: tag)
        startHQPrefetch()
        startThumbPreheat(following, section: "following")
    }

    func selectFollowSort(_ sort: CatalogSort) async {
        guard followSort != sort else { return }
        followSort = sort
        if let tag = selectedFollowTag {
            followLoading = true
            defer { followLoading = false }
            following = await movies(for: tag)
            startHQPrefetch()
            startThumbPreheat(following, section: "following")
        }
    }

    private func movies(for tag: FollowingTag) async -> [Movie] {
        if let actorID = tag.parsedActorID {
            return (try? await sdk.actorMovies(
                actorID, page: 1, limit: 9, type: actorType(from: tag.value),
                sortBy: followSort.sortBy, orderBy: followSort.orderBy
            )) ?? []
        }
        if let filter = tag.moviesFilterBy {
            return (try? await sdk.moviesByTag(
                filterBy: filter, type: nil, page: 1, limit: 9,
                sortBy: followSort.sortBy, orderBy: followSort.orderBy
            )) ?? []
        }
        return []
    }

    private func actorType(from value: String?) -> String {
        guard let value, let first = value.split(separator: ":").first else { return "0" }
        return String(first)
    }

    func shuffleLatest() async {
        latestPage += 1
        await load(.latest, page: latestPage, generation: loadGeneration, scope: cacheContext, restore: false)
        if latestState == .empty { latestPage = 1 }
    }

    func shuffleMagnets() async {
        magnetPage += 1
        await load(.magnets, page: magnetPage, generation: loadGeneration, scope: cacheContext, restore: false)
        if magnetsState == .empty { magnetPage = 2 }
    }

    /// Build 303: light cell-sized HQ prefetch for home grids (latest / magnets /
    /// following). Warms VisibleHQ + HQPosterDiskCache for the first ~2 screens;
    /// scroll-ahead is handled by MoviePosterGrid. Bump hqRevision when a new
    /// URL is learned so synchronous ListCoverPolicy can lead with it.
    /// Immediate DTO thumb/cover loads (not VisibleHQ). Called in section order
    /// so a fast scroll to 我的關注 does not flash film icons on cards with a URL.
    private func startThumbPreheat(_ movies: [Movie], section: String) {
        guard !movies.isEmpty else { return }
        Task { await HomeRailThumbPreheat.preheat(movies) }
    }

    private func startHQPrefetch(_ sectionMovies: [Movie]? = nil, section: String = "following") {
        let movies = sectionMovies ?? following
        guard !movies.isEmpty else { return }
        hqPrefetchTasks[section]?.cancel()
        hqPrefetchTasks[section] = Task {
            let learned = await HomeHQPosterPrefetch.prefetch(movies, account: APIClient.shared.token)
            guard learned, !Task.isCancelled else { return }
            hqRevision += 1
        }
    }
}

// MARK: - Build 325 immersive home: theme, metrics, glass

/// Home palette (Build 328): rails follow system appearance like the detail sheet;
/// on-image hero chrome stays white on dark scrims. Accent is unchanged.
enum HomeTheme {
    static let accent = Color(red: 1.0, green: 138.0 / 255.0, blue: 61.0 / 255.0)          // #FF8A3D
    static let accentPressed = Color(red: 229.0 / 255.0, green: 119.0 / 255.0, blue: 42.0 / 255.0) // #E5772A
    /// Kept for the TOP250 dark-island banner only — not the page floor.
    static let floor = Color(red: 20.0 / 255.0, green: 16.0 / 255.0, blue: 13.0 / 255.0)     // #14100D
    /// Historical 326 empty-hero fill. Must not be used as a visible empty floor in 328.
    static let fallbackBase = Color(red: 42.0 / 255.0, green: 32.0 / 255.0, blue: 25.0 / 255.0) // #2A2019
    /// Loading / empty hero floor when no blur or DTO image is available.
    static let heroLoadingFloor = Color(.systemGray)
    /// Glass fill rgba(20,16,13,0.32) for on-image chrome (search, 看熱播 chip, 更多).
    static let glassFill = Color(red: 20.0 / 255.0, green: 16.0 / 255.0, blue: 13.0 / 255.0).opacity(0.32)
    static let primary = Color.primary
    static let secondary = Color.secondary
    static let tertiary = Color.secondary.opacity(0.70)
    static let separator = Color.primary.opacity(0.10)
}

/// Scene-width driven metrics (never UIScreen): P, hero height, rail card size.
struct HomeMetrics {
    let width: CGFloat
    let safeTop: CGFloat

    /// iPad layout from the actual window width.
    var isPadWidth: Bool { width >= 768 }
    /// P = 16 (W < 380), 20, 24 on iPad.
    var padding: CGFloat { isPadWidth ? 24 : (width < 380 ? 16 : 20) }
    /// clamp(W * 1.15, 430, 560) on phone; 600 on iPad.
    var heroHeight: CGFloat { isPadWidth ? 600 : min(max(width * 1.15, 430), 560) }
    /// Build 332: the light shortcuts/rails block overlaps the hero bottom by this
    /// amount, covering the poster edge. 32 pt was chosen after a SNOS-484 layout
    /// check (faces stay well above the band; the allowed window was 24–40 pt).
    /// Hero bottom UI insets grow by the same amount; the overlap is not in the
    /// hero gesture hit area.
    static let heroContentOverlap: CGFloat = 32
    /// Sections are capped at 1100 and centered.
    var contentWidth: CGFloat { min(width, AdaptiveLayout.contentMaxWidth) }
    /// 3-column grid card width for loading placeholders (actual cells are flexible).
    var cardWidth: CGFloat {
        let usable = contentWidth - 2 * padding - 24
        return max(usable / 3, 1)
    }
    var cardHeight: CGFloat { (cardWidth * 1.5).rounded() }
    var quickItem: CGFloat { width <= 375 ? 56 : 60 }
    var quickCircle: CGFloat { width <= 375 ? 48 : 52 }
    /// Phone: five full items plus a peek of the sixth; iPad: roomy fixed spacing.
    var quickSpacing: CGFloat {
        if isPadWidth { return 22 }
        let free = contentWidth - padding - quickItem * 5.4
        return max(8, (free / 5).rounded(.down))
    }
}

extension View {
    /// Home glass recipe: ultraThin material + rgba(20,16,13,0.32) + accent 10% tint + 0.5pt white 16% stroke.
    func homeGlass<S: InsettableShape>(in shape: S) -> some View {
        background {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(HomeTheme.glassFill)
                shape.fill(HomeTheme.accent.opacity(0.10))
            }
            .environment(\.colorScheme, .dark)
        }
        .overlay {
            shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
        }
    }
}

/// Press feedback: scale only (quick actions 0.92 / 0.12 s, cards 0.97 spring).
struct HomePressStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    var spring = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? scale : 1))
            .animation(spring ? .spring(response: 0.3, dampingFraction: 0.8) : .easeOut(duration: 0.12),
                       value: configuration.isPressed)
    }
}

// MARK: Scroll offset (stretch / parallax / fades) without re-rendering the rails

struct HomeScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

final class HomeScrollState: ObservableObject {
    static let space = "home325.scroll"
    /// Hero top in the scroll view: > 0 pulled down, < 0 scrolled up. Clamped and rounded so
    /// far-down scrolling does not publish.
    @Published private(set) var offset: CGFloat = 0
    var up: CGFloat { max(0, -offset) }
    var pull: CGFloat { max(0, offset) }

    func update(_ raw: CGFloat) {
        guard raw.isFinite else { return }
        let value = min(max(raw, -720), 200).rounded()
        if value != offset { offset = value }
    }
}

// MARK: Ambient warm background (average of the current hero poster)

struct HomeHSB: Equatable {
    var h: Double
    var s: Double
    var b: Double
    /// #2A2019.
    static let fallback = HomeHSB(h: 0.0686, s: 0.405, b: 0.165)
    var topColor: Color { Color(hue: h, saturation: s, brightness: b) }
    var deepColor: Color { Color(hue: h, saturation: s, brightness: b * 0.55) }
}

enum HomeAmbientColor {
    /// Downscale to 32x32, average, convert to HSB, clamp S to [0.25, 0.45] and B to [0.16, 0.22].
    /// When `source` is a jacket, only the visible front window is sampled — this
    /// is a 32×32 probe, never a replacement of the sharp-layer pixels.
    static func base(from image: UIImage, source: String? = nil) -> HomeHSB? {
        guard let cg = image.cgImage else { return nil }
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let crop = HeroFrontWindow.cropRect(image: image, source: source)
            ?? CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            let sx = CGFloat(side) / max(crop.width, 1)
            let sy = CGFloat(side) / max(crop.height, 1)
            context.draw(cg, in: CGRect(x: -crop.origin.x * sx, y: -crop.origin.y * sy,
                                        width: CGFloat(cg.width) * sx, height: CGFloat(cg.height) * sy))
            return true
        }
        guard drawn else { return nil }
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 0 {
            r += Double(pixels[i]); g += Double(pixels[i + 1]); b += Double(pixels[i + 2]); n += 1
        }
        guard n > 0 else { return nil }
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
        _ = UIColor(red: CGFloat(r / n / 255), green: CGFloat(g / n / 255), blue: CGFloat(b / n / 255), alpha: 1)
            .getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
        return HomeHSB(h: Double(hue),
                       s: min(max(Double(sat), 0.25), 0.45),
                       b: min(max(Double(bri), 0.16), 0.22))
    }
}

final class HomeAmbient: ObservableObject {
    @Published private(set) var base: HomeHSB = .fallback
    @Published private(set) var key = "fallback"

    func show(_ hsb: HomeHSB?, id: String) {
        let nextKey = hsb == nil ? "fallback" : id
        let next = hsb ?? .fallback
        guard nextKey != key || next != base else { return }
        base = next
        key = nextKey
    }
}

/// Ambient wash clipped to the hero + top overscroll. Never paints #14100D / #2A2019 under the rails.
private struct HomeAmbientBackground: View {
    @ObservedObject var ambient: HomeAmbient
    var heroHeight: CGFloat
    @ObservedObject var scroll: HomeScrollState
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let height = max(0, heroHeight - scroll.up) + scroll.pull
        ZStack {
            if reduceTransparency {
                ambient.base.topColor
            } else {
                LinearGradient(
                    stops: [
                        .init(color: ambient.base.topColor, location: 0),
                        .init(color: ambient.base.deepColor, location: 0.55),
                        .init(color: ambient.base.deepColor.opacity(0), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .id(ambient.key)
                .transition(.opacity)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .offset(y: 0)
        .animation(.easeInOut(duration: 0.8), value: ambient.key)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .clipped()
    }
}

// MARK: Floating chrome over the hero

/// 44 pt liquid-glass search button, floating top-right below the status bar.
/// Hit area is 44 pt (do not go below 44). If the glyph is unreadable on the
/// brightest daily-ranking poster, fall back the *material only* to `homeGlass`,
/// not the size.
private struct HomeSearchButton: View {
    @ObservedObject var scroll: HomeScrollState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 44, height: 44)
                .liquidGlassCircle()
                .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
                .contentShape(Circle())
        }
        .buttonStyle(HomePressStyle(scale: 0.92))
        // Fades slightly while scrolling up but stays visible and tappable.
        .opacity(1 - 0.22 * min(scroll.up, 120) / 120)
        .accessibilityLabel("搜索")
        .accessibilityIdentifier("home-search")
    }
}

/// Status-bar legibility once the hero has scrolled away.
private struct HomeTopScrim: View {
    @ObservedObject var scroll: HomeScrollState
    let start: CGFloat

    var body: some View {
        LinearGradient(colors: [Color(.systemBackground).opacity(0.94), Color(.systemBackground).opacity(0)],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: 30)
            .ignoresSafeArea(.container, edges: .top)
            .opacity(min(max((scroll.up - start) / 60, 0), 1))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// 看熱播 · 日榜 identity chip: dark glass over the hero image. Tapping opens
/// RankingsView playback with the same filters as the hero (high_score + daily).
private struct HomeHotChip: View {
    let action: () -> Void

    var body: some View {
        Button {
            GlassHaptic.tap()
            action()
        } label: {
            HStack(spacing: 5) {
                Text("看熱播 · 日榜")
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .homeGlass(in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle(scale: 0.94))
        .accessibilityLabel("看熱播，日榜")
        .accessibilityIdentifier("home-hot-daily")
    }
}

private struct HomeChevronCircle: View {
    var onDark: Bool = false
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(onDark ? Color.white : Color.primary.opacity(0.55))
            .frame(width: 26, height: 26)
            .background(Circle().fill(onDark ? Color.white.opacity(0.10) : Color.primary.opacity(0.08)))
    }
}

// MARK: Hero carousel

/// Synopsis is not in the list snapshot: fetched lazily from movieDetail (/api/v4/movies/{id})
/// for the current and next hero items, cached for the session. Never blocks the hero.
@MainActor
final class HomeHeroSynopsisStore {
    static let shared = HomeHeroSynopsisStore()
    private var values: [String: String] = [:]
    private var inFlight: Set<String> = []

    func cached(_ id: String) -> String? { values[id] }

    func fetch(_ movie: Movie) async -> String? {
        if let value = values[movie.id] { return value }
        if let own = Self.text(movie) { values[movie.id] = own; return own }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--poster-navigation-fixture") { return nil }
        #endif
        guard !inFlight.contains(movie.id) else { return nil }
        inFlight.insert(movie.id)
        defer { inFlight.remove(movie.id) }
        guard let detail = try? await JavDBSDK.shared.movieDetail(movie.id) else { return nil }
        let text = Self.text(detail) ?? ""
        values[movie.id] = text
        return text
    }

    private static func text(_ movie: Movie) -> String? {
        for candidate in [movie.summary, movie.desc] {
            let trimmed = (candidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}

/// 看熱播日榜全出血轮播（Build 328）。横滑保留，竖滑换条；芯片是「看熱播 · 日榜」。
/// 宽 = 屏宽、无圆角无边距、延伸到状态栏下；底部 / 顶部 scrim；左下文字块 + 独立圆点层；
/// 5 s 自动交叉淡入 + Ken Burns，手动翻页弹簧；下拉拉伸、上滑视差、文字随滚动淡出。
private struct HomeHeroCarousel: View {
    let movies: [Movie]
    let metrics: HomeMetrics
    @ObservedObject var scroll: HomeScrollState
    let ambient: HomeAmbient
    let isActive: Bool
    let onOpen: (Movie) -> Void
    let onHot: () -> Void
    let onMore: () -> Void

    @ObservedObject private var covers = HeroCoverStore.shared
    @State private var index = 0
    @State private var synopses: [String: String] = [:]
    @State private var touching = false
    @State private var dragging = false
    @State private var dragX: CGFloat = 0
    @State private var dragY: CGFloat = 0
    @State private var lastDragAt = Date.distantPast
    @State private var slideEdge: Edge?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    private var width: CGFloat { metrics.width }
    private var height: CGFloat { metrics.heroHeight }
    private var padding: CGFloat { metrics.padding }
    private var showsDots: Bool { movies.count > 1 }

    private var current: Movie? {
        guard !movies.isEmpty else { return nil }
        return movies[min(max(index, 0), movies.count - 1)]
    }

    private func heroMovie(at offset: Int) -> Movie? {
        guard !movies.isEmpty else { return nil }
        return movies[(min(max(index, 0), movies.count - 1) + offset) % movies.count]
    }

    private func cover(_ movie: Movie) -> HeroCoverPresentation {
        covers.presentation(for: movie.id)
    }

    private var currentCover: HeroCoverPresentation {
        current.map(cover) ?? HeroCoverPresentation()
    }

    /// Autoplay only advances to pages already finalized as A/B. It pauses on
    /// C-tier or blur pages (manual swipe still reaches them) and is off when
    /// no A/B page exists.
    private var hasABPage: Bool { movies.contains { cover($0).isAB } }

    private var autoplayEnabled: Bool {
        movies.count > 1 && isActive && !touching && !dragging && scenePhase == .active
            && !reduceMotion && !voiceOver && scroll.up < height * 0.85
            && currentCover.isAB && hasABPage
    }

    private func nextABIndex() -> Int? {
        guard !movies.isEmpty else { return nil }
        let start = min(max(index, 0), movies.count - 1)
        for step in 1..<movies.count {
            let i = (start + step) % movies.count
            if cover(movies[i]).isAB { return i }
        }
        return nil
    }

    /// Global empty is judged from per-item 已定案（可升级） with no floor.
    /// A title that still has a DTO cover/thumb is not empty — the page paints
    /// that unblurred floor — so the banner stays off.
    private var showCoverFailure: Bool {
        !movies.isEmpty && movies.allSatisfy { movie in
            let p = cover(movie)
            return p.settled && !p.hasQuick && !Self.hasDTOFloor(movie)
        }
    }

    private static func hasDTOFloor(_ movie: Movie) -> Bool {
        let cover = (movie.coverURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let thumb = (movie.thumbURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !cover.isEmpty || !thumb.isEmpty
    }

    /// Fade text / dots / chip over the first 120 pt of scroll-up.
    private var chromeOpacity: Double { 1 - Double(min(scroll.up, 120) / 120) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Button {
                // Overlay tap is the sole navigation entry. The button stays for
                // VoiceOver only and is hit-disabled so the overlay can receive taps.
                guard let movie = current else { return }
                onOpen(movie)
            } label: {
                imageLayer
            }
            .buttonStyle(HeroTouchStyle(touching: $touching))
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityHint("打開詳情")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("home-hero")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: go(1, slide: false)
                case .decrement: go(-1, slide: false)
                @unknown default: break
                }
            }

            // Sibling of the hit-disabled button (not its overlay) so taps reach
            // it. HomeHotChip and HomeHeroMoreButton are later in this ZStack
            // and keep their own hit targets; taps there must not also open detail.
            HeroSwipeOverlay(
                scrollOffset: { scroll.offset },
                index: { index },
                count: { movies.count },
                onTrackHorizontal: { value in
                    dragging = true
                    dragX = value
                },
                onTrackVertical: { value in
                    dragging = true
                    dragY = value
                },
                onPageHorizontal: { delta in
                    // lastDragAt is set only on page-commit, then used to
                    // suppress a trailing touch for 0.35s after a swipe.
                    lastDragAt = Date()
                    dragging = false
                    go(delta, slide: true, vertical: false)
                },
                onPageVertical: { delta in
                    lastDragAt = Date()
                    dragging = false
                    go(delta, slide: true, vertical: true)
                },
                onSpringHorizontal: {
                    dragging = false
                    withAnimation(.spring(response: HeroSwipePolicy.pageSpringResponse,
                                          dampingFraction: HeroSwipePolicy.pageSpringDamping)) { dragX = 0 }
                },
                onSpringVertical: {
                    dragging = false
                    withAnimation(.spring(response: HeroSwipePolicy.pageSpringResponse,
                                          dampingFraction: HeroSwipePolicy.pageSpringDamping)) { dragY = 0 }
                },
                onTouch: { down in
                    touching = down
                },
                onTap: {
                    guard Date().timeIntervalSince(lastDragAt) > HeroTapPolicy.trailingSuppress,
                          let movie = current else { return }
                    onOpen(movie)
                },
                lastPageCommitAt: { lastDragAt }
            )
            // Build 332: the overlap band (bottom heroContentOverlap) is not in the
            // hero gesture hit area — shortcuts / rails own those taps.
            .frame(width: width, height: max(0, height - HomeMetrics.heroContentOverlap))
            .frame(width: width, height: height, alignment: .top)
            .accessibilityHidden(true)

            scrims
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            textBlock
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if showsDots {
                HomeHeroDots(count: movies.count, index: min(index, movies.count - 1))
                    .padding(.leading, padding)
                    .padding(.bottom, 46 + HomeMetrics.heroContentOverlap)
                    .frame(width: width, height: height, alignment: .bottomLeading)
                    .opacity(chromeOpacity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            HomeHotChip(action: onHot)
                .padding(.leading, padding)
                .padding(.top, metrics.safeTop + 13)
                .opacity(chromeOpacity)

            HomeHeroMoreButton(action: onMore)
                .padding(.bottom, 38 + HomeMetrics.heroContentOverlap)
                .frame(width: width, height: height, alignment: .bottom)
                .opacity(chromeOpacity)

            if showCoverFailure {
                Text("高清封面加载失败，下拉刷新重试")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.86))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, padding)
                    .frame(width: width, height: height)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: width, height: height)
        .onAppear {
            if !HeroCoverStore.appCallsSuspended { covers.setCurrentIndex(index, movies: movies) }
            publishAmbient()
        }
        .onChange(of: movies.map(\.id)) { _, _ in
            index = 0
            if !HeroCoverStore.appCallsSuspended { covers.setCurrentIndex(0, movies: movies) }
            publishAmbient()
        }
        .onChange(of: index) { _, new in
            if !HeroCoverStore.appCallsSuspended { covers.setCurrentIndex(new, movies: movies) }
        }
        .onChange(of: ambientKey) { _, _ in publishAmbient() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !HeroCoverStore.appCallsSuspended { covers.retryOnForeground() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .heroCoverNetworkRecovered)) { _ in
            if !HeroCoverStore.appCallsSuspended { covers.noteNetworkRecovered() }
        }
        // Synopsis for current + next, lazily; never blocks the hero.
        .task(id: current?.id) {
            for offset in 0..<min(2, movies.count) {
                guard let movie = heroMovie(at: offset), synopses[movie.id] == nil, !Task.isCancelled else { continue }
                if let text = await HomeHeroSynopsisStore.shared.fetch(movie), !Task.isCancelled {
                    withAnimation(.easeOut(duration: 0.25)) { synopses[movie.id] = text }
                }
            }
        }
        // Autoplay: 5s interval; only advances onto finalized A/B pages.
        .task(id: autoplayKey) {
            guard autoplayEnabled else { return }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, autoplayEnabled, let next = nextABIndex() else { return }
            go(to: next, slide: false, delta: 1)
        }
    }

    // Image layer: only transform / opacity animate (stretch, parallax, Ken Burns, crossfade).
    private var imageLayer: some View {
        ZStack {
            if let movie = current {
                HomeHeroPage(presentation: cover(movie), movie: movie, metrics: metrics, kenBurns: !reduceMotion)
                    .id(movie.id)
                    .transition(pageTransition)
            }
        }
        .frame(width: width, height: height)
        .offset(x: dragX, y: dragY)
        // Pull-down stretch (anchored at the bottom so it fills the gap above) + scroll-up parallax.
        .scaleEffect(1 + min(scroll.pull, 120) / height, anchor: .bottom)
        .offset(y: scroll.up * 0.45)
        // Clip the sides and the bottom edge only; the stretch may grow above the top.
        .mask(alignment: .bottom) {
            Rectangle().frame(width: width, height: height + 400)
        }
        .contentShape(Rectangle())
    }

    /// Bottom scrim for text legibility, then — Build 333, mirroring the detail
    /// page's portraitHero — the image bottom *graduates* into the page
    /// background instead of being hard-cut by the shortcuts sheet: the black
    /// scrim hands off inside the fade band and a systemBackground gradient
    /// reaches full opacity exactly at the sheet's top edge (hero height minus
    /// the content overlap), so the seam disappears and the shortcut buttons
    /// sit on the poster's faded foot. Plus a top scrim (black 0.28 → 0 over
    /// 110 pt) for the status bar. Not parallaxed.
    private var scrims: some View {
        // Visible fade band above the sheet's top edge.
        let band: CGFloat = 56
        let edge = max(0, (height - HomeMetrics.heroContentOverlap) / max(height, 1))
        let bandTop = max(0, (height - HomeMetrics.heroContentOverlap - band) / max(height, 1))
        return ZStack(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 0.35),
                    .init(color: .black.opacity(0.18), location: 0.56),
                    .init(color: .black.opacity(0.45), location: 0.70),
                    .init(color: .black.opacity(0.62), location: 0.80),
                    .init(color: .black.opacity(0), location: edge)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(
                stops: [
                    .init(color: Color(.systemBackground).opacity(0), location: bandTop),
                    .init(color: Color(.systemBackground), location: edge),
                    .init(color: Color(.systemBackground), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(colors: [.black.opacity(0.28), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 110)
        }
        .frame(width: width, height: height)
    }

    private var textBlock: some View {
        Group {
            if let movie = current {
                VStack(alignment: .leading, spacing: 6) {
                    Text(headline(movie))
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
                    if let date = movie.releaseDate?.trimmingCharacters(in: .whitespaces), !date.isEmpty {
                        Text(date)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.72))
                    }
                    if let synopsis = synopsis(movie) {
                        Text(synopsis)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .lineLimit(2)
                            .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
                    }
                }
                .frame(maxWidth: width - padding * 2, alignment: .leading)
                .id(movie.id)
                .transition(.opacity)
            }
        }
        .padding(.leading, padding)
        // Build 333: the whole bottom chrome rides above the detail-style fade
        // band (dots: 6 pt tall at 46 pt above the bottom edge, plus the Build
        // 332 content overlap), so the typography stays on the dark scrim and
        // fully visible — never inside the graduated foot of the poster.
        .padding(.bottom, (showsDots ? 66 : 50) + HomeMetrics.heroContentOverlap)
        .frame(width: width, height: height, alignment: .bottomLeading)
        .opacity(chromeOpacity)
    }

    private var pageTransition: AnyTransition {
        guard let edge = slideEdge else { return .opacity }
        if edge == .top || edge == .bottom {
            return .asymmetric(insertion: .move(edge: edge),
                               removal: .move(edge: edge == .bottom ? .top : .bottom))
        }
        return .asymmetric(insertion: .move(edge: edge),
                           removal: .move(edge: edge == .trailing ? .leading : .trailing))
    }

    private func go(_ delta: Int, slide: Bool, vertical: Bool = false) {
        guard movies.count > 1 else { return }
        let currentIndex = min(max(index, 0), movies.count - 1)
        let next: Int
        if vertical {
            next = currentIndex + delta
            guard movies.indices.contains(next) else { return }
        } else {
            next = (currentIndex + delta + movies.count) % movies.count
        }
        go(to: next, slide: slide, delta: delta, vertical: vertical)
    }

    private func go(to next: Int, slide: Bool, delta: Int? = nil, vertical: Bool = false) {
        guard movies.count > 1, next != index, movies.indices.contains(next) else { return }
        let inferred = delta ?? (next > index ? 1 : -1)
        if slide {
            if vertical {
                slideEdge = inferred > 0 ? .bottom : .top
            } else {
                slideEdge = inferred > 0 ? .trailing : .leading
            }
            withAnimation(.spring(response: HeroSwipePolicy.pageSpringResponse,
                                  dampingFraction: HeroSwipePolicy.pageSpringDamping)) {
                index = next
                dragX = 0
                dragY = 0
            }
        } else {
            slideEdge = nil
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.6)) {
                index = next
                dragX = 0
                dragY = 0
            }
        }
    }

    private var autoplayKey: String {
        "\(index)|\(autoplayEnabled)|\(movies.count)|\(currentCover.isAB)|\(hasABPage)"
    }

    private var ambientKey: String {
        guard let movie = current else { return "" }
        // Build 332: follows the currently displayed (front-windowed) bitmap.
        guard let hsb = cover(movie).ambient else { return movie.id + "#" }
        return movie.id + "#hsb#\(hsb.h)|\(hsb.s)|\(hsb.b)"
    }

    private func publishAmbient() {
        guard let movie = current else { return }
        ambient.show(cover(movie).ambient, id: movie.id)
    }

    private func headline(_ movie: Movie) -> String {
        let number = movie.displayNumber
        guard let title = movie.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty, title != number else { return number }
        return number + "  " + title
    }

    private func synopsis(_ movie: Movie) -> String? {
        guard let text = synopses[movie.id] ?? HomeHeroSynopsisStore.shared.cached(movie.id), !text.isEmpty else { return nil }
        return text
    }

    private var accessibilityText: String {
        guard let movie = current else { return "看熱播日榜" }
        let date = movie.releaseDate?.trimmingCharacters(in: .whitespaces) ?? ""
        return date.isEmpty ? headline(movie) : "\(movie.displayNumber) \(movie.displayTitle), \(date)"
    }
}

/// Reports touch-down so autoplay pauses while the finger is on the hero; no visual change.
private struct HeroTouchStyle: ButtonStyle {
    @Binding var touching: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in touching = pressed }
    }
}

/// One hero page: layered full-bleed paint, never an inset card.
/// Build 331/332 two-level floor: level 1 = the sharpest *original* decoded
/// image in the movie's current record (cover_url preferred, thumb fallback),
/// painted unblurred (no radius, no brightness dim); level 2 = the official
/// DetailPosterResolver winner, cross-faded in (plain fade ≤ 0.45s) on arrival.
/// The main layer paints the loader's decoded original bitmap with zero pixel
/// reprocessing. Landscape jackets are shown only through a display-time window
/// equal to `FrontPosterPolicy.cropRect` — no layer may show the back-cover
/// collage. Brand brown #2A2019 is never the visible empty floor.
private struct HomeHeroPage: View {
    let presentation: HeroCoverPresentation
    let movie: Movie
    let metrics: HomeMetrics
    let kenBurns: Bool
    @State private var zoomed = false
    @State private var floorImage: UIImage?
    @State private var floorSource: String?

    var body: some View {
        let size = CGSize(width: metrics.width, height: metrics.heroHeight)
        ZStack {
            HomeTheme.heroLoadingFloor
            // Level 1: floor. Level 2: official resolver winner on top.
            if let floor = presentation.blurImage ?? floorImage {
                HomeAnchoredFill(image: floor, size: size,
                                 source: presentation.floorSource ?? floorSource)
            }
            if let sharp = presentation.sharpImage {
                HomeAnchoredFill(image: sharp, size: size, source: presentation.winnerURL)
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(.easeOut(duration: HeroCoverPolicy.crossfadeDuration), value: presentation.token)
        .scaleEffect(zoomed ? 1.05 : 1.0)
        .task(id: movie.id) {
            // Safety net if HeroCoverStore is stuck: load the original cover_url
            // (then thumb). The paint path windows jackets at display time. Skip
            // hanging / delayed stand-ins so a slow source cannot block the floor.
            if presentation.blurImage != nil || presentation.sharpImage != nil { return }
            await withTaskGroup(of: (String, UIImage?).self) { group in
                let cover = movie.coverURL.flatMap { $0.contains("/small_covers/") ? nil : $0 }
                for url in [cover, movie.thumbURL] {
                    guard let url, !url.isEmpty else { continue }
                    if url.hasPrefix("fixture://hang") || url.hasPrefix("fixture://delay") { continue }
                    let size = url == cover ? 1024 : 640
                    group.addTask { (url, await ImageLoader.shared.load(url, maxPixelSize: size, timeout: 4)) }
                }
                var best: UIImage?
                var bestSource: String?
                for await (url, image) in group {
                    guard let image else { continue }
                    if best == nil || HeroCoverStore.floorRank(image, source: url) > HeroCoverStore.floorRank(best!, source: bestSource) {
                        best = image
                        bestSource = url
                        floorImage = image
                        floorSource = url
                    }
                }
            }
        }
        .onAppear {
            guard kenBurns else { return }
            withAnimation(.linear(duration: 5.6)) { zoomed = true }
        }
    }
}

/// 44 pt hit target, bottom-center of the hero (chevron.down + 「更多」), over the scrim.
private struct HomeHeroMoreButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            GlassHaptic.tap()
            action()
        } label: {
            VStack(spacing: 1) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                Text("更多")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(Color.white.opacity(0.92))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle(scale: 0.94))
        .accessibilityLabel("更多")
        .accessibilityIdentifier("home-hero-more")
    }
}

/// Horizontal anchor of a non-jacket hero layer. Portrait rasters center;
/// a residual landscape raster is right-anchored (trailing = DVD front).
enum HeroFillAnchor {
    static func x(imageWidth iw: CGFloat, imageHeight ih: CGFloat, drawnWidth dw: CGFloat, containerWidth w: CGFloat) -> CGFloat {
        iw > ih ? (w - dw) : (w - dw) / 2
    }
}

/// aspectFill with a vertical anchor (0 = top, 0.5 = center).
/// Build 332: paints the original decoded bitmap (zero pixel reprocessing).
/// Landscape jackets are shown only through a view-level scale / offset / clip
/// equal to `FrontPosterPolicy.cropRect`. Non-jacket images keep the existing
/// passthrough / fill. `.interpolation(.high)` stays — it now scales a pristine
/// decoded image.
struct HomeAnchoredFill: View {
    let image: UIImage
    let size: CGSize
    var source: String? = nil
    var anchorY: CGFloat = 0.22

    var body: some View {
        let p = HeroFrontWindow.placement(image: image, source: source, container: size, anchorY: anchorY)
        Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: p.drawnSize.width, height: p.drawnSize.height)
            .offset(x: p.offset.width, y: p.offset.height)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
    }
}

/// Independent dots layer: 6×6 white 45%, selected 18×6 white capsule, spacing 5; windowed to 9.
private struct HomeHeroDots: View {
    let count: Int
    let index: Int

    var body: some View {
        let visible = min(count, 9)
        let start = count <= 9 ? 0 : min(max(index - 4, 0), count - 9)
        HStack(spacing: 5) {
            ForEach(start..<(start + visible), id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(i == index ? 1 : 0.45))
                    .frame(width: i == index ? 18 : 6, height: 6)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: index)
    }
}

// MARK: Rails

private struct HomeRailHeader: View {
    let title: String
    let padding: CGFloat
    var titleIdentifier: String? = nil
    var shuffle: (() -> Void)? = nil
    var more: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(HomeTheme.primary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(titleIdentifier ?? "home-section-\(title)")
            Spacer(minLength: 8)
            if let shuffle {
                // 換一組 kept as a small text button.
                Button {
                    GlassHaptic.tap()
                    shuffle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11, weight: .semibold))
                        Text("換一組")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(HomeTheme.secondary)
                    .padding(.horizontal, 6)
                    .frame(height: 26)
                    .contentShape(Rectangle().inset(by: -9))
                }
                .buttonStyle(HomePressStyle(scale: 0.94))
                .accessibilityLabel("" + title + " 換一組")
                .accessibilityIdentifier("home-shuffle-" + title)
            }
            if let more {
                Button {
                    GlassHaptic.tap()
                    more()
                } label: {
                    HomeChevronCircle()
                        .frame(width: 26, height: 26)
                        // 44 pt hit area around the 26 pt circle.
                        .contentShape(Rectangle().inset(by: -9))
                }
                .buttonStyle(HomePressStyle(scale: 0.9))
                .accessibilityLabel("\(title) 全部")
            }
        }
        .padding(.horizontal, padding)
        .frame(minHeight: 26)
    }
}

/// 3-column vertical poster grid (Build 329). Reuses MoviePosterGrid cells
/// (`MoviePosterCard`). Caps at 9 posters (3×3) on the home page. There is no
/// horizontal cover-rail swipe; 「>」 / 更多 opens the existing full list.
private struct HomePosterGrid: View {
    var upgradesVisibleHQ = true
    let movies: [Movie]
    let metrics: HomeMetrics
    let open: (Movie) -> Void

    private static let columns = 3

    var body: some View {
        let items = Array(movies.prefix(HomeViewModel.homeGridCap))
        let cols = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12), count: Self.columns)
        LazyVGrid(columns: cols, spacing: 16) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, movie in
                Button {
                    open(movie)
                } label: {
                    MoviePosterCard(movie: movie, upgradesVisibleHQ: upgradesVisibleHQ)
                }
                .buttonStyle(HomePressStyle(scale: 0.97, spring: true))
                .accessibilityIdentifier("poster-" + movie.id)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
                .clipped()
                .onAppear {
                    if upgradesVisibleHQ {
                        HomeHQPosterPrefetch.scheduleAhead(movies: items, around: idx)
                    }
                }
            }
        }
        .padding(.horizontal, metrics.padding)
        .accessibilityIdentifier("home-poster-grid")
    }
}


enum HomePlaceholder {
    case hero(HomeMetrics)
    case rail(HomeMetrics)
}

/// Same-size shimmer while loading; film.stack tap-to-retry when a first load failed.
private struct HomePlaceholderView: View {
    let kind: HomePlaceholder
    let failed: Bool
    let retry: () -> Void

    var body: some View {
        switch kind {
        case .hero(let m):
            ZStack {
                if failed {
                    Color(.systemGray5)
                    failedBadge(size: 26)
                } else {
                    HomeShimmer()
                }
            }
            .frame(width: m.width, height: m.heroHeight)
            .contentShape(Rectangle())
            .onTapGesture { if failed { retry() } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(failed ? "載入失敗，點按重試" : "載入中")
            .accessibilityAddTraits(failed ? .isButton : [])
        case .rail(let m):
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12), count: 3), spacing: 16) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 6) {
                        ZStack {
                            if failed {
                                Color(.systemGray5)
                                failedBadge(size: 20)
                            } else {
                                HomeShimmer()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .aspectRatio(2.0/3.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Capsule().fill(Color.primary.opacity(0.10)).frame(height: 9)
                            Capsule().fill(Color.primary.opacity(0.07)).frame(width: 60, height: 8)
                        }
                        .frame(height: 34, alignment: .topLeading)
                    }
                }
            }
            .padding(.horizontal, m.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { if failed { retry() } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(failed ? "載入失敗，點按重試" : "載入中")
            .accessibilityAddTraits(failed ? .isButton : [])
        }
    }

    private func failedBadge(size: CGFloat) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "film.stack")
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(HomeTheme.tertiary)
            Text("點按重試")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(HomeTheme.tertiary)
        }
    }
}

/// Light shimmer for loading placeholders on the system background.
private struct HomeShimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            Color(.systemGray5)
                .overlay {
                    LinearGradient(colors: [.clear, Color.white.opacity(0.45), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: w * 0.6)
                        .offset(x: phase * w * 1.3)
                }
        }
        .clipped()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) { phase = 1.2 }
        }
        .accessibilityHidden(true)
    }
}

struct ArticlesView: View {
    @State private var articles: [Article] = []
    @State private var loading = true

    var body: some View {
        Group {
            if loading && articles.isEmpty {
                EmptyStateView(text: "載入資訊…")
            } else {
                List(articles, id: \.stableArticleID) { article in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(article.title ?? "")
                            .font(.system(size: 15, weight: .medium))
                        if let date = article.createdAt {
                            Text(date).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("AV資訊")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loading = true
            articles = (try? await JavDBSDK.shared.articles()) ?? []
            loading = false
        }
    }
}

struct HotReviewsView: View {
    @State private var reviews: [Review] = []
    @State private var loading = true

    var body: some View {
        Group {
            if loading && reviews.isEmpty {
                EmptyStateView(text: "載入短評…")
            } else {
                List(reviews, id: \.stableReviewID) { review in
                    ReviewRow(review: review)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("看短評")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loading = true
            reviews = (try? await JavDBSDK.shared.hotReviews()) ?? []
            loading = false
        }
    }
}

/// 往期推薦：/api/v1/movies/recommend_periods
struct PastRecommendView: View {
    @StateObject private var vm = PastRecommendViewModel()
    @State private var query = ""
    @State private var showSearch = false

    var body: some View {
        List {
            ForEach(Array(vm.filtered(query).enumerated()), id: \.element.id) { idx, period in
                NavigationLink {
                    PeriodMoviesView(period: period)
                } label: {
                    HStack(spacing: 8) {
                        Text(period.titleText)
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                        if !period.dateText.isEmpty {
                            Text("(\(period.dateText))")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 10)
                }
                .listRowBackground(idx % 2 == 0 ? Color(.systemBackground) : Color(.systemGray5))
                .listRowSeparator(.hidden)
                .onAppear {
                    if period.id == vm.periods.last?.id {
                        Task { await vm.loadMore() }
                    }
                }
            }
            if vm.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationTitle("往期推薦")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSearch.toggle()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
            }
        }
        .searchable(text: $query, isPresented: $showSearch, prompt: "搜尋期數")
        .task { await vm.loadMore() }
    }
}

@MainActor
final class PastRecommendViewModel: ObservableObject {
    @Published var periods: [RecommendPeriod] = []
    @Published var isLoading = false
    private var page = 1
    private var hasMore = true

    func filtered(_ query: String) -> [RecommendPeriod] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return periods }
        return periods.filter {
            $0.titleText.contains(q) || $0.dateText.contains(q) || "\($0.period ?? 0)".contains(q)
        }
    }

    func loadMore() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        defer { isLoading = false }
        let next = (try? await JavDBSDK.shared.recommendPeriods(page: page, limit: 24)) ?? []
        if next.isEmpty {
            hasMore = false
            return
        }
        let ids = Set(periods.map(\.id))
        periods.append(contentsOf: next.filter { !ids.contains($0.id) })
        page += 1
    }
}

struct PeriodMoviesView: View {
    let period: RecommendPeriod
    @StateObject private var vm: MovieListViewModel

    init(period: RecommendPeriod) {
        self.period = period
        let p = period.period
        _vm = StateObject(wrappedValue: MovieListViewModel { page in
            try await JavDBSDK.shared.recommendMovies(page: page, period: p)
        })
    }

    var body: some View {
        ScrollView {
            MoviePosterGrid(upgradesVisibleHQ: true, movies: vm.movies, onAppearLast: { movie in
                vm.loadMoreIfNeeded(current: movie)
            })
            if vm.isLoading { ProgressView().padding() }
        }
        .navigationTitle(period.dateText.isEmpty ? period.titleText : "\(period.titleText)  \(period.dateText)")
        .navigationBarTitleDisplayMode(.inline)
        .task { if vm.movies.isEmpty { await vm.loadMore() } }
        .refreshable { await vm.refresh() }
    }
}

private struct HomeStatusBarObserver: View {
    @ObservedObject var scroll: HomeScrollState
    var active: Bool
    var cutoff: CGFloat
    var body: some View {
        HomeStatusBarStyle(lightContent: active && scroll.up < cutoff)
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Isolated status-bar style: light content over the hero image, dark content
/// over the light rails. Does not force the page color scheme.
private struct HomeStatusBarStyle: UIViewControllerRepresentable {
    var lightContent: Bool

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.lightContent = lightContent
        controller.setNeedsStatusBarAppearanceUpdate()
        controller.propagate()
    }

    final class Controller: UIViewController {
        var lightContent = true
        override var preferredStatusBarStyle: UIStatusBarStyle {
            lightContent ? .lightContent : .darkContent
        }
        override var childForStatusBarStyle: UIViewController? { nil }
        func propagate() {
            setNeedsStatusBarAppearanceUpdate()
            var current = parent
            while let viewController = current {
                viewController.setNeedsStatusBarAppearanceUpdate()
                current = viewController.parent
            }
        }
    }
}
