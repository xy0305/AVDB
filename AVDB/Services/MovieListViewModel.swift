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

    private var currentPage = 1
    private let fetchPage: (Int) async throws -> [Movie]

    init(fetchPage: @escaping (Int) async throws -> [Movie]) {
        self.fetchPage = fetchPage
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
            let result = try await fetchPage(currentPage)
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
