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
