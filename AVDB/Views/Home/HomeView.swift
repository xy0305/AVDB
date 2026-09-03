//
//  HomeView.swift
//  AVDB
//
//  首页：快捷入口、佳片推荐、最新上架、TOP250、近期磁链、我的关注。
//

import SwiftUI

struct HomeView: View {
    @StateObject private var vm = HomeViewModel()
    @State private var goRankings = false
    @State private var goHot = false
    @State private var goLatest = false
    @State private var goMagnets = false
    @State private var goArticles = false
    @State private var goReviews = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    shortcutRow
                    recommendSection
                    if let ad = vm.bannerAd {
                        adBanner(ad)
                    }
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
        }
    }

    private var shortcutRow: some View {
        HStack(spacing: 0) {
            shortcut("看熱播", "play.rectangle.fill", Color.blue) { goHot = true }
            shortcut("AV資訊", "newspaper.fill", Color.red) { goArticles = true }
            shortcut("看短評", "text.bubble.fill", Color.orange) { goReviews = true }
            shortcut("找磁鏈", "link", Color.green) { goMagnets = true }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private func shortcut(_ title: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(color)
                }
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var recommendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("佳片推薦")
                    .font(.system(size: 17, weight: .semibold))
                Text(vm.periodLabel)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
                Spacer()
                Button {
                    Task { await vm.shuffleRecommend() }
                } label: {
                    HStack(spacing: 2) {
                        Text("往期推薦")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                    }
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
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
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 8) {
                            Text(movie.displayNumber + "  " + movie.displayTitle)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(3)
                            if let score = movie.score, score > 0 {
                                HStack(spacing: 4) {
                                    ForEach(0..<5, id: \.self) { i in
                                        Image(systemName: i < Int(score.rounded()) ? "star.fill" : "star")
                                            .font(.system(size: 11))
                                            .foregroundColor(.orange)
                                    }
                                    Text(String(format: "%.2f", score))
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
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

    private func adBanner(_ ad: AdItem) -> some View {
        Group {
            if let url = ad.url, let link = URL(string: url) {
                Link(destination: link) {
                    JavDBImage(url: ad.imageURL, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(height: 70)
                        .clipped()
                }
            } else {
                JavDBImage(url: ad.imageURL, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: 70)
                    .clipped()
            }
        }
        .padding(.horizontal, 12)
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
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
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
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(red: 0.95, green: 0.35, blue: 0.75))
                    .shadow(radius: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
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
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
    }

    private var followingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("我的關注")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Text("更新時間倒序")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
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
    @Published var bannerAd: AdItem?
    @Published var periodLabel = "週一/四更新"
    @Published var periods: [RecommendPeriod] = []
    private var periodIndex = 0
    private var latestPage = 1
    private var magnetPage = 2
    private let sdk = JavDBSDK.shared

    func initialLoad() async {
        async let rec = try? sdk.recommendMovies(page: 1)
        async let latestTask = try? sdk.latestMovies(page: 1, limit: 9, type: "0")
        async let magTask = try? sdk.latestMovies(page: 2, limit: 9, type: "0")
        async let periodsTask = try? sdk.recommendPeriods()
        async let adsTask = try? sdk.adsPayload()
        async let followTask = try? sdk.recentViewed()

        recommended = await rec ?? []
        latest = await latestTask ?? []
        magnets = (await magTask ?? []).filter { ($0.magnetsCount ?? 0) > 0 }
        if magnets.isEmpty { magnets = latest }
        periods = await periodsTask ?? []
        if let ads = await adsTask, let first = ads.ads?["web_magnets_top"]?.first {
            bannerAd = first
        }
        following = await followTask ?? []
        if let created = periods.first?.createdAt, created.count >= 10 {
            periodLabel = String(created.prefix(10))
        }
    }

    func shuffleRecommend() async {
        guard !periods.isEmpty else {
            recommended = (try? await sdk.recommendMovies(page: 1)) ?? recommended
            return
        }
        periodIndex = (periodIndex + 1) % periods.count
        if let p = periods[periodIndex].period {
            recommended = (try? await sdk.recommendMovies(page: 1, period: p)) ?? recommended
            if let created = periods[periodIndex].createdAt {
                periodLabel = String(created.prefix(10))
            }
        }
    }

    func shuffleLatest() async {
        latestPage += 1
        let next = (try? await sdk.latestMovies(page: latestPage, limit: 9, type: "0")) ?? []
        if next.isEmpty { latestPage = 1 }
        else { latest = next }
    }

    func shuffleMagnets() async {
        magnetPage += 1
        let next = (try? await sdk.latestMovies(page: magnetPage, limit: 9, type: "0")) ?? []
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
