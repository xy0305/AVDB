//
//  SearchView.swift
//  AVDB
//
//  搜索页：关键词搜索 + 以图搜图 + 磁力搜索 + 历史关键词。
//

import SwiftUI

struct SearchView: View {
    @State private var keyword = ""
    @State private var searchType: SearchType = .movie
    @State private var submitted = ""

    enum SearchType: String, CaseIterable {
        case movie = "影片"
        case magnet = "磁力"
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("类型", selection: $searchType) {
                ForEach(SearchType.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            HStack {
                TextField("搜索番号 / 关键词", text: $keyword)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit { submit() }

                Button {
                    submit()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
            }
            .padding(.horizontal)

            if !submitted.isEmpty {
                if searchType == .movie {
                    SearchResultView(keyword: submitted)
                } else {
                    MagnetResultView(keyword: submitted)
                }
            } else {
                SearchPlaceholderView()
            }
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        submitted = trimmed
    }
}

/// 搜索结果（影片）
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
        MovieGridView(title: "「\(keyword)」的搜索结果", viewModel: vm)
    }
}

/// 磁力搜索结果
struct MagnetResultView: View {
    let keyword: String
    @StateObject private var vm = MagnetSearchViewModel()

    var body: some View {
        VStack {
            List {
                ForEach(vm.magnets, id: \.stableID) { magnet in
                    MagnetRow(magnet: magnet)
                }
                if vm.isLoading {
                    ProgressView()
                }
            }
            .listStyle(.plain)
            .task {
                if vm.magnets.isEmpty {
                    await vm.search(keyword)
                }
            }
        }
        .navigationTitle("磁力搜索结果")
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
final class MagnetSearchViewModel: ObservableObject {
    @Published var magnets: [Magnet] = []
    @Published var isLoading = false

    func search(_ keyword: String) async {
        isLoading = true
        defer { isLoading = false }
        if let m = try? await JavDBSDK.shared.searchMagnet(keyword) {
            magnets = m
        }
    }
}

/// 搜索占位
struct SearchPlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            Text("输入番号或关键词开始搜索")
                .foregroundColor(.secondary)
        }
        .frame(maxHeight: .infinity)
    }
}
