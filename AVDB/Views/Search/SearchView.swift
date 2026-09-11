//
//  SearchView.swift
//  AVDB
//
//  固定搜索栏 + 官方類型/篩選/排序（movie_type / movie_filter_by / movie_sort_by）。
//

import SwiftUI

/// 搜索分类（对应 /api/v2/search 的 type）
enum SearchCategory: String, CaseIterable, Identifiable {
    case movie
    case actor
    case series
    case maker
    case director
    case list
    case code

    var id: String { rawValue }

    var title: String {
        switch self {
        case .movie: return "影片"
        case .actor: return "演員"
        case .series: return "系列"
        case .maker: return "片商"
        case .director: return "導演"
        case .list: return "清單"
        case .code: return "番號"
        }
    }

    var typeValue: String { rawValue }

    var showsMovieFilters: Bool { self == .movie }
}

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var keyword = ""
    @State private var submitted = ""
    @State private var category: SearchCategory = .movie
    @State private var movieType: SearchMovieType = .all
    @State private var filterBy: MovieFilterBy = .all
    @State private var sortBy: MovieSortBy = .relevance
    @StateObject private var suggest = SearchSuggestStore.shared
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            pinnedSearchBar

            if !submitted.isEmpty {
                categoryPicker
                if category.showsMovieFilters {
                    officialMovieFilters
                }
            }

            Group {
                if submitted.isEmpty {
                    SearchIdleView(
                        hotKeywords: suggest.hotKeywords,
                        history: suggest.history,
                        onPick: { pick($0) },
                        onClearHistory: { suggest.clearHistory() }
                    )
                } else {
                    SearchResultView(
                        keyword: submitted,
                        category: category,
                        sortBy: sortBy,
                        filterBy: filterBy,
                        movieType: movieType
                    )
                    .id("\(submitted)_\(category.rawValue)_\(movieType.id)_\(filterBy.rawValue)_\(sortBy.rawValue)")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(AdaptiveLayout.isPad ? .visible : .automatic, for: .tabBar)
        .task { await suggest.loadHotKeywords() }
        .onAppear { isSearchFocused = submitted.isEmpty }
    }

    /// 钉在顶部，不随列表滚动、不走系统 searchable。
    private var pinnedSearchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("搜索番號 / 關鍵詞", text: $keyword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isSearchFocused)
                    .onSubmit { submit() }
                if !keyword.isEmpty {
                    Button {
                        keyword = ""
                        submitted = ""
                        isSearchFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.systemGray6), in: Capsule(style: .continuous))

            Button("取消") {
                if submitted.isEmpty, keyword.isEmpty {
                    dismiss()
                } else {
                    keyword = ""
                    submitted = ""
                    isSearchFocused = true
                }
            }
            .font(.body)
            .foregroundStyle(.tint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private var categoryPicker: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(SearchCategory.allCases) { cat in
                        Button {
                            category = cat
                        } label: {
                            VStack(spacing: 8) {
                                Text(cat.title)
                                    .font(.subheadline.weight(category == cat ? .semibold : .regular))
                                    .foregroundStyle(category == cat ? Color.accentColor : Color.primary)
                                Rectangle()
                                    .fill(category == cat ? Color.accentColor : Color.clear)
                                    .frame(height: 2)
                            }
                            .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
            }
            Divider()
        }
        .background(Color(.systemBackground))
    }

    /// 官方搜索页：類型 / 篩選 / 排序 三行芯片。
    private var officialMovieFilters: some View {
        VStack(alignment: .leading, spacing: 10) {
            officialChipRow("類型", SearchMovieType.allCases, selection: $movieType) { $0.title }
            officialChipRow("篩選", MovieFilterBy.allCases, selection: $filterBy) { $0.title }
            officialChipRow("排序", MovieSortBy.allCases, selection: $sortBy) { $0.title }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    private func officialChipRow<T: Hashable & Identifiable>(
        _ label: String,
        _ items: [T],
        selection: Binding<T>,
        title: @escaping (T) -> String
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(width: 36, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        let selected = selection.wrappedValue == item
                        Button {
                            selection.wrappedValue = item
                        } label: {
                            Text(title(item))
                                .font(.subheadline.weight(selected ? .semibold : .regular))
                                .foregroundStyle(selected ? Color.white : Color.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    selected ? Color.accentColor : Color(.systemGray5),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func submit() {
        pick(keyword)
    }

    private func pick(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        keyword = trimmed
        submitted = trimmed
        suggest.addHistory(trimmed)
        isSearchFocused = false
    }
}

/// 空搜索页：近期热搜（startup.recent_keywords）+ 本地历史。
private struct SearchIdleView: View {
    let hotKeywords: [String]
    let history: [String]
    let onPick: (String) -> Void
    let onClearHistory: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !hotKeywords.isEmpty {
                    keywordSection(title: "近期熱搜", words: hotKeywords)
                }
                if !history.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        keywordSection(title: "歷史搜索", words: history)
                        Button("清空", action: onClearHistory)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    }
                }
                if hotKeywords.isEmpty && history.isEmpty {
                    ContentUnavailableView("搜索", systemImage: "magnifyingglass", description: Text("输入番号、演员名或关键词"))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private func keywordSection(title: String, words: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
            FlowLayout(spacing: 8) {
                ForEach(words, id: \.self) { word in
                    Button {
                        onPick(word)
                    } label: {
                        Text(word)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

@MainActor
final class SearchSuggestStore: ObservableObject {
    static let shared = SearchSuggestStore()

    @Published private(set) var hotKeywords: [String] = []
    @Published private(set) var history: [String] = []

    private let historyKey = "avdb.search.history"
    private let historyLimit = 30

    private init() {
        history = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
    }

    func loadHotKeywords() async {
        if let words = try? await JavDBSDK.shared.startup().recentKeywords, !words.isEmpty {
            hotKeywords = words
        }
    }

    func addHistory(_ keyword: String) {
        var next = history.filter { $0.caseInsensitiveCompare(keyword) != .orderedSame }
        next.insert(keyword, at: 0)
        if next.count > historyLimit { next = Array(next.prefix(historyLimit)) }
        history = next
        UserDefaults.standard.set(next, forKey: historyKey)
    }

    func clearHistory() {
        history = []
        UserDefaults.standard.removeObject(forKey: historyKey)
    }
}

struct SearchResultView: View {
    let keyword: String
    let category: SearchCategory
    var sortBy: MovieSortBy = .relevance
    var filterBy: MovieFilterBy = .all
    var movieType: SearchMovieType = .all

    var body: some View {
        switch category {
        case .movie:
            SearchMovieResultView(
                keyword: keyword,
                type: "movie",
                sortBy: sortBy,
                filterBy: filterBy,
                movieType: movieType
            )
        case .actor:
            SearchActorResultView(keyword: keyword)
        case .list:
            SearchListResultView(keyword: keyword)
        case .series, .maker, .director, .code:
            SearchNamedResultView(keyword: keyword, category: category)
        }
    }
}

/// 影片结果
struct SearchMovieResultView: View {
    let keyword: String
    var type: String = "movie"
    var sortBy: MovieSortBy = .relevance
    var filterBy: MovieFilterBy = .all
    var movieType: SearchMovieType = .all
    @StateObject private var vm: MovieListViewModel

    init(
        keyword: String,
        type: String = "movie",
        sortBy: MovieSortBy = .relevance,
        filterBy: MovieFilterBy = .all,
        movieType: SearchMovieType = .all
    ) {
        self.keyword = keyword
        self.type = type
        self.sortBy = sortBy
        self.filterBy = filterBy
        self.movieType = movieType
        _vm = StateObject(wrappedValue: MovieListViewModel { page in
            try await JavDBSDK.shared.search(
                keyword: keyword,
                page: page,
                type: type,
                sortBy: sortBy,
                filterBy: filterBy,
                movieType: movieType
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
        .task { if vm.movies.isEmpty { await vm.loadMore() } }
        .refreshable { await vm.refresh() }
    }
}

/// 演员结果
struct SearchActorResultView: View {
    let keyword: String
    @State private var actors: [Actor] = []
    @State private var loading = false

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(actors) { actor in
                    NavigationLink {
                        ActorDetailView(actorID: actor.id)
                    } label: {
                        VStack(spacing: 6) {
                            JavDBImage(url: actor.avatarURL ?? actor.coverURL)
                                .frame(width: 90, height: 90)
                                .clipped()
                                .clipShape(Circle())
                                .contentShape(Circle())
                            Text(actor.displayName)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            if loading { ProgressView().padding() }
        }
        .task { await load() }
        .refreshable { await reload() }
    }

    private func load() async {
        guard actors.isEmpty, !loading else { return }
        await reload()
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        if let next = try? await JavDBSDK.shared.searchActors(keyword: keyword) {
            actors = next
        }
    }
}

/// 系列 / 片商 / 导演 / 番号前缀
struct SearchNamedResultView: View {
    let keyword: String
    let category: SearchCategory
    @State private var items: [NamedResult] = []
    @State private var loading = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    NavigationLink {
                        namedDestination(item)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name ?? item.id)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                if let c = item.videosCount {
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
                    Divider()
                }
            }
            .padding(.horizontal, 16)
            if loading { ProgressView().padding() }
        }
        .task { await load() }
        .refreshable { await reload() }
    }

    @ViewBuilder
    private func namedDestination(_ item: NamedResult) -> some View {
        switch category {
        case .series:
            SeriesMoviesView(seriesID: item.id, title: item.name ?? item.id)
        case .maker:
            MakerMoviesView(makerID: item.id, title: item.name ?? item.id)
        case .director:
            DirectorMoviesView(directorID: item.id, title: item.name ?? item.id)
        case .code:
            SeriesNumberMoviesView(number: item.id, title: item.name ?? item.id)
        default:
            Text(item.name ?? item.id)
        }
    }

    private func load() async {
        guard items.isEmpty, !loading else { return }
        await reload()
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        if let next = try? await JavDBSDK.shared.searchNamed(keyword: keyword, type: category.typeValue) {
            items = next
        }
    }
}

/// 清单结果
struct SearchListResultView: View {
    let keyword: String
    @State private var lists: [MovieList] = []
    @State private var loading = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(lists) { list in
                    NavigationLink {
                        ListDetailView(listID: list.id, title: list.displayName)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(list.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                if let n = list.movieCount {
                                    Text("\(n) 部")
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
                    Divider()
                }
            }
            .padding(.horizontal, 16)
            if loading { ProgressView().padding() }
        }
        .task { await load() }
        .refreshable { await reload() }
    }

    private func load() async {
        guard lists.isEmpty, !loading else { return }
        await reload()
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        if let next = try? await JavDBSDK.shared.searchLists(keyword: keyword) {
            lists = next
        }
    }
}
