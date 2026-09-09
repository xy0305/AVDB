//
//  HomeView.swift
//  AVDB
//
//  首页：快捷入口、佳片推荐、最新上架、TOP250、近期磁链、我的关注。
//

import SwiftUI

struct HomeView: View {
    @StateObject private var vm = HomeViewModel()
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    searchBar
                    shortcutRow
                    recommendSection
                    latestSection
                    top250Banner
                    magnetSection
                    followingSection
                }
                .padding(.vertical, 8)
            }
            .background {
                LiquidGlassBackground()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    EmptyView()
                }
            }
            .task { await vm.initialLoad() }
            .refreshable { await vm.initialLoad() }
            .navigationDestination(isPresented: $goSearch) {
                SearchView()
            }
            .navigationDestination(isPresented: $goRankings) {
                RankingsView(embedded: true, initialTab: .top250)
            }
            .navigationDestination(isPresented: $goHot) {
                RankingsView(embedded: true, initialTab: .playback)
            }
            .navigationDestination(isPresented: $goLatest) {
                CatalogListView(title: "最新上架", type: .censored, source: .latest)
            }
            .navigationDestination(isPresented: $goMagnets) {
                CatalogListView(title: "近期磁鏈", type: .censored, source: .latest)
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
        }
    }

    /// 首页顶部原生搜索框（点击进入搜索页）
    private var searchBar: some View {
        Button {
            goSearch = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                Text("搜索番號 / 關鍵詞")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.blue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .liquidGlass(cornerRadius: 16, edgeOpacity: 0.45, glowOpacity: 0.18, shadowRadius: 12, shadowY: 4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var shortcutRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                shortcut("看熱播", "play.rectangle.fill", Color.red) { goHot = true }
                shortcut("AV資訊", "newspaper.fill", Color.orange) { goArticles = true }
                shortcut("看短評", "text.bubble.fill", Color.purple) { goReviews = true }
                shortcut("找磁鏈", "link.circle.fill", Color.green) { goMagnets = true }
                shortcut("系列", "square.stack.3d.up.fill", Color.blue) { goSeries = true }
                shortcut("片商", "building.2.fill", Color.teal) { goMakers = true }
                shortcut("導演", "person.3.fill", Color.indigo) { goDirectors = true }
                shortcut("TOP250", "crown.fill", Color.yellow) { goRankings = true }
            }
            .padding(.horizontal, 16)
        }
    }

    private func shortcut(_ title: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    // 液态玻璃圆形底座：材质 + 色调 + 镜面高光
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 56, height: 56)
                        .overlay {
                            Circle()
                                .fill(color.opacity(0.12))
                        }
                        .overlay {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.white.opacity(0.3), .clear],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                )
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.5),
                                            .white.opacity(0.15),
                                            .white.opacity(0.35),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.8
                                )
                        }
                        .shadow(color: color.opacity(0.15), radius: 8, y: 3)
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(color.gradient)
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .frame(width: 72)
        }
        .buttonStyle(.plain)
    }

    private var recommendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.yellow.gradient)
                    Text("佳片推薦")
                        .font(.system(size: 17, weight: .bold))
                }
                Text(vm.periodLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule(style: .continuous)
                            .fill(.blue.gradient)
                            .overlay {
                                Capsule(style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [.white.opacity(0.3), .clear],
                                            startPoint: .top,
                                            endPoint: .center
                                        )
                                    )
                            }
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(.white.opacity(0.35), lineWidth: 0.6)
                            }
                    }
                Spacer()
                NavigationLink {
                    PastRecommendView()
                } label: {
                    HStack(spacing: 4) {
                        Text("往期")
                            .font(.system(size: 14, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 16)

            if vm.recommended.isEmpty {
                EmptyStateView(text: "載入推薦…")
                    .padding(.horizontal, 16)
            } else if let movie = vm.recommended.first {
                NavigationLink {
                    MovieDetailView(movieID: movie.id)
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        ZStack(alignment: .topTrailing) {
                            JavDBImage(url: movie.coverURL ?? movie.thumbURL)
                                .aspectRatio(2/3, contentMode: .fill)
                                .frame(width: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            
                            if let score = movie.score, score > 0 {
                                Text(String(format: "%.1f", score))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background {
                                        Capsule(style: .continuous)
                                            .fill(.orange.gradient)
                                            .overlay {
                                                Capsule(style: .continuous)
                                                    .fill(
                                                        LinearGradient(
                                                            colors: [.white.opacity(0.3), .clear],
                                                            startPoint: .top,
                                                            endPoint: .center
                                                        )
                                                    )
                                            }
                                    }
                                    .padding(6)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(movie.displayNumber)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.blue)
                            
                            Text(movie.displayTitle)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(3)
                            
                            Spacer()
                            
                            if let score = movie.score, score > 0 {
                                HStack(spacing: 3) {
                                    ForEach(0..<5, id: \.self) { i in
                                        Image(systemName: i < Int(score / 2) ? "star.fill" : "star")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.orange.gradient)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                    .liquidGlass(cornerRadius: 18, tint: .blue, edgeOpacity: 0.5, glowOpacity: 0.16, shadowRadius: 14, shadowY: 6)
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var latestSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeaderBar(title: "最新上架") { goLatest = true }
            if vm.latest.isEmpty {
                EmptyStateView(text: "載入最新…")
            } else {
                MoviePosterGrid(movies: Array(vm.latest.prefix(9)))
            }
            Button {
                Task { await vm.shuffleLatest() }
            } label: {
                Text("換一組")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
    }

    private var top250Banner: some View {
        Button { goRankings = true } label: {
            ZStack {
                JavDBImage(url: vm.latest.first?.coverURL, contentMode: .fill)
                    .frame(height: 90)
                    .clipped()
                    .overlay {
                        LinearGradient(
                            colors: [
                                .black.opacity(0.25),
                                .black.opacity(0.45),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                Text("TOP250")
                    .font(.largeTitle.weight(.heavy))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .glassEdge(cornerRadius: 12, opacity: 0.4)
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }

    private var magnetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeaderBar(title: "近期磁鏈更新") { goMagnets = true }
            if vm.magnets.isEmpty {
                EmptyStateView(text: "載入磁鏈…")
            } else {
                MoviePosterGrid(movies: Array(vm.magnets.prefix(9)))
            }
            Button {
                Task { await vm.shuffleMagnets() }
            } label: {
                Text("換一組")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
    }

    private var followingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("我的關注")
                    .font(.headline)
                Spacer()
                Text("更新時間倒序")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            if vm.following.isEmpty {
                Text("登入後顯示關注內容")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
            } else {
                MoviePosterGrid(movies: vm.following)
            }
        }
    }
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var recommended: [Movie] = []
    @Published var latest: [Movie] = []
    @Published var magnets: [Movie] = []
    @Published var following: [Movie] = []
    @Published var periodLabel = "週一/四更新"
    @Published var periods: [RecommendPeriod] = []
    private var latestPage = 1
    private var magnetPage = 2
    private let sdk = JavDBSDK.shared

    func initialLoad() async {
        async let rec = try? sdk.recommendMovies(page: 1)
        async let latestTask = try? sdk.latestMovies(page: 1, limit: 9, type: "all", filterBy: "can_play", sortBy: "update")
        async let magTask = try? sdk.latestMovies(page: 2, limit: 9, type: "all", filterBy: "can_play", sortBy: "update")
        async let periodsTask = try? sdk.recommendPeriods()
        async let followTask = try? sdk.recentViewed()

        recommended = await rec ?? []
        latest = await latestTask ?? []
        magnets = (await magTask ?? []).filter { ($0.magnetsCount ?? 0) > 0 }
        if magnets.isEmpty { magnets = latest }
        periods = await periodsTask ?? []
        following = await followTask ?? []
        if let created = periods.first?.createdAt, created.count >= 10 {
            periodLabel = String(created.prefix(10))
        }
    }

    func shuffleLatest() async {
        latestPage += 1
        let next = (try? await sdk.latestMovies(page: latestPage, limit: 9, type: "all", filterBy: "can_play", sortBy: "update")) ?? []
        if next.isEmpty { latestPage = 1 }
        else { latest = next }
    }

    func shuffleMagnets() async {
        magnetPage += 1
        let next = (try? await sdk.latestMovies(page: magnetPage, limit: 9, type: "all", filterBy: "can_play", sortBy: "update")) ?? []
        let filtered = next.filter { ($0.magnetsCount ?? 0) > 0 }
        if filtered.isEmpty { magnetPage = 1 }
        else { magnets = filtered }
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
            MoviePosterGrid(movies: vm.movies, onAppearLast: { movie in
                vm.loadMoreIfNeeded(current: movie)
            })
            if vm.isLoading { ProgressView().padding() }
            // 底部占位：避开悬浮 Tab 栏，让最后一行作品完整露出
            Color.clear.frame(height: 100)
        }
        .navigationTitle(period.dateText.isEmpty ? period.titleText : "\(period.titleText)  \(period.dateText)")
        .navigationBarTitleDisplayMode(.inline)
        .task { if vm.movies.isEmpty { await vm.loadMore() } }
        .refreshable { await vm.refresh() }
    }
}
