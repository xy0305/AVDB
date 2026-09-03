//
//  ActorsView.swift
//  AVDB
//
//  演員：推薦 / 有碼(女) / 有碼(男) / 無碼 / 歐美(女) / 歐美(男)。
//

import SwiftUI

enum ActorTab: String, CaseIterable, Identifiable {
    case recommend
    case censoredFemale
    case censoredMale
    case uncensored
    case westernFemale
    case westernMale

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recommend: return "推薦"
        case .censoredFemale: return "有碼(女)"
        case .censoredMale: return "有碼(男)"
        case .uncensored: return "無碼"
        case .westernFemale: return "歐美(女)"
        case .westernMale: return "歐美(男)"
        }
    }

    var type: String {
        switch self {
        case .recommend, .censoredFemale, .censoredMale: return "0"
        case .uncensored: return "1"
        case .westernFemale, .westernMale: return "2"
        }
    }

    var gender: String? {
        switch self {
        case .recommend: return nil
        case .censoredFemale, .uncensored, .westernFemale: return "0"
        case .censoredMale, .westernMale: return "1"
        }
    }
}

struct ActorsView: View {
    @State private var tab: ActorTab = .recommend
    @StateObject private var vm = ActorsHomeViewModel()
    @State private var showSearch = false

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                UnderlineTabBar(tabs: ActorTab.allCases.map { ($0, $0.title) }, selection: $tab)
                    .padding(.top, 4)
                content
            }
            .background(Color(.systemBackground))
            .navigationTitle("演員")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSearch = true } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
            .navigationDestination(isPresented: $showSearch) { SearchView() }
            .task { await vm.loadRecommend() }
            .onChange(of: tab) { _, new in
                Task { await vm.switchTab(new) }
            }
            .refreshable { await vm.switchTab(tab, force: true) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if tab == .recommend {
            recommendContent
        } else {
            listContent
        }
    }

    private var recommendContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                actorBlock(title: "新人", trailing: vm.newUpdateLabel, actors: vm.newActors)
                actorBlock(title: "月排名", trailing: "全部 >", actors: vm.monthlyActors)
                if !vm.recommendActors.isEmpty {
                    actorBlock(title: "推薦", trailing: nil, actors: vm.recommendActors)
                }
            }
            .padding(.vertical, 12)
        }
    }

    private func actorBlock(title: String, trailing: String?, actors: [Actor]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(actors) { actor in
                    NavigationLink {
                        ActorDetailView(actorID: actor.id)
                    } label: {
                        actorCell(actor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private var listContent: some View {
        ScrollView {
            if vm.isLoading && vm.list.isEmpty {
                EmptyStateView(text: "載入演員…")
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(vm.list) { actor in
                        NavigationLink {
                            ActorDetailView(actorID: actor.id)
                        } label: {
                            actorCell(actor)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if actor.id == vm.list.last?.id {
                                Task { await vm.loadMore() }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                if vm.isLoading { ProgressView().padding() }
            }
        }
    }

    private func actorCell(_ actor: Actor) -> some View {
        VStack(spacing: 8) {
            JavDBImage(url: actor.avatarURL ?? actor.coverURL)
                .aspectRatio(1, contentMode: .fill)
                .frame(minWidth: 0, maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(actor.name ?? "")
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
    }
}

@MainActor
final class ActorsHomeViewModel: ObservableObject {
    @Published var newActors: [Actor] = []
    @Published var monthlyActors: [Actor] = []
    @Published var recommendActors: [Actor] = []
    @Published var list: [Actor] = []
    @Published var isLoading = false
    @Published var newUpdateLabel = ""
    private var page = 1
    private var hasMore = true
    private var currentTab: ActorTab = .recommend
    private let sdk = JavDBSDK.shared

    func loadRecommend() async {
        isLoading = true
        defer { isLoading = false }
        let data = try? await sdk.recommendActors()
        newActors = data?.newActors ?? []
        monthlyActors = data?.monthlyActors ?? []
        recommendActors = data?.recommendActors ?? []
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant")
        f.dateFormat = "M月d日更新"
        newUpdateLabel = f.string(from: Date())
    }

    func switchTab(_ tab: ActorTab, force: Bool = false) async {
        if tab == .recommend {
            currentTab = tab
            if force || newActors.isEmpty { await loadRecommend() }
            return
        }
        if !force, tab == currentTab, !list.isEmpty { return }
        currentTab = tab
        page = 1
        hasMore = true
        list = []
        await fetch()
    }

    func loadMore() async {
        guard currentTab != .recommend, hasMore, !isLoading else { return }
        page += 1
        await fetch()
    }

    private func fetch() async {
        isLoading = true
        defer { isLoading = false }
        let next = (try? await sdk.actors(page: page, type: currentTab.type, gender: currentTab.gender)) ?? []
        if next.isEmpty {
            hasMore = false
        } else if page == 1 {
            list = next
        } else {
            let ids = Set(list.map(\.id))
            list.append(contentsOf: next.filter { !ids.contains($0.id) })
        }
    }
}

/// 演员详情
struct ActorDetailView: View {
    let actorID: String
    @StateObject private var vm: ActorDetailViewModel

    init(actorID: String) {
        self.actorID = actorID
        _vm = StateObject(wrappedValue: ActorDetailViewModel(actorID: actorID))
    }

    var body: some View {
        ScrollView {
            if let actor = vm.actor {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        JavDBImage(url: actor.avatarURL ?? actor.coverURL)
                            .frame(width: 100, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(actor.name ?? "演員")
                                .font(.title3.bold())
                            if let other = actor.otherName, !other.isEmpty {
                                Text(other).font(.caption).foregroundColor(.secondary)
                            }
                            if let birthday = actor.birthday, !birthday.isEmpty {
                                Label(birthday, systemImage: "birthday.cake")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            HStack(spacing: 12) {
                                if let age = actor.age { info("\(age)歲") }
                                if let height = actor.height { info("\(height)cm") }
                                if let cup = actor.cup { info(cup) }
                                if let count = actor.videosCount { info("\(count) 部") }
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal)

                    if vm.movies.isEmpty {
                        if vm.isLoadingMovies {
                            ProgressView().frame(maxWidth: .infinity).padding(.top, 24)
                        } else {
                            Text("暫無作品")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                        }
                    } else {
                        MoviePosterGrid(movies: vm.movies, onAppearLast: { _ in
                            Task { await vm.loadMore() }
                        })
                    }
                }
            } else if vm.isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
            }
        }
        .navigationTitle(vm.actor?.name ?? "演員")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
    }

    private func info(_ text: String) -> some View {
        Text(text).font(.caption).foregroundColor(.secondary)
    }
}

@MainActor
final class ActorDetailViewModel: ObservableObject {
    @Published var actor: Actor?
    @Published var movies: [Movie] = []
    @Published var isLoading = false
    @Published var isLoadingMovies = false
    let actorID: String
    private var page = 1
    private var hasMore = true

    init(actorID: String) {
        self.actorID = actorID
    }

    func load() async {
        isLoading = true
        isLoadingMovies = true
        defer { isLoading = false }
        actor = try? await JavDBSDK.shared.actorDetail(actorID)
        page = 1
        hasMore = true
        movies = []
        await fetchMovies()
    }

    func loadMore() async {
        guard hasMore, !isLoadingMovies else { return }
        page += 1
        await fetchMovies()
    }

    private func fetchMovies() async {
        isLoadingMovies = true
        defer { isLoadingMovies = false }
        let keyword = actor?.name ?? actorID
        let next = (try? await JavDBSDK.shared.search(keyword: keyword, page: page, limit: 21)) ?? []
        if next.isEmpty {
            hasMore = false
        } else if page == 1 {
            movies = next
        } else {
            let ids = Set(movies.map(\.id))
            movies.append(contentsOf: next.filter { !ids.contains($0.id) })
        }
    }
}
