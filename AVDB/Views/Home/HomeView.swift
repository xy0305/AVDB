//
//  HomeView.swift
//  AVDB
//
//  首页：启动配置 + 推荐/最新/排行榜/热门标签。
//

import SwiftUI

struct HomeView: View {
    @StateObject private var vm = HomeViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 热门搜索词
                    if !vm.recentKeywords.isEmpty {
                        keywordSection
                    }

                    // 标签分类
                    if !vm.tags.isEmpty {
                        tagSection
                    }

                    // 推荐
                    movieSection(title: "推荐", movies: vm.recommended, fetch: vm.loadRecommended)

                    // 最新发布
                    movieSection(title: "最新发布", movies: vm.latest, fetch: vm.loadLatest)

                    // 排行榜
                    movieSection(title: "排行榜", movies: vm.top, fetch: vm.loadTop)
                }
                .padding(.vertical)
            }
            .navigationTitle("AVDB")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if vm.isLoading {
                        ProgressView()
                    }
                }
            }
            .task {
                await vm.initialLoad()
            }
            .refreshable {
                await vm.initialLoad()
            }
            .alert("加载失败", isPresented: .constant(vm.errorMessage != nil)) {
                Button("确定") { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }

    private var keywordSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("热门搜索")
                .font(.headline)
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.recentKeywords, id: \.self) { kw in
                        NavigationLink {
                            SearchResultView(keyword: kw)
                        } label: {
                            Text(kw)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(.systemGray6))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("分类")
                .font(.headline)
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(vm.tags.prefix(20)) { tag in
                        NavigationLink {
                            TagMoviesView(tag: tag)
                        } label: {
                            VStack(spacing: 4) {
                                JavDBImage(url: tag.coverURL)
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(tag.name ?? "")
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .frame(width: 60)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func movieSection(title: String, movies: [Movie], fetch: @escaping () async -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)

            if movies.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                        .task { await fetch() }
                    Spacer()
                }
                .frame(height: 180)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(movies) { movie in
                            NavigationLink {
                                MovieDetailView(movieID: movie.id)
                            } label: {
                                MovieCoverCard(movie: movie)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var recommended: [Movie] = []
    @Published var latest: [Movie] = []
    @Published var top: [Movie] = []
    @Published var tags: [Tag] = []
    @Published var recentKeywords: [String] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let sdk = JavDBSDK.shared

    func initialLoad() async {
        isLoading = true
        defer { isLoading = false }
        async let startup = try? sdk.startup()
        async let tags = try? sdk.movieTags()

        if let s = await startup {
            recentKeywords = s.recentKeywords ?? []
        }
        if let t = await tags {
            self.tags = t
        }

        await loadRecommended()
        await loadLatest()
        await loadTop()
    }

    func loadRecommended() async {
        if let m = try? await sdk.recommendMovies(page: 1) {
            recommended = m
        }
    }
    func loadLatest() async {
        if let m = try? await sdk.latestMovies(page: 1) {
            latest = m
        }
    }
    func loadTop() async {
        if let m = try? await sdk.topMovies(page: 1) {
            top = m
        }
    }
}

/// 标签影片列表
struct TagMoviesView: View {
    let tag: Tag
    @StateObject private var vm: MovieListViewModel

    init(tag: Tag) {
        self.tag = tag
        _vm = StateObject(wrappedValue: MovieListViewModel { page in
            try await JavDBSDK.shared.search(keyword: "", page: page)
        })
    }

    var body: some View {
        MovieGridView(title: tag.name ?? "标签", viewModel: vm)
    }
}
