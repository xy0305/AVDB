//
//  SearchView.swift
//  AVDB
//
//  系统搜索栏：番号 / 关键词。
//

import SwiftUI

struct SearchView: View {
    @State private var keyword = ""
    @State private var submitted = ""

    var body: some View {
        Group {
            if submitted.isEmpty {
                ContentUnavailableView("搜索", systemImage: "magnifyingglass", description: Text("输入番号或关键词"))
            } else {
                SearchResultView(keyword: submitted)
            }
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $keyword, prompt: "番号 / 关键词")
        .onSubmit(of: .search) { submit() }
    }

    private func submit() {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        submitted = trimmed
    }
}

struct SearchResultView: View {
    let keyword: String
    @StateObject private var vm: MovieListViewModel

    init(keyword: String) {
        self.keyword = keyword
        _vm = StateObject(wrappedValue: MovieListViewModel { page in
            try await JavDBSDK.shared.search(keyword: keyword, page: page)
        })
    }

    var body: some View {
        ScrollView {
            MoviePosterGrid(movies: vm.movies, onAppearLast: { movie in
                vm.loadMoreIfNeeded(current: movie)
            })
            if vm.isLoading { ProgressView().padding() }
        }
        .task { if vm.movies.isEmpty { await vm.loadMore() } }
        .refreshable { await vm.refresh() }
    }
}
