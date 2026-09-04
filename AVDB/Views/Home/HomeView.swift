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
            .background(Color(.systemBackground))
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
                NamedListView(kind: .makers)
            }
            .navigationDestination(isPresented: $goDirectors) {
                NamedListView(kind: .directors)
            }
        }
    }

    /// 首页顶部原生搜索框（点击进入搜索页）
    private var searchBar: some View {
        Button {
            goSearch = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                Text("搜索番号 / 关键词")
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var shortcutRow: some View {
        HStack(spacing: 0) {
            shortcut("看熱播", "play.rectangle.fill", Color.blue) { goHot = true }
            shortcut("AV資訊", "newspaper.fill", Color.red) { goArticles = true }
            shortcut("看短評", "text.bubble.fill", Color.orange) { goReviews = true }
            shortcut("找磁鏈", "link", Color.green) { goMagnets = true }
            shortcut("系列", "square.stack", Color.purple) { goSeries = true }
            shortcut("片商", "building.2", Color.teal) { goMakers = true }
            shortcut("导演", "person.3", Color.indigo) { goDirectors = true }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private func shortcut(_ title: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var recommendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("佳片推薦")
                    .font(.headline)
                Text(vm.periodLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.systemGray6), in: Capsule())
                Spacer()
                NavigationLink {
                    PastRecommendView()
                } label: {
                    HStack(spacing: 2) {
                        Text("往期推薦")
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)

            if vm.recommended.isEmpty {
                EmptyStateView(text: "載入推薦…")
            } else if let movie = vm.recommended.first {
                NavigationLink {
                    MovieDetailView(movieID: movie.id)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        JavDBImage(url: movie.coverURL ?? movie.thumbURL)
                            .frame(width: 110, height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 8) {
                            Text(movie.displayNumber + "  " + movie.displayTitle)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(3)
                            if let score = movie.score, score > 0 {
                                HStack(spacing: 4) {
                                    ForEach(0..<5, id: \.self) { i in
                                        Image(systemName: i < Int(score.rounded()) ? "star.fill" : "star")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                    Text(String(format: "%.2f", score))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
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
                    .overlay(Color.black.opacity(0.35))
                Text("TOP250")
                    .font(.largeTitle.weight(.heavy))
                    .foregroundStyle(.white)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
