//
//  HomeView.swift
//  AVDB
//
//  首页：iOS 26 液态玻璃风格重构
//

import SwiftUI

struct HomeView: View {
    @StateObject private var vm = HomeViewModel()
    @State private var goSearch = false
    @State private var selectedSection: HomeSection? = nil
    
    enum HomeSection: Hashable {
        case rankings, hot, latest, magnets, articles, reviews
        case series, makers, directors, pastRecommend
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景渐变
                LinearGradient(
                    colors: [Color(.systemBackground), Color.blue.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 20) {
                        // 搜索栏
                        searchButton
                            .padding(.horizontal)
                            .padding(.top, 8)
                        
                        // 快捷入口网格
                        shortcutsGrid
                            .padding(.horizontal)
                        
                        // 佳片推荐卡片
                        if !vm.recommended.isEmpty {
                            recommendCard
                                .padding(.horizontal)
                        }
                        
                        // 最新上架
                        latestSection
                        
                        // TOP250 横幅
                        top250Banner
                            .padding(.horizontal)
                        
                        // 近期磁链
                        magnetSection
                        
                        // 我的关注
                        if !vm.following.isEmpty {
                            followingSection
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.blue.gradient)
                        Text("AVDB")
                            .font(.system(size: 20, weight: .bold))
                    }
                }
            }
            .task { await vm.initialLoad() }
            .refreshable { await vm.initialLoad() }
            .navigationDestination(isPresented: $goSearch) { SearchView() }
            .navigationDestination(item: $selectedSection) { section in
                destinationView(for: section)
            }
        }
    }
    
    // MARK: - 搜索按钮
    private var searchButton: some View {
        Button {
            goSearch = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                
                Text("搜索番號 / 關鍵詞")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.blue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 快捷入口网格
    private var shortcutsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            ShortcutCard(icon: "flame.fill", title: "熱播", color: .red) {
                selectedSection = .hot
            }
            ShortcutCard(icon: "sparkles", title: "最新", color: .blue) {
                selectedSection = .latest
            }
            ShortcutCard(icon: "link.circle.fill", title: "磁鏈", color: .green) {
                selectedSection = .magnets
            }
            ShortcutCard(icon: "crown.fill", title: "TOP250", color: .yellow) {
                selectedSection = .rankings
            }
            ShortcutCard(icon: "newspaper.fill", title: "資訊", color: .purple) {
                selectedSection = .articles
            }
            ShortcutCard(icon: "bubble.left.and.bubble.right.fill", title: "短評", color: .orange) {
                selectedSection = .reviews
            }
            ShortcutCard(icon: "square.stack.3d.up.fill", title: "系列", color: .teal) {
                selectedSection = .series
            }
            ShortcutCard(icon: "building.2.fill", title: "片商", color: .indigo) {
                selectedSection = .makers
            }
        }
    }
    
    // MARK: - 佳片推荐卡片
    private var recommendCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 头部
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.yellow.gradient)
                    Text("佳片推薦")
                        .font(.system(size: 18, weight: .bold))
                }
                
                GlassTag(text: vm.periodLabel, color: .blue, size: .small)
                
                Spacer()
                
                Button {
                    selectedSection = .pastRecommend
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
            .padding()
            
            Divider()
            
            // 推荐内容
            if let movie = vm.recommended.first {
                NavigationLink {
                    MovieDetailView(movieID: movie.id)
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        // 封面
                        ZStack(alignment: .topTrailing) {
                            JavDBImage(url: movie.coverURL ?? movie.thumbURL)
                                .aspectRatio(2/3, contentMode: .fill)
                                .frame(width: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            
                            if let score = movie.score, score > 0 {
                                Text(String(format: "%.1f", score))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.orange.gradient, in: Capsule())
                                    .padding(6)
                            }
                        }
                        
                        // 信息
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
                                RatingStars(rating: score / 2, size: 14, color: .orange)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                }
                .buttonStyle(.plain)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
    }
    
    // MARK: - 最新上架
    private var latestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.blue.gradient)
                    Text("最新上架")
                        .font(.system(size: 18, weight: .bold))
                }
                .padding(.leading)
                
                Spacer()
                
                Button {
                    selectedSection = .latest
                } label: {
                    HStack(spacing: 4) {
                        Text("查看全部")
                            .font(.system(size: 14, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.blue)
                }
                .padding(.trailing)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(vm.latest.prefix(12), id: \.id) { movie in
                        NavigationLink {
                            MovieDetailView(movieID: movie.id)
                        } label: {
                            MoviePosterCard(movie: movie)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            
            Button {
                Task { await vm.shuffleLatest() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                    Text("換一組")
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - TOP250横幅
    private var top250Banner: some View {
        Button {
            selectedSection = .rankings
        } label: {
            ZStack(alignment: .leading) {
                // 背景图
                if let coverURL = vm.latest.first?.coverURL {
                    JavDBImage(url: coverURL, contentMode: .fill)
                        .frame(height: 140)
                        .blur(radius: 40)
                }
                
                // 渐变遮罩
                LinearGradient(
                    colors: [.yellow.opacity(0.9), .orange.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 140)
                
                // 内容
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 24, weight: .bold))
                            Text("TOP 250")
                                .font(.system(size: 32, weight: .black))
                        }
                        .foregroundStyle(.white)
                        
                        Text("觀看評分最高影片")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                }
                .padding(20)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .orange.opacity(0.3), radius: 15, y: 8)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 近期磁链
    private var magnetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.green.gradient)
                    Text("近期磁鏈")
                        .font(.system(size: 18, weight: .bold))
                }
                .padding(.leading)
                
                Spacer()
                
                Button {
                    selectedSection = .magnets
                } label: {
                    HStack(spacing: 4) {
                        Text("查看全部")
                            .font(.system(size: 14, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.green)
                }
                .padding(.trailing)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(vm.magnets.prefix(12), id: \.id) { movie in
                        NavigationLink {
                            MovieDetailView(movieID: movie.id)
                        } label: {
                            MoviePosterCard(movie: movie)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            
            Button {
                Task { await vm.shuffleMagnets() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                    Text("換一組")
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - 我的关注
    private var followingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.pink.gradient)
                Text("我的關注")
                    .font(.system(size: 18, weight: .bold))
            }
            .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(vm.following.prefix(12), id: \.id) { movie in
                        NavigationLink {
                            MovieDetailView(movieID: movie.id)
                        } label: {
                            MoviePosterCard(movie: movie)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - 路由辅助
    @ViewBuilder
    private func destinationView(for section: HomeSection) -> some View {
        switch section {
        case .rankings:
            RankingsView(embedded: true, initialTab: .top250)
        case .hot:
            RankingsView(embedded: true, initialTab: .playback)
        case .latest:
            CatalogListView(title: "最新上架", type: .censored, source: .latest)
        case .magnets:
            CatalogListView(title: "近期磁鏈", type: .censored, source: .latest)
        case .articles:
            ArticlesView()
        case .reviews:
            HotReviewsView()
        case .series:
            SeriesView()
        case .makers:
            MakersView()
        case .directors:
            DirectorsView()
        case .pastRecommend:
            PastRecommendView()
        }
    }
}

// MARK: - 快捷卡片组件
struct ShortcutCard: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(color.gradient)
                }
                
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ViewModel (保持不变)
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
        async let latestTask = try? sdk.latestMovies(page: 1, limit: 24, type: "all", filterBy: "can_play", sortBy: "update")
        async let magTask = try? sdk.latestMovies(page: 2, limit: 24, type: "all", filterBy: "can_play", sortBy: "update")
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
        let next = (try? await sdk.latestMovies(page: latestPage, limit: 24, type: "all", filterBy: "can_play", sortBy: "update")) ?? []
        if next.isEmpty { latestPage = 1 }
        else { latest = next }
    }

    func shuffleMagnets() async {
        magnetPage += 1
        let next = (try? await sdk.latestMovies(page: magnetPage, limit: 24, type: "all", filterBy: "can_play", sortBy: "update")) ?? []
        let filtered = next.filter { ($0.magnetsCount ?? 0) > 0 }
        if filtered.isEmpty { magnetPage = 1 }
        else { magnets = filtered }
    }
}

// MARK: - 辅助视图(保留原有实现，后续单独重构)
struct ArticlesView: View {
    @State private var articles: [Article] = []
    @State private var loading = true

    var body: some View {
        ZStack {
            if loading && articles.isEmpty {
                EmptyStateView(text: "載入資訊")
            } else if articles.isEmpty {
                EmptyStateView(text: "暫無資訊")
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(articles, id: \.stableArticleID) { article in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(article.title ?? "")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.primary)
                                if let date = article.createdAt {
                                    Text(date)
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding()
                }
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
        ZStack {
            if loading && reviews.isEmpty {
                EmptyStateView(text: "載入短評")
            } else if reviews.isEmpty {
                EmptyStateView(text: "暫無短評")
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(reviews, id: \.stableReviewID) { review in
                            ReviewRow(review: review)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
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

struct PastRecommendView: View {
    @StateObject private var vm = PastRecommendViewModel()
    @State private var query = ""

    var body: some View {
        List {
            ForEach(vm.filtered(query), id: \.id) { period in
                NavigationLink {
                    PeriodMoviesView(period: period)
                } label: {
                    HStack(spacing: 8) {
                        Text(period.titleText)
                            .font(.system(size: 16, weight: .medium))
                        if !period.dateText.isEmpty {
                            Text("(\(period.dateText))")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "搜索推薦期數")
        .navigationTitle("往期推薦")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
    }
}

@MainActor
final class PastRecommendViewModel: ObservableObject {
    @Published var periods: [RecommendPeriod] = []
    func load() async {
        periods = (try? await JavDBSDK.shared.recommendPeriods()) ?? []
    }
    func filtered(_ q: String) -> [RecommendPeriod] {
        guard !q.isEmpty else { return periods }
        return periods.filter {
            $0.titleText.localizedCaseInsensitiveContains(q) ||
            $0.dateText.localizedCaseInsensitiveContains(q)
        }
    }
}

struct PeriodMoviesView: View {
    let period: RecommendPeriod
    @State private var movies: [Movie] = []
    @State private var loading = true

    var body: some View {
        Group {
            if loading && movies.isEmpty {
                EmptyStateView(text: "載入中")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(movies, id: \.id) { movie in
                            NavigationLink {
                                MovieDetailView(movieID: movie.id)
                            } label: {
                                MoviePosterCard(movie: movie)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(period.titleText)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loading = true
            movies = (try? await JavDBSDK.shared.recommendMovies(period: period.period)) ?? []
            loading = false
        }
    }
}
