//
//  CategoriesView.swift
//  AVDB
//
//  類別：有碼 / 無碼 / 歐美 / FC2 / 動漫 + 底部篩選。
//

import SwiftUI

struct CategoriesView: View {
    @State private var catalog: MovieCatalogType = .censored
    @StateObject private var vm = CategoriesViewModel()
    @State private var showFilter = false
    @State private var showSearch = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                UnderlineTabBar(
                    tabs: MovieCatalogType.allCases.map { ($0, $0.title) },
                    selection: $catalog
                )
                .padding(.top, 4)

                ScrollView {
                    if vm.isLoading && vm.movies.isEmpty {
                        EmptyStateView(text: "載入類別…")
                    } else {
                        MoviePosterGrid(movies: vm.movies, onAppearLast: { _ in
                            Task { await vm.loadMore() }
                        })
                        .padding(.top, 8)
                        if vm.isLoading { ProgressView().padding() }
                    }
                }

                filterBar
            }
            .background(Color(.systemBackground))
            .navigationTitle("類別")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button { } label: { Image(systemName: "eye") }
                        Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
                    }
                }
            }
            .navigationDestination(isPresented: $showSearch) { SearchView() }
            .sheet(isPresented: $showFilter) {
                CategoryFilterSheet(vm: vm)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .task { await vm.load(type: catalog) }
            .onChange(of: catalog) { _, new in
                Task { await vm.load(type: new) }
            }
            .refreshable { await vm.load(type: catalog, force: true) }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button { showFilter = true } label: {
                    Text("篩選")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                }
                Spacer()
                Button { showFilter = true } label: {
                    HStack(spacing: 4) {
                        Text(vm.sortLabel)
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .font(.system(size: 14))
                    .foregroundColor(JAVDBPalette.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
        }
    }
}

@MainActor
final class CategoriesViewModel: ObservableObject {
    @Published var movies: [Movie] = []
    @Published var isLoading = false
    @Published var groups: [TagGroup] = []
    @Published var selected: Set<String> = []
    @Published var sortBy: MovieSortBy = .release
    @Published var catalog: MovieCatalogType = .censored

    var sortLabel: String {
        switch sortBy {
        case .release: return "發布日期倒序"
        case .rating: return "評分"
        case .relevance: return "相關"
        case .date: return "日期"
        }
    }

    private var page = 1
    private var hasMore = true
    private let sdk = JavDBSDK.shared

    func load(type: MovieCatalogType, force: Bool = false) async {
        if !force, type == catalog, !movies.isEmpty { return }
        catalog = type
        page = 1
        hasMore = true
        movies = []
        selected.removeAll()
        async let tags = try? sdk.tagGroups(type: type.rawValue)
        groups = await tags ?? []
        await fetch()
    }

    func applyFilter() async {
        page = 1
        hasMore = true
        movies = []
        await fetch()
    }

    func loadMore() async {
        guard hasMore, !isLoading else { return }
        page += 1
        await fetch()
    }

    func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) }
        else { selected.insert(id) }
    }

    private func fetch() async {
        isLoading = true
        defer { isLoading = false }
        let list: [Movie]
        if selected.isEmpty {
            list = (try? await sdk.latestMovies(page: page, limit: 21, type: catalog.rawValue)) ?? []
        } else {
            let filter = selected.sorted().joined(separator: ",")
            list = (try? await sdk.moviesByTag(filterBy: filter, type: catalog.rawValue, page: page)) ?? []
        }
        if list.isEmpty {
            hasMore = false
        } else if page == 1 {
            movies = list
        } else {
            let ids = Set(movies.map(\.id))
            movies.append(contentsOf: list.filter { !ids.contains($0.id) })
        }
    }
}

struct CategoryFilterSheet: View {
    @ObservedObject var vm: CategoriesViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(vm.groups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.category ?? "")
                                .font(.system(size: 14, weight: .semibold))
                            FlowChips(tags: group.tags ?? [], selected: vm.selected) { id in
                                vm.toggle(id)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("篩選")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("重置") {
                        vm.selected.removeAll()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        Task {
                            await vm.applyFilter()
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

struct FlowChips: View {
    let tags: [Tag]
    let selected: Set<String>
    let toggle: (String) -> Void

    var body: some View {
        FlexibleChipWrap(tags: tags, selected: selected, toggle: toggle)
    }
}

/// 简易换行芯片（用 LazyVGrid 近似官方胶囊）
struct FlexibleChipWrap: View {
    let tags: [Tag]
    let selected: Set<String>
    let toggle: (String) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 72), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(tags) { tag in
                let on = selected.contains(tag.id)
                Button {
                    toggle(tag.id)
                } label: {
                    Text(tag.name ?? tag.id)
                        .font(.system(size: 13))
                        .foregroundColor(on ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(on ? JAVDBPalette.chipSelected : JAVDBPalette.chipGray)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 通用分类列表（首页「全部」跳转）
enum CatalogSource {
    case latest
    case rankings
}

struct CatalogListView: View {
    let title: String
    let type: MovieCatalogType
    let source: CatalogSource
    @StateObject private var vm: MovieListViewModel

    init(title: String, type: MovieCatalogType, source: CatalogSource) {
        self.title = title
        self.type = type
        self.source = source
        _vm = StateObject(wrappedValue: MovieListViewModel { page in
            switch source {
            case .latest:
                return try await JavDBSDK.shared.latestMovies(page: page, limit: 21, type: type.rawValue)
            case .rankings:
                return try await JavDBSDK.shared.rankings(type: type.rawValue, period: "daily", page: page)
            }
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
