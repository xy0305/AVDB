//
//  MovieListViewModel.swift
//  AVDB
//
//  通用的影片列表状态管理（支持分页加载）。
//

import Foundation
import SwiftUI

@MainActor
class MovieListViewModel: ObservableObject {
    @Published var movies: [Movie] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasMore = true
    @Published var sort: CatalogSort = .updateDesc

    private var currentPage = 1
    private var fetchPage: (Int) async throws -> [Movie]
    private var fetchSortedPage: ((Int, CatalogSort) async throws -> [Movie])?

    func replaceFetcher(_ fetchPage: @escaping (Int) async throws -> [Movie]) {
        self.fetchPage = fetchPage
        self.fetchSortedPage = nil
        currentPage = 1
        hasMore = true
    }

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
        isLoading = true
        defer { isLoading = false }
        do {
            let result: [Movie]
            if let fetchSortedPage {
                result = try await fetchSortedPage(1, sort)
            } else {
                result = try await fetchPage(1)
            }
            if result.isEmpty {
                hasMore = false
            } else {
                movies = result
                currentPage = 2
            }
        } catch {
            errorMessage = error.localizedDescription
        }
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
    var sortOptions: [CatalogSort]? = nil

    var body: some View {
        Menu {
            ForEach(sortOptions ?? CatalogSort.allCases) { sort in
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
                .foregroundStyle(.primary)
        }
        .accessibilityLabel("排序")
    }
}

// Route-local state for Home's latest/magnet catalog. No global response cache.
struct CatalogQuery: Equatable {
    let source: String
    let type: String
    let filter: String
    let sort: String
    let account: String?
    let backend: String
}

@MainActor
final class CatalogListViewModel: ObservableObject {
    typealias Fetch = (CatalogQuery, Int) async throws -> [Movie]
    @Published private(set) var movies: [Movie] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasMore = true
    @Published private(set) var requestCount = 0
    @Published var scrollID: String?
    private(set) var nextPage = 1
    private(set) var query: CatalogQuery?
    private var generation = 0
    private var attempted = false
    private var failedRequest: (page: Int, replacing: Bool)?
    private var work: Task<Void, Never>?
    private let fetch: Fetch
    private let scopeIsCurrent: (CatalogQuery) -> Bool

    init(fetch: @escaping Fetch, scopeIsCurrent: @escaping (CatalogQuery) -> Bool = { _ in true }) {
        self.fetch = fetch
        self.scopeIsCurrent = scopeIsCurrent
    }

    deinit { work?.cancel() }

    // The view task may be cancelled on a push. The route-owned request is not:
    // on return, await the same request, never reset/re-fetch page one.
    func enter(_ query: CatalogQuery) async {
        if self.query != query {
            generation += 1
            work?.cancel()
            work = nil
            self.query = query
            movies = []
            scrollID = nil
            nextPage = 1
            hasMore = true
            attempted = false
            isLoading = false
            errorMessage = nil
        }
        if !attempted {
            attempted = true
            start(page: 1, replacing: true)
        }
        await work?.value
    }

    func refresh() async {
        guard query != nil else { return }
        generation += 1
        work?.cancel()
        work = nil
        isLoading = false
        start(page: 1, replacing: true)
        await work?.value
    }

    func loadMoreIfNeeded(current movie: Movie) {
        guard movie.id == movies.last?.id, !isLoading, hasMore, errorMessage == nil else { return }
        start(page: nextPage, replacing: false)
    }

    func retry() async {
        guard !isLoading else { return }
        let request = failedRequest ?? (page: nextPage, replacing: nextPage == 1)
        start(page: request.page, replacing: request.replacing)
        await work?.value
    }

    private func start(page: Int, replacing: Bool) {
        guard let query, !isLoading else { return }
        let epoch = generation
        let fetch = self.fetch
        isLoading = true
        errorMessage = nil
        failedRequest = nil
        requestCount += 1
        work = Task { [weak self] in
            do {
                let result = try await fetch(query, page)
                guard let self, epoch == self.generation, self.scopeIsCurrent(query), !Task.isCancelled else { return }
                var ids = Set<String>()
                let unique = result.filter { ids.insert($0.id).inserted }
                var appended = unique.count
                if replacing {
                    self.movies = unique
                } else {
                    ids = Set(self.movies.map(\.id))
                    let newMovies = unique.filter { ids.insert($0.id).inserted }
                    appended = newMovies.count
                    self.movies.append(contentsOf: newMovies)
                }
                self.hasMore = !result.isEmpty && appended > 0
                self.nextPage = page + 1
                self.isLoading = false
                self.work = nil
            } catch {
                guard let self, epoch == self.generation, self.scopeIsCurrent(query) else { return }
                // Do not disguise cancellation, server/auth/decode failure as an empty page.
                self.failedRequest = (page, replacing)
                self.errorMessage = error is CancellationError ? "載入已中斷，請重試" : error.localizedDescription
                self.isLoading = false
                self.work = nil
            }
        }
    }
}
