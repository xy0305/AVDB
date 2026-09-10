//
//  SearchView.swift
//  AVDB
//
//  系统搜索栏：支持按 影片/演员/系列/片商/导演/清单/番号 分类搜索。
//

import SwiftUI

/// 搜索分类
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
        case .actor: return "演员"
        case .series: return "系列"
        case .maker: return "片商"
        case .director: return "导演"
        case .list: return "清单"
        case .code: return "番号"
        }
    }

    /// /api/v2/search 的 type 值
    var typeValue: String {
        switch self {
        case .movie: return "movie"
        case .actor: return "actor"
        case .series: return "series"
        case .maker: return "maker"
        case .director: return "director"
        case .list: return "list"
        case .code: return "code"
        }
    }
}

struct SearchView: View {
    @State private var keyword = ""
    @State private var submitted = ""
    @State private var category: SearchCategory = .movie
    @StateObject private var suggest = SearchSuggestStore.shared
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        Group {
            if submitted.isEmpty {
                SearchIdleView(
                    hotKeywords: suggest.hotKeywords,
                    history: suggest.history,
                    onPick: { pick($0) },
                    onClearHistory: { suggest.clearHistory() }
                )
            } else {
                SearchResultView(keyword: submitted, category: category)
                    .id("\(submitted)_\(category.rawValue)")
            }
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            if !submitted.isEmpty {
                categoryPicker
            }
        }
        .focused($isSearchFocused)
        .searchable(text: $keyword, prompt: "輸入演員或番號等關鍵字")
        .onSubmit(of: .search) { submit() }
        .onChange(of: keyword) { _, new in
            if new.isEmpty { submitted = "" }
        }
        .task { await suggest.loadHotKeywords() }
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchCategory.allCases) { cat in
                    LiquidFilterChip(
                        title: cat.title,
                        isSelected: category == cat
                    ) {
                        category = cat
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color(.systemBackground).opacity(0.92))
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

    var body: some View {
        switch category {
        case .movie:
            SearchMovieResultView(keyword: keyword)
        case .actor:
            SearchActorResultView(keyword: keyword)
        case .list:
            SearchListResultView(keyword: keyword)
        case .series, .maker, .director:
            SearchNamedResultView(keyword: keyword, category: category)
        case .code:
            SearchMovieResultView(keyword: keyword, asCode: true)
        }
    }
}

/// 影片 / 番号 结果
struct SearchMovieResultView: View {
    let keyword: String
    var asCode: Bool = false
    @StateObject private var vm: MovieListViewModel

    init(keyword: String, asCode: Bool = false) {
        self.keyword = keyword
        self.asCode = asCode
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
    }

    private func load() async {
        guard actors.isEmpty, !loading else { return }
        loading = true
        defer { loading = false }
        actors = (try? await JavDBSDK.shared.searchActors(keyword: keyword)) ?? []
    }
}

/// 系列 / 片商 / 导演 结果（统一 id/name/videos_count）
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
    }

    @ViewBuilder
    private func namedDestination(_ item: NamedResult) -> some View {
        switch category {
        case .series:
            // 系列详情走影片列表
            SeriesMoviesView(seriesID: item.id, title: item.name ?? item.id)
        case .maker:
            MakerMoviesView(makerID: item.id, title: item.name ?? item.id)
        case .director:
            DirectorMoviesView(directorID: item.id, title: item.name ?? item.id)
        default:
            Text(item.name ?? item.id)
        }
    }

    private func load() async {
        guard items.isEmpty, !loading else { return }
        loading = true
        defer { loading = false }
        items = (try? await JavDBSDK.shared.searchNamed(keyword: keyword, type: category.typeValue)) ?? []
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
    }

    private func load() async {
        guard lists.isEmpty, !loading else { return }
        loading = true
        defer { loading = false }
        lists = (try? await JavDBSDK.shared.searchLists(keyword: keyword)) ?? []
    }
}
