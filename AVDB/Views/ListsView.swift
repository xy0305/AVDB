//
//  ListsView.swift
//  AVDB
//
//  片单列表页。
//

import SwiftUI

struct ListsView: View {
    @StateObject private var vm = ListsViewModel()

    var body: some View {
        NavigationStack {
            List {
                ForEach(vm.lists) { list in
                    NavigationLink {
                        ListDetailView(listID: list.id ?? "", title: list.name ?? list.title ?? "片单")
                    } label: {
                        HStack(spacing: 12) {
                            JavDBImage(url: list.coverURL)
                                .frame(width: 50, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(list.name ?? list.title ?? "片单")
                                    .font(.subheadline)
                                if let count = list.movieCount {
                                    Text("\(count) 部影片")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
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

    func load() async {
        isLoading = true
        defer { isLoading = false }
        if let l = try? await JavDBSDK.shared.lists(page: page) {
            if l.isEmpty { return }
            lists.append(contentsOf: l)
            page += 1
        }
    }

    func refresh() async {
        page = 1
        lists = []
        await load()
    }
}

/// 片单详情
struct ListDetailView: View {
    let listID: String
    let title: String
    @StateObject private var vm: MovieListViewModel

    init(listID: String, title: String) {
        self.listID = listID
        self.title = title
        _vm = StateObject(wrappedValue: MovieListViewModel { _ in
            try await JavDBSDK.shared.listDetail(listID)
        })
    }

    var body: some View {
        MovieGridView(title: title, viewModel: vm)
    }
}
