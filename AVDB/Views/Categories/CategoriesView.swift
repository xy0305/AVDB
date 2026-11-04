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
    @State private var showSearch = false
    /// Build 307: 篩選 entry is the top-left toolbar button; the panel drops from
    /// the top under the category tabs. Default stowed (panel hidden).
    @AppStorage("categories.filterPanel.expanded.v2") private var filterExpanded = false
    @Environment(\.availableLayoutSize) private var layoutSize

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("類別")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AdaptiveLayout.horizontalPadding)
                    .padding(.vertical, 8)
                UnderlineTabBar(
                    tabs: MovieCatalogType.categoryTabs.map { ($0, $0.title) },
                    selection: $catalog,
                    scrolls: false
                )
                .padding(.top, 4)

                // Build 307: the filter panel hangs from the top, directly under
                // the category tabs, in normal layout flow — the floating tab bar
                // at the bottom can never cover it (the 302–306 bottom placements
                // kept losing that fight). Entry point: top-left toolbar button.
                if filterExpanded {
                    CategoryInlineFilterPanel(
                        vm: vm,
                        expanded: $filterExpanded,
                        maxHeight: max(260, min(480, layoutSize.height * 0.52))
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

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
            }
            .background {
                LiquidGlassBackground()
            }
            .frame(maxWidth: AdaptiveLayout.contentMaxWidth)
            .frame(maxWidth: .infinity)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Build 307: filter entry lives in the top-left corner, always
                // visible; the dot marks active (non-default) filter picks.
                ToolbarItem(placement: .topBarLeading) {
                    Button { toggleFilter() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            Text("篩選")
                            if !vm.activeFilterSummary.isEmpty {
                                Circle().fill(Color.accentColor).frame(width: 7, height: 7)
                            }
                            Image(systemName: filterExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2.weight(.semibold))
                        }
                    }
                    .accessibilityIdentifier("category-filter-toolbar-toggle")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSearch = true } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
            .navigationDestination(isPresented: $showSearch) { SearchView() }
            .task { await vm.load(type: catalog) }
            .onChange(of: catalog) { _, new in
                Task { await vm.load(type: new) }
            }
            .refreshable { await vm.load(type: catalog, force: true) }
        }
    }

    private func toggleFilter() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { filterExpanded.toggle() }
        if filterExpanded, vm.groups.isEmpty, !vm.isLoading { Task { await vm.reloadGroups() } }
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

    /// Active non-default picks, e.g. 「可下載 · 2025 · 3月」.
    var activeFilterSummary: String {
        groups.compactMap { group -> String? in
            let current = selectedID(in: group)
            guard !current.isEmpty, current != "all", !(group.categoryID == "main" && current == "m") else { return nil }
            return group.tags?.first { $0.id == current }?.name
        }.joined(separator: " · ")
    }

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
        if !force, type == catalog, (isLoading || !movies.isEmpty) { return }
        let changed = type != catalog
        catalog = type
        if changed {
            movies = []
            groups = []
            selected.removeAll()
        }
        await fetch(replacing: true, reloadGroups: true)
    }

    func applyFilter() async {
        await fetch(replacing: true)
    }

    /// Build 301: retry the official tag groups if the first load failed.
    func reloadGroups() async {
        await fetch(replacing: true, reloadGroups: true)
    }

    func selectSort(_ sort: CatalogSort) async {
        guard self.sort != sort else { return }
        self.sort = sort
        await fetch(replacing: true)
    }

    func loadMore() async {
        guard hasMore, !isLoading else { return }
        await fetch(replacing: false)
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

    private var requestID = UUID()

    private func fetch(replacing: Bool, reloadGroups: Bool = false) async {
        let id = UUID()
        requestID = id
        let type = catalog
        let nextPage = replacing ? 1 : page + 1
        let requestedSort = sort
        isLoading = true
        defer { if requestID == id { isLoading = false } }
        do {
            if reloadGroups {
                let refreshedGroups = try await sdk.tagGroups(type: type.rawValue)
                guard requestID == id, !Task.isCancelled else { return }
                groups = refreshedGroups
            }
            let requestedFilter = filterBy
            let list = try await sdk.moviesByTag(
                filterBy: requestedFilter,
                type: nil,
                page: nextPage,
                limit: 24,
                sortBy: requestedSort.sortBy,
                orderBy: requestedSort.orderBy
            )
            guard requestID == id, !Task.isCancelled else { return }
            page = nextPage
            hasMore = !list.isEmpty
            if replacing {
                movies = list
            } else {
                let ids = Set(movies.map(\.id))
                movies.append(contentsOf: list.filter { !ids.contains($0.id) })
            }
            // Build 303: warm first ~2 screens of HQ covers at cell size.
            let warm = movies
            Task(priority: .utility) { await HomeHQPosterPrefetch.prefetch(warm) }
        } catch {
            // Keep successful content and pagination; failed requests are retryable.
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
                    GlassHaptic.tap()
                    vm.pick(groupID: cid, tagID: id == "all" ? nil : id)
                }
            }
        }
        .padding(12)
        .glassSurface(
            in: RoundedRectangle(cornerRadius: 14, style: .continuous),
            elevation: 0.35
        )
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
        .nestedMovieListChrome()
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
    @State private var account = APIClient.shared.token
    @StateObject private var vm: CatalogListViewModel

    private var query: CatalogQuery {
        CatalogQuery(source: String(describing: source), type: catalog.rawValue,
                     filter: filter.rawValue, sort: sort.sortBy,
                     account: account, backend: JavDBConstants.baseURL)
    }

    private let listSorts: [CatalogSort] = [.updateDesc, .releaseDesc]

    init(title: String, type: MovieCatalogType = .all, source: CatalogSource) {
        self.title = title
        self.source = source
        _catalog = State(initialValue: type == .censored ? .all : type)
        _filter = State(initialValue: source == .magnets ? .magnets : .all)
        _vm = StateObject(wrappedValue: CatalogListViewModel(fetch: { query, page in
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--catalog-navigation-fixture") {
                return page == 1 ? (1...60).map {
                    Movie(id: "catalog-\($0)", number: "TEST-\($0)", title: "Neutral film \($0)", coverURL: "fixture://poster/\($0)")
                } : []
            }
            #endif
            switch query.source {
            case "rankings":
                return try await JavDBSDK.shared.rankings(type: query.type, period: "daily", page: page)
            default:
                return try await JavDBSDK.shared.latestMovies(page: page, limit: 21, type: query.type,
                    filterBy: query.filter.isEmpty ? nil : query.filter, sortBy: query.sort)
            }
        }, scopeIsCurrent: { query in
            query.account == APIClient.shared.token && query.backend == JavDBConstants.baseURL
        }))
    }

    var body: some View {
        VStack(spacing: 0) {
            UnderlineTabBar(
                tabs: MovieCatalogType.allCases.map { ($0, $0.title) },
                selection: $catalog,
                scrolls: false
            )
            .padding(.top, 4)

            filterSortBar

            ScrollView {
                MoviePosterGrid(movies: vm.movies, scrollTargets: true, onAppearLast: { movie in
                    vm.loadMoreIfNeeded(current: movie)
                })
                if vm.isLoading { ProgressView().padding().accessibilityIdentifier("catalog-loading") }
                if let error = vm.errorMessage {
                    VStack {
                        Text(error).font(.caption).accessibilityIdentifier("catalog-error")
                        Button("重試") { Task { await vm.retry() } }
                    }.padding()
                } else if vm.movies.isEmpty && !vm.isLoading {
                    Text("暫無符合條件的作品").padding()
                }
            }
            .scrollPosition(id: $vm.scrollID)
            .refreshable { await vm.refresh() }
            .overlay(alignment: .top) {
                if !vm.movies.isEmpty, let error = vm.errorMessage {
                    HStack {
                        Text(error).font(.caption).lineLimit(3)
                        Spacer(minLength: 8)
                        Button("重試") { Task { await vm.retry() } }
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(8)
                    .accessibilityIdentifier("catalog-error-notice")
                }
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--catalog-navigation-fixture") {
                Text("items=\(vm.movies.count) requests=\(vm.requestCount)")
                    .font(.caption).accessibilityIdentifier("catalog-diagnostics")
            }
            #endif
        }
        .background { LiquidGlassBackground() }
        .nestedMovieListChrome()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: query) { await vm.enter(query) }
        .onReceive(NotificationCenter.default.publisher(for: .avdbCatalogAccountChanged)) { _ in
            account = APIClient.shared.token
        }
    }

    private var filterSortBar: some View {
        HStack(spacing: 8) {
            CapsuleChipBar(
                tabs: LatestListFilter.allCases.map { ($0, $0.title) },
                selection: $filter
            )
            .padding(.horizontal, 0)
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
                .liquidGlass(interactive: false)
            }
            .padding(.trailing, 12)
        }
        .padding(.vertical, 2)
    }

}


// MARK: - Build 307 top filter panel

/// Filter panel hanging from the top of the categories page, directly under the
/// category tabs. Builds 302–306 hosted the filter at the bottom — first as a
/// VStack sibling, then via `.safeAreaInset(edge: .bottom)` — and the floating
/// tab bar kept covering it, so Build 307 moves the entry point to the top-left
/// toolbar button and drops the panel from the top in normal layout flow, where
/// nothing can cover it. Chips apply immediately (250ms coalesced); the sort
/// menu lives in the panel header; drag the bottom handle up to stow.
struct CategoryInlineFilterPanel: View {
    @ObservedObject var vm: CategoriesViewModel
    @Binding var expanded: Bool
    let maxHeight: CGFloat
    @State private var dragOffset: CGFloat = 0
    @State private var applyTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if vm.groups.isEmpty {
                        Text(vm.isLoading ? "載入篩選…" : "暫無可用篩選")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 20)
                    }
                    ForEach(vm.groups) { group in row(group) }
                }
                .padding(.horizontal, AdaptiveLayout.horizontalPadding)
                .padding(.bottom, 10)
            }
            .frame(maxHeight: maxHeight)
            // Grab handle on the panel's bottom edge: tap or drag up to stow.
            Capsule(style: .continuous)
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 38, height: 5)
                .padding(.top, 2).padding(.bottom, 7)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { toggle() }
                .accessibilityIdentifier("category-filter-handle")
        }
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 18, bottomTrailingRadius: 18, topTrailingRadius: 0, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 3)
        }
        .offset(y: min(0, dragOffset))
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in dragOffset = min(0, value.translation.height) }
                .onEnded { value in
                    let dy = value.translation.height
                    dragOffset = 0
                    if dy < -60 { setExpanded(false) }
                }
        )
        .accessibilityIdentifier("category-filter-panel")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { toggle() } label: {
                HStack(spacing: 6) {
                    Text("篩選").font(.headline).foregroundStyle(.primary)
                    if !summary.isEmpty {
                        Text(summary).font(.caption).foregroundStyle(.tint).lineLimit(1)
                    }
                    Image(systemName: "chevron.up")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("category-filter-toggle")
            Spacer(minLength: 8)
            Menu {
                ForEach(CatalogSort.allCases) { sort in
                    Button {
                        Task { await vm.selectSort(sort) }
                    } label: {
                        if vm.sort == sort { Label(sort.title, systemImage: "checkmark") } else { Text(sort.title) }
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
            .accessibilityIdentifier("category-filter-sort")
        }
        .padding(.horizontal, AdaptiveLayout.horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    /// Active non-default picks, e.g. 「可下載 · 2025 · 3月」.
    private var summary: String { vm.activeFilterSummary }

    private func row(_ group: TagGroup) -> some View {
        let cid = group.categoryID ?? group.id
        let current = vm.selectedID(in: group)
        let selected = current.isEmpty ? "all" : current
        return HStack(alignment: .top, spacing: 10) {
            Text(group.category ?? "")
                .font(.subheadline.weight(.semibold))
                .frame(width: 40, alignment: .leading)
                .padding(.top, 5)
            FlowLayout(spacing: 8) {
                ForEach([Tag.allChip] + (group.tags ?? [])) { tag in
                    let on = selected == tag.id
                    Button {
                        GlassHaptic.tap()
                        vm.pick(groupID: cid, tagID: tag.id == "all" ? nil : tag.id)
                        scheduleApply()
                    } label: {
                        // Static chips (no live glass) so a 40-chip panel scrolls smoothly.
                        Text(tag.name ?? tag.id)
                            .font(.subheadline.weight(on ? .semibold : .regular))
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(on ? Color.accentColor : Color(.tertiarySystemFill),
                                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Coalesce quick successive taps (e.g. 年份 then 月份) into one request.
    private func scheduleApply() {
        applyTask?.cancel()
        applyTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await vm.applyFilter()
        }
    }

    private func toggle() { setExpanded(!expanded) }
    private func setExpanded(_ value: Bool) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { expanded = value }
        if value, vm.groups.isEmpty, !vm.isLoading { Task { await vm.reloadGroups() } }
    }
}
