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
        _vm = StateObject(wrappedValue: MovieListViewModel { page, sort in
            try await JavDBSDK.shared.moviesByTag(
                filterBy: "0:l:\(listID):", type: "0", page: page, limit: 21,
                sortBy: sort.sortBy, orderBy: sort.orderBy)
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
        .toolbar { ToolbarItem(placement: .topBarTrailing) { MovieSortToolbar(vm: vm) } }
        .task { if vm.movies.isEmpty { await vm.loadMore() } }
        .refreshable { await vm.refresh() }
    }
}

/// 系列作品列表（type: 0有码 1无码 2欧美）
struct SeriesMoviesView: View {
    let seriesID: String
    let title: String
    let type: String
    @StateObject private var vm: MovieListViewModel

    init(seriesID: String, title: String, type: String = "0") {
        self.seriesID = seriesID
        self.title = title
        self.type = type
        _vm = StateObject(wrappedValue: MovieListViewModel { page, sort in
            try await JavDBSDK.shared.moviesByTag(
                filterBy: "\(type):s:\(seriesID):", type: type, page: page, limit: 21,
                sortBy: sort.sortBy, orderBy: sort.orderBy)
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
        .toolbar { ToolbarItem(placement: .topBarTrailing) { MovieSortToolbar(vm: vm) } }
        .task { if vm.movies.isEmpty { await vm.loadMore() } }
        .refreshable { await vm.refresh() }
    }
}

/// 番号前缀作品列表（系列「番号」子分类，如 IPX → 搜索 q=IPX）
struct SeriesNumberMoviesView: View {
    let number: String
    let title: String
    @StateObject private var vm: MovieListViewModel

    init(number: String, title: String) {
        self.number = number
        self.title = title
        _vm = StateObject(wrappedValue: MovieListViewModel { page, sort in
            try await JavDBSDK.shared.moviesByTag(
                filterBy: "0:c:\(number):", type: "0", page: page, limit: 21,
                sortBy: sort.sortBy, orderBy: sort.orderBy)
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
        .toolbar { ToolbarItem(placement: .topBarTrailing) { MovieSortToolbar(vm: vm) } }
        .task { if vm.movies.isEmpty { await vm.loadMore() } }
        .refreshable { await vm.refresh() }
    }
}

/// 片商作品列表
struct MakerMoviesView: View {
    let makerID: String
    let title: String
    var type: String = "0"
    @StateObject private var vm: MovieListViewModel

    init(makerID: String, title: String, type: String = "0") {
        self.makerID = makerID
        self.title = title
        self.type = type
        _vm = StateObject(wrappedValue: MovieListViewModel { page, sort in
            try await JavDBSDK.shared.moviesByTag(
                filterBy: "\(type):m:\(makerID):", type: type, page: page, limit: 21,
                sortBy: sort.sortBy, orderBy: sort.orderBy)
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
        .toolbar { ToolbarItem(placement: .topBarTrailing) { MovieSortToolbar(vm: vm) } }
        .task { if vm.movies.isEmpty { await vm.loadMore() } }
        .refreshable { await vm.refresh() }
    }
}

/// 导演作品列表
struct DirectorMoviesView: View {
    let directorID: String
    let title: String
    var type: String = "0"
    @StateObject private var vm: MovieListViewModel

    init(directorID: String, title: String, type: String = "0") {
        self.directorID = directorID
        self.title = title
        self.type = type
        _vm = StateObject(wrappedValue: MovieListViewModel { page, sort in
            try await JavDBSDK.shared.moviesByTag(
                filterBy: "\(type):d:\(directorID):", type: type, page: page, limit: 21,
                sortBy: sort.sortBy, orderBy: sort.orderBy)
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
        .toolbar { ToolbarItem(placement: .topBarTrailing) { MovieSortToolbar(vm: vm) } }
        .task { if vm.movies.isEmpty { await vm.loadMore() } }
        .refreshable { await vm.refresh() }
    }
}

/// 系列子分类
enum SeriesTab: String, CaseIterable, Identifiable {
    case number
    case censored
    case uncensored
    case western

    var id: String { rawValue }

    var title: String {
        switch self {
        case .number: return "番号"
        case .censored: return "有码"
        case .uncensored: return "无码"
        case .western: return "欧美"
        }
    }

    /// series 接口 type 参数（番号不用）
    var type: String {
        switch self {
        case .number: return "0"
        case .censored: return "0"
        case .uncensored: return "1"
        case .western: return "2"
        }
    }
}

/// 系列模块：番号 / 有码 / 无码 / 欧美 四个子分类。
struct SeriesView: View {
    @State private var tab: SeriesTab = .number
    @State private var letters: [SeriesLetter] = []
    @State private var series: [Series] = []
    @State private var loading = false
    @State private var lettersPage = 1
    @State private var seriesPage = 1
    @State private var hasMore = true

    var body: some View {
        VStack(spacing: 0) {
            CapsuleChipBar(
                tabs: SeriesTab.allCases.map { ($0, $0.title) },
                selection: $tab
            )

            ScrollView {
                LazyVStack(spacing: 0) {
                    if tab == .number {
                        ForEach(letters) { item in
                            row(title: item.displayName, subtitle: item.description, count: item.videosCount) {
                                SeriesNumberMoviesView(number: item.letter ?? item.id, title: item.displayName)
                            }
                            .onAppear {
                                if item.id == letters.last?.id {
                                    Task { await loadMore() }
                                }
                            }
                        }
                    } else {
                        ForEach(series) { item in
                            row(title: item.displayName, subtitle: nil, count: item.videosCount) {
                                SeriesMoviesView(seriesID: item.id, title: item.displayName, type: tab.type)
                            }
                            .onAppear {
                                if item.id == series.last?.id {
                                    Task { await loadMore() }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                if loading { ProgressView().padding() }
            }
        }
        .navigationTitle("系列")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load(force: true) }
        .onChange(of: tab) { _, new in
            Task { await load(tab: new, force: true) }
        }
    }

    private func row<D: View>(title: String, subtitle: String?, count: Int?, @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let c = count {
                        Text("\(c) 部")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func load(tab: SeriesTab? = nil, force: Bool = false) async {
        let current = tab ?? self.tab
        if force || current != self.tab {
            letters = []
            series = []
            lettersPage = 1
            seriesPage = 1
            hasMore = true
        }
        let isNumber = current == .number
        let empty = isNumber ? letters.isEmpty : series.isEmpty
        guard empty, !loading else { return }
        loading = true
        defer { loading = false }
        if isNumber {
            letters = (try? await JavDBSDK.shared.seriesLetters(page: 1, limit: 100)) ?? []
            lettersPage = 2
        } else {
            series = (try? await JavDBSDK.shared.series(type: current.type, page: 1, limit: 100)) ?? []
            seriesPage = 2
        }
        hasMore = !(isNumber ? letters.isEmpty : series.isEmpty)
    }

    private func loadMore() async {
        guard hasMore, !loading else { return }
        loading = true
        defer { loading = false }
        if tab == .number {
            let next = (try? await JavDBSDK.shared.seriesLetters(page: lettersPage, limit: 100)) ?? []
            if next.isEmpty {
                hasMore = false
            } else {
                let ids = Set(letters.map(\.id))
                letters.append(contentsOf: next.filter { !ids.contains($0.id) })
                lettersPage += 1
            }
        } else {
            let next = (try? await JavDBSDK.shared.series(type: tab.type, page: seriesPage, limit: 100)) ?? []
            if next.isEmpty {
                hasMore = false
            } else {
                let ids = Set(series.map(\.id))
                series.append(contentsOf: next.filter { !ids.contains($0.id) })
                seriesPage += 1
            }
        }
    }
}

/// 片商/导演 的分类 Tab（有码/无码/欧美/FC2）
enum NamedTypeTab: String, CaseIterable, Identifiable {
    case censored
    case uncensored
    case western
    case fc2

    var id: String { rawValue }

    var title: String {
        switch self {
        case .censored: return "有码"
        case .uncensored: return "无码"
        case .western: return "欧美"
        case .fc2: return "FC2"
        }
    }

    /// makers/directors 接口 type 参数
    var type: String {
        switch self {
        case .censored: return "0"
        case .uncensored: return "1"
        case .western: return "2"
        case .fc2: return "3"
        }
    }
}

/// 片商模块：有码 / 无码 / 欧美 / FC2 四个子分类（带分页）。
struct MakersView: View {
    @State private var tab: NamedTypeTab = .censored
    @State private var items: [Actor] = []
    @State private var loading = false
    @State private var page = 1
    @State private var hasMore = true

    var body: some View {
        VStack(spacing: 0) {
            CapsuleChipBar(
                tabs: NamedTypeTab.allCases.map { ($0, $0.title) },
                selection: $tab
            )
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        row(name: item.displayName, count: item.videosCount) {
                            MakerMoviesView(makerID: item.id, title: item.displayName, type: tab.type)
                        }
                        .onAppear {
                            if item.id == items.last?.id {
                                Task { await loadMore() }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                if loading { ProgressView().padding() }
            }
        }
        .navigationTitle("片商")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load(force: true) }
        .onChange(of: tab) { _, _ in
            Task { await load(force: true) }
        }
    }

    private func row<D: View>(name: String, count: Int?, @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    if let c = count {
                        Text("\(c) 部")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func load(force: Bool = false) async {
        if force {
            items = []
            page = 1
            hasMore = true
        }
        guard items.isEmpty, !loading else { return }
        loading = true
        defer { loading = false }
        items = (try? await JavDBSDK.shared.makers(type: tab.type, page: 1, limit: 100)) ?? []
        page = 2
        hasMore = !items.isEmpty
    }

    private func loadMore() async {
        guard hasMore, !loading else { return }
        loading = true
        defer { loading = false }
        let next = (try? await JavDBSDK.shared.makers(type: tab.type, page: page, limit: 100)) ?? []
        if next.isEmpty {
            hasMore = false
        } else {
            let ids = Set(items.map(\.id))
            items.append(contentsOf: next.filter { !ids.contains($0.id) })
            page += 1
        }
    }
}

/// 导演分类 Tab（有码 type=0 / 无码 type=2）。
enum DirectorTypeTab: String, CaseIterable, Identifiable {
    case censored
    case uncensored

    var id: String { rawValue }

    var title: String {
        switch self {
        case .censored: return "有码"
        case .uncensored: return "无码"
        }
    }

    var type: String {
        switch self {
        case .censored: return "0"
        case .uncensored: return "2"
        }
    }
}

/// 导演模块：有码 / 无码两个子分类（带分页）。
struct DirectorsView: View {
    @State private var tab: DirectorTypeTab = .censored
    @State private var items: [Actor] = []
    @State private var loading = false
    @State private var page = 1
    @State private var hasMore = true

    var body: some View {
        VStack(spacing: 0) {
            CapsuleChipBar(
                tabs: DirectorTypeTab.allCases.map { ($0, $0.title) },
                selection: $tab
            )
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        row(name: item.displayName, count: item.videosCount) {
                            DirectorMoviesView(directorID: item.id, title: item.displayName, type: tab.type)
                        }
                        .onAppear {
                            if item.id == items.last?.id {
                                Task { await loadMore() }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                if loading { ProgressView().padding() }
            }
        }
        .navigationTitle("导演")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load(force: true) }
        .onChange(of: tab) { _, _ in
            Task { await load(force: true) }
        }
    }

    private func row<D: View>(name: String, count: Int?, @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    if let c = count {
                        Text("\(c) 部")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func load(force: Bool = false) async {
        if force {
            items = []
            page = 1
            hasMore = true
        }
        guard items.isEmpty, !loading else { return }
        loading = true
        defer { loading = false }
        items = (try? await JavDBSDK.shared.directors(type: tab.type, page: 1, limit: 100)) ?? []
        page = 2
        hasMore = !items.isEmpty
    }

    private func loadMore() async {
        guard hasMore, !loading else { return }
        loading = true
        defer { loading = false }
        let next = (try? await JavDBSDK.shared.directors(type: tab.type, page: page, limit: 100)) ?? []
        if next.isEmpty {
            hasMore = false
        } else {
            let ids = Set(items.map(\.id))
            items.append(contentsOf: next.filter { !ids.contains($0.id) })
            page += 1
        }
    }
}

/// 通用「名称列表」：系列 / 片商 / 导演 的首页入口，复用 Actor 模型（id/name/videos_count）。
struct NamedListView: View {
    let kind: NamedListKind
    @State private var seriesItems: [Series] = []
    @State private var actorItems: [Actor] = []
    @State private var loading = false

    enum NamedListKind {
        case series, makers, directors

        var title: String {
            switch self {
            case .series: return "系列"
            case .makers: return "片商"
            case .directors: return "导演"
            }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                switch kind {
                case .series:
                    ForEach(seriesItems) { item in
                        row(name: item.displayName, count: item.videosCount) {
                            SeriesMoviesView(seriesID: item.id, title: item.displayName)
                        }
                    }
                case .makers:
                    ForEach(actorItems) { item in
                        row(name: item.displayName, count: item.videosCount) {
                            MakerMoviesView(makerID: item.id, title: item.displayName)
                        }
                    }
                case .directors:
                    ForEach(actorItems) { item in
                        row(name: item.displayName, count: item.videosCount) {
                            DirectorMoviesView(directorID: item.id, title: item.displayName)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            if loading { ProgressView().padding() }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load(force: true) }
    }

    private func row<D: View>(name: String, count: Int?, @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    if let c = count {
                        Text("\(c) 部")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func load(force: Bool = false) async {
        if force {
            seriesItems = []
            actorItems = []
        }
        let empty = kind == .series ? seriesItems.isEmpty : actorItems.isEmpty
        guard empty, !loading else { return }
        loading = true
        defer { loading = false }
        switch kind {
        case .series:
            seriesItems = (try? await JavDBSDK.shared.series(type: "0")) ?? []
        case .makers:
            actorItems = (try? await JavDBSDK.shared.makers()) ?? []
        case .directors:
            actorItems = (try? await JavDBSDK.shared.directors()) ?? []
        }
    }
}
