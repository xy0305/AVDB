//
//  MovieListViewModel.swift
//  AVDB
//
//  通用的影片列表状态管理（支持分页加载）。
//

import Foundation
import SwiftUI

@MainActor
final class MovieListViewModel: ObservableObject {
    @Published var movies: [Movie] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasMore = true
    @Published var sort: CatalogSort = .updateDesc

    private var currentPage = 1
    private let fetchPage: (Int) async throws -> [Movie]
    private let fetchSortedPage: ((Int, CatalogSort) async throws -> [Movie])?

    init(fetchPage: @escaping (Int) async throws -> [Movie]) {
        self.fetchPage = fetchPage
        self.fetchSortedPage = nil
    }

    init(fetchPage: @escaping (Int, CatalogSort) async throws -> [Movie]) {
        self.fetchPage = { page in try await fetchPage(page, .updateDesc) }
        self.fetchSortedPage = fetchPage
    }

    func selectSort(_ sort: CatalogSort) async {
        guard self.sort != sort, fetchSortedPage != nil else { return }
        self.sort = sort
        currentPage = 1
        hasMore = true
        movies = []
        await loadMore()
    }

    func refresh() async {
        currentPage = 1
        hasMore = true
        movies = []
        await loadMore()
    }

    func loadMore() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result: [Movie]
            if let fetchSortedPage {
                result = try await fetchSortedPage(currentPage, sort)
            } else {
                result = try await fetchPage(currentPage)
            }
            if result.isEmpty {
                hasMore = false
            } else {
                movies.append(contentsOf: result)
                currentPage += 1
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 加载到触发载入更多
    func loadMoreIfNeeded(current movie: Movie) {
        guard let last = movies.last, last.id == movie.id else { return }
        Task { await loadMore() }
    }
}

struct MovieSortToolbar: View {
    @ObservedObject var vm: MovieListViewModel

    var body: some View {
        Menu {
            ForEach(CatalogSort.allCases) { sort in
                Button {
                    Task { await vm.selectSort(sort) }
                } label: {
                    if vm.sort == sort {
                        Label(sort.title, systemImage: "checkmark")
                    } else {
                        Text(sort.title)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("排序")
    }
}
