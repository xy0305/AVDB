//
//  CategoriesView.swift
//  AVDB
//
//  類別：有碼 / 無碼 / 歐美 / FC2 / 動漫 + 官方 movies/tags 篩選排序。
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
                    tabs: MovieCatalogType.categoryTabs.map { ($0, $0.title) },
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
            .background {
                LiquidGlassBackground()
            }
            .frame(maxWidth: .infinity)
            .navigationTitle("類別")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSearch = true } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
            .navigationDestination(isPresented: $showSearch) { SearchView() }
            .sheet(isPresented: $showFilter) {
                CategoryFilterSheet(vm: vm)
                    .presentationDetents([.large])
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
            HStack {
                Button { showFilter = true } label: {
                    Text("篩選")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                Spacer()
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
                    HStack(spacing: 4) {
                        Text(vm.sort.title)
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, AdaptiveLayout.horizontalPadding)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .frame(maxWidth: .infinity)
    }
}

enum CatalogSort: String, CaseIterable, Identifiable {
    case updateDesc
    case releaseDesc
    case releaseAsc
    case score
    case hit
    case wantWatch
    case watched

    var id: String { rawValue }

    var title: String {
        switch self {
        case .updateDesc: return "更新時間倒序"
        case .releaseDesc: return "發布日期倒序"
        case .releaseAsc: return "發布日期正序"
        case .score: return "評分倒序"
        case .hit: return "熱度倒序"
        case .wantWatch: return "想看人數倒序"
        case .watched: return "看過人數倒序"
        }
    }

    var sortBy: String {
        switch self {
        case .updateDesc: return "update"
        case .releaseDesc, .releaseAsc: return "release"
        case .score: return "score"
        case .hit: return "hit"
        case .wantWatch: return "want_watch_count"
        case .watched: return "watched_count"
        }
    }

    var orderBy: String {
        self == .releaseAsc ? "asc" : "desc"
    }

    /// 清单专用排序选项（存入时间倒序、创建时间倒序、评分倒序）
    static var listSortOptions: [CatalogSort] {
        [.updateDesc, .releaseDesc, .score]
    }
}

@MainActor
final class CategoriesViewModel: ObservableObject {
    @Published var movies: [Movie] = []
    @Published var isLoading = false
    @Published var groups: [TagGroup] = []
    @Published var selected: [String: String] = [:]
    @Published var sort: CatalogSort = .updateDesc
    @Published var catalog: MovieCatalogType = .censored

    var sortLabel: String { sort.title }

    private var page = 1
    private var hasMore = true
    private let sdk = JavDBSDK.shared

    /// 官方抓包 7 段：`{type}:t:{main}:{tags}:{year}:{month}:`
    /// README 没有槽位说明。主题/角色/服装/体型/行为/玩法/类别/时长全部进第 4 段，逗号拼接。
    /// 例：欧美巨乳 `2:t:m:13:::` ；有码巨乳 `0:t:m:17:::` ；年份 `0:t:m::2024::`
    private var filterBy: String {
        let main: String
        if let picked = selected["main"] {
            main = picked == "all" ? "" : picked
        } else {
            main = "m"
        }
        func slot(_ key: String) -> String {
            let v = selected[key] ?? ""
            return (v.isEmpty || v == "all") ? "" : v
        }
        let year = slot("year")
        let month = slot("month")
        let extras = groups
            .compactMap { group -> String? in
                guard let cid = group.categoryID,
                      !["main", "year", "month"].contains(cid) else { return nil }
                return selected[cid]
            }
            .filter { !$0.isEmpty && $0 != "all" }
        let tagSlot = extras.joined(separator: ",")
        return "\(catalog.rawValue):t:\(main):\(tagSlot):\(year):\(month):"
    }

    func load(type: MovieCatalogType, force: Bool = false) async {
        if !force, type == catalog, !movies.isEmpty { return }
        catalog = type
        page = 1
        hasMore = true
        movies = []
        selected.removeAll()
        groups = (try? await sdk.tagGroups(type: type.rawValue)) ?? []
        await fetch()
    }

    func applyFilter() async {
        page = 1
        hasMore = true
        movies = []
        await fetch()
    }

    func selectSort(_ sort: CatalogSort) async {
        guard self.sort != sort else { return }
        self.sort = sort
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

    func pick(groupID: String, tagID: String?) {
        if let tagID, !tagID.isEmpty {
            selected[groupID] = tagID
        } else {
            selected.removeValue(forKey: groupID)
        }
    }

    func selectedID(in group: TagGroup) -> String {
        guard let cid = group.categoryID else { return "" }
        if let v = selected[cid] { return v }
        if cid == "main" { return "m" }
        return ""
    }

    private func fetch() async {
        isLoading = true
        defer { isLoading = false }
        let list = (try? await sdk.moviesByTag(
            filterBy: filterBy,
            type: nil,
            page: page,
            limit: 24,
            sortBy: sort.sortBy,
            orderBy: sort.orderBy
        )) ?? []
        if list.isEmpty {
            hasMore = false
            if page == 1 { movies = [] }
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
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(vm.groups) { group in
                        filterRow(group)
                    }
                }
                .padding(16)
            }
            .background {
                LiquidGlassBackground()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack {
                        Text("篩選").font(.headline)
                        Spacer()
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
                            HStack(spacing: 4) {
                                Text(vm.sort.title)
                                Image(systemName: "arrow.up.arrow.down")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.tint)
                        }
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

    private func filterRow(_ group: TagGroup) -> some View {
        let cid = group.categoryID ?? group.id
        let current = vm.selectedID(in: group)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Text(group.category ?? "")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 44, alignment: .leading)
                    .padding(.top, 6)
                FlexibleChipWrap(
                    tags: [Tag.allChip] + (group.tags ?? []),
                    selected: current.isEmpty ? "all" : current
                ) { id in
                    vm.pick(groupID: cid, tagID: id == "all" ? nil : id)
                }
            }
        }
    }
}

extension Tag {
    static let allChip = Tag(id: "all", name: "全部", coverURL: nil, count: nil)
}

struct FlexibleChipWrap: View {
    let tags: [Tag]
    let selected: String
    let toggle: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(tags) { tag in
                LiquidFilterChip(
                    title: tag.name ?? tag.id,
                    isSelected: selected == tag.id
                ) {
                    toggle(tag.id)
                }
            }
        }
    }
}

/// 按内容换行的芯片布局（对齐官方筛选弹层）。
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var positions: [CGPoint] = []
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return (CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight), positions)
    }
}

/// 详情标签跳转：官方 `filter_by={type}:t::{tagID}::`
struct TagMoviesView: View {
    let tag: Tag
    var catalogType: String = "0"
    @StateObject private var vm: MovieListViewModel

    init(tag: Tag, catalogType: String = "0") {
        self.tag = tag
        self.catalogType = catalogType
        let type = catalogType.isEmpty ? "0" : catalogType
        let filter = "\(type):t::\(tag.id)::"
        _vm = StateObject(wrappedValue: MovieListViewModel { page, sort in
            try await JavDBSDK.shared.moviesByTag(
                filterBy: filter,
                type: nil,
                page: page,
                limit: 24,
                sortBy: sort.sortBy,
                orderBy: sort.orderBy
            )
        })
    }

    var body: some View {
        ScrollView {
            MoviePosterGrid(movies: vm.movies, onAppearLast: { movie in
                vm.loadMoreIfNeeded(current: movie)
            })
            if vm.isLoading { ProgressView().padding() }
        }
        .navigationTitle(tag.name ?? tag.id)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { MovieSortToolbar(vm: vm) } }
        .task { if vm.movies.isEmpty { await vm.loadMore() } }
        .refreshable { await vm.refresh() }
    }
}

enum CatalogSource {
    case latest
    case magnets
    case rankings
}

/// 最新上架 / 近期磁鏈：官方 filter_by（latest 接口）
enum LatestListFilter: String, CaseIterable, Identifiable {
    case all = ""
    case magnets = "magnets"
    case playable = "can_play"
    case subtitle = "subtitle"

    var id: String { rawValue.isEmpty ? "all" : rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .magnets: return "含磁鏈"
        case .playable: return "可播放"
        case .subtitle: return "字幕"
        }
    }
}

struct CatalogListView: View {
    let title: String
    var source: CatalogSource = .latest
    @State private var catalog: MovieCatalogType = .all
    @State private var filter: LatestListFilter
    @State private var sort: CatalogSort = .updateDesc
    @StateObject private var vm = MovieListViewModel { _ in [] }

    private let listSorts: [CatalogSort] = [.updateDesc, .releaseDesc, .releaseAsc, .score]

    init(title: String, type: MovieCatalogType = .all, source: CatalogSource) {
        self.title = title
        self.source = source
        _catalog = State(initialValue: type == .censored ? .all : type)
        _filter = State(initialValue: source == .magnets ? .magnets : .all)
    }

    var body: some View {
        VStack(spacing: 0) {
            UnderlineTabBar(
                tabs: MovieCatalogType.allCases.map { ($0, $0.title) },
                selection: $catalog
            )
            .padding(.top, 4)

            filterSortBar

            ScrollView {
                MoviePosterGrid(movies: vm.movies, onAppearLast: { movie in
                    vm.loadMoreIfNeeded(current: movie)
                })
                if vm.isLoading { ProgressView().padding() }
            }
        }
        .background { LiquidGlassBackground() }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .onChange(of: catalog) { _, _ in Task { await reload() } }
        .onChange(of: filter) { _, _ in Task { await reload() } }
        .onChange(of: sort) { _, _ in Task { await reload() } }
        .refreshable { await vm.refresh() }
    }

    private var filterSortBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LatestListFilter.allCases) { item in
                        let selected = filter == item
                        Button {
                            filter = item
                        } label: {
                            Text(item.title)
                                .font(.subheadline.weight(selected ? .semibold : .regular))
                                .foregroundStyle(selected ? Color.white : Color.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    selected ? Color.accentColor.opacity(0.85) : Color(.systemGray6),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Menu {
                ForEach(listSorts) { item in
                    Button {
                        sort = item
                    } label: {
                        if sort == item {
                            Label(item.title, systemImage: "checkmark")
                        } else {
                            Text(item.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(sort.title)
                    Image(systemName: "chevron.down")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(.systemGray6), in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @MainActor
    private func reload() async {
        let type = catalog.rawValue
        let filterBy = filter.rawValue.isEmpty ? nil : filter.rawValue
        let sortBy = sort.sortBy
        vm.replaceFetcher { page in
            switch source {
            case .rankings:
                return try await JavDBSDK.shared.rankings(type: type, period: "daily", page: page)
            case .latest, .magnets:
                return try await JavDBSDK.shared.latestMovies(
                    page: page,
                    limit: 21,
                    type: type,
                    filterBy: filterBy,
                    sortBy: sortBy
                )
            }
        }
        await vm.refresh()
    }
}
