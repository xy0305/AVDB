//
//  ListsView.swift
//  AVDB
//
//  片单列表 / 片单作品（/api/v1/lists/{id}/movies 分页）。
//

import SwiftUI

struct ListsView: View {
    @StateObject private var vm = ListsViewModel()

    var body: some View {
        NavigationStack {
            List {
                ForEach(vm.lists) { list in
                    NavigationLink {
                        ListDetailView(listID: list.id, title: list.displayName)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(list.displayName)
                                .font(.subheadline)
                            HStack(spacing: 8) {
                                if let count = list.movieCount {
                                    Text("\(count) 部影片")
                                }
                                if let c = list.collectionsCount {
                                    Text("\(c) 收藏")
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                    .onAppear {
                        if list.id == vm.lists.last?.id {
                            Task { await vm.load() }
                        }
                    }
                }
                if vm.isLoading {
                    ProgressView()
                }
            }
            .navigationTitle("片单")
            .task {
                if vm.lists.isEmpty { await vm.load() }
            }
            .refreshable { await vm.refresh() }
        }
    }
}

@MainActor
final class ListsViewModel: ObservableObject {
    @Published var lists: [MovieList] = []
    @Published var isLoading = false
    private var page = 1
    private var hasMore = true

    func load() async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let next = (try? await JavDBSDK.shared.lists(page: page)) ?? []
        if next.isEmpty {
            hasMore = false
            return
        }
        let ids = Set(lists.map(\.id))
        lists.append(contentsOf: next.filter { !ids.contains($0.id) })
        page += 1
    }

    func refresh() async {
        page = 1
        hasMore = true
        lists = []
        await load()
    }
}

/// 片单作品列表
struct ListDetailView: View {
    let listID: String
    let title: String
    @StateObject private var vm: MovieListViewModel

    init(listID: String, title: String) {
        self.listID = listID
        self.title = title
        _vm = StateObject(wrappedValue: MovieListViewModel { page in
            try await JavDBSDK.shared.listMovies(listID, page: page, limit: 21)
        })
    }

    var body: some View {
        ScrollView {
            MoviePosterGrid(movies: vm.movies, onAppearLast: { movie in
                vm.loadMoreIfNeeded(current: movie)
            })
            if vm.isLoading { ProgressView().padding() }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { if vm.movies.isEmpty { await vm.loadMore() } }
        .refreshable { await vm.refresh() }
    }
}

/// 系列作品列表
struct SeriesMoviesView: View {
    let seriesID: String
    let title: String
    @StateObject private var vm: MovieListViewModel

    init(seriesID: String, title: String) {
        self.seriesID = seriesID
        self.title = title
        _vm = StateObject(wrappedValue: MovieListViewModel { page in
            try await JavDBSDK.shared.seriesMovies(seriesID, page: page, limit: 21)
        })
    }

    var body: some View {
        ScrollView {
            MoviePosterGrid(movies: vm.movies, onAppearLast: { movie in
                vm.loadMoreIfNeeded(current: movie)
            })
            if vm.isLoading { ProgressView().padding() }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { if vm.movies.isEmpty { await vm.loadMore() } }
        .refreshable { await vm.refresh() }
    }
}

/// 片商作品列表
struct MakerMoviesView: View {
    let makerID: String
    let title: String
    @StateObject private var vm: MovieListViewModel

    init(makerID: String, title: String) {
        self.makerID = makerID
        self.title = title
        _vm = StateObject(wrappedValue: MovieListViewModel { page in
            try await JavDBSDK.shared.makerMovies(makerID, page: page, limit: 21)
        })
    }

    var body: some View {
        ScrollView {
            MoviePosterGrid(movies: vm.movies, onAppearLast: { movie in
                vm.loadMoreIfNeeded(current: movie)
            })
            if vm.isLoading { ProgressView().padding() }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { if vm.movies.isEmpty { await vm.loadMore() } }
        .refreshable { await vm.refresh() }
    }
}

/// 导演作品列表
struct DirectorMoviesView: View {
    let directorID: String
    let title: String
    @StateObject private var vm: MovieListViewModel

    init(directorID: String, title: String) {
        self.directorID = directorID
        self.title = title
        _vm = StateObject(wrappedValue: MovieListViewModel { page in
            try await JavDBSDK.shared.directorMovies(directorID, page: page, limit: 21)
        })
    }

    var body: some View {
        ScrollView {
            MoviePosterGrid(movies: vm.movies, onAppearLast: { movie in
                vm.loadMoreIfNeeded(current: movie)
            })
            if vm.isLoading { ProgressView().padding() }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { if vm.movies.isEmpty { await vm.loadMore() } }
        .refreshable { await vm.refresh() }
    }
}

/// 通用「名称列表」：系列 / 片商 / 导演 的首页入口，复用 Actor 模型（id/name/videos_count）。
struct NamedListView: View {
    let kind: NamedListKind
    @State private var seriesItems: [Series] = []
    @State private var actorItems: [Actor] = []
    @State private var loading = false

    enum NamedListKind {
        case series, makers, directors

        var title: String {
            switch self {
            case .series: return "系列"
            case .makers: return "片商"
            case .directors: return "导演"
            }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                switch kind {
                case .series:
                    ForEach(seriesItems) { item in
                        row(name: item.displayName, count: item.videosCount) {
                            SeriesMoviesView(seriesID: item.id, title: item.displayName)
                        }
                    }
                case .makers:
                    ForEach(actorItems) { item in
                        row(name: item.displayName, count: item.videosCount) {
                            MakerMoviesView(makerID: item.id, title: item.displayName)
                        }
                    }
                case .directors:
                    ForEach(actorItems) { item in
                        row(name: item.displayName, count: item.videosCount) {
                            DirectorMoviesView(directorID: item.id, title: item.displayName)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            if loading { ProgressView().padding() }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load(force: true) }
    }

    private func row<D: View>(name: String, count: Int?, @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    if let c = count {
                        Text("\(c) 部")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func load(force: Bool = false) async {
        if force {
            seriesItems = []
            actorItems = []
        }
        let empty = kind == .series ? seriesItems.isEmpty : actorItems.isEmpty
        guard empty, !loading else { return }
        loading = true
        defer { loading = false }
        switch kind {
        case .series:
            seriesItems = (try? await JavDBSDK.shared.series(type: "0")) ?? []
        case .makers:
            actorItems = (try? await JavDBSDK.shared.makers()) ?? []
        case .directors:
            actorItems = (try? await JavDBSDK.shared.directors()) ?? []
        }
    }
}
