//
//  ActorsView.swift
//  AVDB
//
//  演員：推薦 / 有碼(女) / 有碼(男) / 無碼 / 歐美(女) / 歐美(男)。
//

import SwiftUI
import UIKit

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
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var columns: [GridItem] {
        let count = sizeClass == .regular ? 5 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 14), count: count)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                UnderlineTabBar(tabs: ActorTab.allCases.map { ($0, $0.title) }, selection: $tab)
                    .padding(.top, 4)
                content
            }
            .background {
                LiquidGlassBackground()
            }
            .frame(maxWidth: .infinity)
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
            .padding(.horizontal, AdaptiveLayout.horizontalPadding)

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
            .padding(.horizontal, AdaptiveLayout.gridPadding)
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
                .padding(.horizontal, AdaptiveLayout.gridPadding)
                .padding(.vertical, 12)
                if vm.isLoading { ProgressView().padding() }
            }
        }
    }

    private func actorCell(_ actor: Actor) -> some View {
        VStack(spacing: 8) {
            ClippedAspectFill(aspectRatio: 1) {
                JavDBImage(url: actor.avatarURL ?? actor.coverURL)
            }
            Text(actor.name ?? "")
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
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

/// 演员详情：/api/v1/actors/{id} 嵌套 actor + filter_tags，作品走 movies/tags
struct ActorDetailView: View {
    let actorID: String
    @StateObject private var vm: ActorDetailViewModel

    init(actorID: String) {
        self.actorID = actorID
        _vm = StateObject(wrappedValue: ActorDetailViewModel(actorID: actorID))
    }

    @EnvironmentObject private var appState: AppState
    @State private var showLogin = false
    @State private var showAllFilters = false

    var body: some View {
        ScrollView {
            if let actor = vm.actor {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        JavDBImage(url: actor.avatarURL ?? actor.coverURL)
                            .frame(width: 100, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(actor.displayName)
                                .font(.title3.bold())
                            if let other = actor.otherName, !other.isEmpty, other != actor.displayName {
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
                            if let twitter = actor.twitterID, !twitter.isEmpty {
                                info("@" + twitter)
                            }
                            HStack(spacing: 18) {
                                actorActionButton(
                                    icon: vm.hasFollowed ? "eye.fill" : "eye",
                                    title: vm.hasFollowed ? "已关注" : "关注",
                                    active: vm.hasFollowed
                                ) {
                                    if appState.isLoggedIn { Task { await vm.toggleFollow() } }
                                    else { showLogin = true }
                                }
                                actorActionButton(
                                    icon: vm.hasCollected ? "heart.fill" : "heart",
                                    title: vm.hasCollected ? "已收藏" : "收藏",
                                    active: vm.hasCollected
                                ) {
                                    if appState.isLoggedIn { Task { await vm.toggleCollect() } }
                                    else { showLogin = true }
                                }
                            }
                            .disabled(vm.isCollecting)
                            if let hint = vm.collectHint {
                                Text(hint)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
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
        .navigationTitle(vm.actor.map { "演員 - \($0.displayName)" } ?? "演員")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actorFilterBar
        }
        .task { await vm.load() }
        .sheet(isPresented: $showLogin) {
            LoginView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $vm.showYearPicker) {
            YearWheelPicker(
                years: vm.yearOptions,
                selection: vm.year,
                onConfirm: { year in
                    Task { await vm.selectYear(year) }
                }
            )
            .presentationDetents([.height(280)])
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showAllFilters) {
            ActorAllFiltersSheet(vm: vm)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground {
                    if #available(iOS 26.0, *) {
                        Color.clear
                    } else {
                        Color(.systemBackground).opacity(0.92)
                    }
                }
        }
    }

    private var actorFilterBar: some View {
        VStack(spacing: 0) {
            Button {
                showAllFilters = true
            } label: {
                Capsule()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("展開全部分類")

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("篩選")
                        .font(.headline)
                    Spacer()
                    Button {
                        vm.showYearPicker = true
                    } label: {
                        Text(vm.yearTitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.tint)
                    }
                    Menu {
                        ForEach(CatalogSort.allCases) { item in
                            Button {
                                Task { await vm.selectSort(item) }
                            } label: {
                                if vm.sort == item {
                                    Label(item.title, systemImage: "checkmark")
                                } else {
                                    Text(item.title)
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
                .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        primaryFilterChip("全部", id: "")
                        ForEach(vm.filterTags) { tag in
                            primaryFilterChip(tag.name ?? tag.id, id: tag.id)
                        }
                        ForEach(vm.tags) { tag in
                            tagFilterChip(
                                "\(tag.name ?? tag.id)\(tag.count.map { "(\($0))" } ?? "")",
                                id: tag.id
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 10)
        }
        .background {
            if #available(iOS 26.0, *) {
                Rectangle().fill(.clear).glassEffect(.regular, in: Rectangle())
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    if value.translation.height < -40 {
                        showAllFilters = true
                    }
                }
        )
    }

    private func actorActionButton(icon: String, title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 18, weight: .medium))
                Text(title).font(.caption)
            }
            .foregroundStyle(active ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func primaryFilterChip(_ title: String, id: String) -> some View {
        LiquidFilterChip(
            title: title,
            isSelected: vm.filter == id && vm.filterByTags.isEmpty
        ) {
            Task { await vm.selectFilter(id) }
        }
    }

    private func tagFilterChip(_ title: String, id: String) -> some View {
        LiquidFilterChip(
            title: title,
            isSelected: vm.filterByTags == id
        ) {
            Task { await vm.selectFilterTag(id) }
        }
    }

    private func info(_ text: String) -> some View {
        Text(text).font(.caption).foregroundColor(.secondary)
    }
}

@MainActor
final class ActorDetailViewModel: ObservableObject {
    @Published var actor: Actor?
    @Published var filterTags: [Tag] = []
    @Published var tags: [Tag] = []
    @Published var movies: [Movie] = []
    @Published var isLoading = false
    @Published var isLoadingMovies = false
    @Published var filter = ""
    // 演员详情的「精选综合 / 4 小时以上 / 中出」属于 filter_by_tags，
    // 不能拼进 filter_by 的演员筛选段。
    @Published var filterByTags = ""
    @Published var sort: CatalogSort = .releaseDesc
    @Published var year: String? = nil
    @Published var showYearPicker = false
    @Published var hasCollected = false
    @Published var hasFollowed = false
    @Published var isCollecting = false
    @Published var collectHint: String?
    let actorID: String
    private var page = 1
    private var hasMore = true
    /// 有码女优详情页官方固定 filter_by=0:a:{id}:，不要拿 actor.type（欧美/无码会串片）
    private let catalogType = "0"

    var yearTitle: String {
        year.map { "\($0)" } ?? "全部年份"
    }

    var yearOptions: [String?] {
        let current = Calendar.current.component(.year, from: Date())
        return [nil] + (1990...current).reversed().map { String($0) }
    }

    init(actorID: String) {
        self.actorID = actorID
    }

    func load() async {
        isLoading = true
        isLoadingMovies = true
        defer { isLoading = false }
        if let payload = try? await JavDBSDK.shared.actorDetail(actorID) {
            actor = payload.actor
            filterTags = payload.filterTags ?? []
            tags = payload.tags ?? []
            hasCollected = payload.hasCollected ?? false
            hasFollowed = UserDefaults.standard.bool(forKey: "avdb.followed.actor.\(actorID)")
        }
        page = 1
        hasMore = true
        movies = []
        await fetchMovies()
    }

    func selectFilter(_ id: String) async {
        guard filter != id || !filterByTags.isEmpty else { return }
        filter = id
        filterByTags = ""
        page = 1
        hasMore = true
        movies = []
        await fetchMovies()
    }

    func selectFilterTag(_ id: String) async {
        guard filterByTags != id || !filter.isEmpty else { return }
        filter = ""
        filterByTags = id
        page = 1
        hasMore = true
        movies = []
        await fetchMovies()
    }

    func selectSort(_ sort: CatalogSort) async {
        guard self.sort != sort else { return }
        self.sort = sort
        page = 1
        hasMore = true
        movies = []
        await fetchMovies()
    }

    func selectYear(_ year: String?) async {
        showYearPicker = false
        guard self.year != year else { return }
        self.year = year
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

    func toggleFollow() async {
        guard !isCollecting else { return }
        isCollecting = true
        collectHint = nil
        defer { isCollecting = false }
        let next = !hasFollowed
        do {
            _ = try await JavDBSDK.shared.followActor(actorID, follow: next)
            hasFollowed = next
            UserDefaults.standard.set(next, forKey: "avdb.followed.actor.\(actorID)")
        } catch {
            collectHint = error.localizedDescription
        }
    }

    func toggleCollect() async {
        guard actor != nil, !isCollecting else { return }
        isCollecting = true
        collectHint = nil
        defer { isCollecting = false }
        let next = !hasCollected
        do {
            _ = try await JavDBSDK.shared.collectActor(actorID, collect: next)
            hasCollected = next
        } catch {
            collectHint = error.localizedDescription
        }
    }

    private func fetchMovies() async {
        isLoadingMovies = true
        defer { isLoadingMovies = false }
        let next = (try? await JavDBSDK.shared.actorMovies(
            actorID, page: page, limit: 24, type: catalogType, filter: filter,
            filterByTags: filterByTags.isEmpty ? nil : filterByTags,
            sortBy: sort.sortBy,
            orderBy: sort.orderBy,
            year: year
        )) ?? []
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

/// 演员分类上拉面板：液态玻璃 + 全部标签换行展示。
struct ActorAllFiltersSheet: View {
    @ObservedObject var vm: ActorDetailViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !vm.filterTags.isEmpty {
                        sectionTitle("快捷")
                        chipWrap {
                            sheetChip("全部", selected: vm.filter.isEmpty && vm.filterByTags.isEmpty) {
                                Task { await vm.selectFilter(""); dismiss() }
                            }
                            ForEach(vm.filterTags) { tag in
                                sheetChip(tag.name ?? tag.id, selected: vm.filter == tag.id && vm.filterByTags.isEmpty) {
                                    Task { await vm.selectFilter(tag.id); dismiss() }
                                }
                            }
                        }
                    }
                    if !vm.tags.isEmpty {
                        sectionTitle("分類")
                        chipWrap {
                            ForEach(vm.tags) { tag in
                                sheetChip(
                                    "\(tag.name ?? tag.id)\(tag.count.map { "(\($0))" } ?? "")",
                                    selected: vm.filterByTags == tag.id
                                ) {
                                    Task { await vm.selectFilterTag(tag.id); dismiss() }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background {
                if #available(iOS 26.0, *) {
                    Color.clear
                } else {
                    Color.clear.background(.ultraThinMaterial)
                }
            }
            .navigationTitle("全部分類")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
        }
        .background {
            if #available(iOS 26.0, *) {
                Rectangle().fill(.clear).glassEffect(.regular, in: Rectangle())
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func chipWrap<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        FlowLayout(spacing: 8) { content() }
    }

    private func sheetChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selected ? Color.accentColor : Color(.systemGray5), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 官方演员页年份滚轮：全部年份 + 逐年，滚动时轻震动。
struct YearWheelPicker: View {
    let years: [String?]
    let selection: String?
    let onConfirm: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            Text(title(for: index))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tint)
                .padding(.top, 18)
                .padding(.bottom, 8)

            Picker("", selection: $index) {
                ForEach(years.indices, id: \.self) { i in
                    Text(title(for: i)).tag(i)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 160)
            .onChange(of: index) { _, _ in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }

            HStack {
                Button("取消") { dismiss() }
                    .frame(maxWidth: .infinity)
                Button("确认") {
                    let year = years.indices.contains(index) ? years[index] : nil
                    onConfirm(year)
                    dismiss()
                }
                .frame(maxWidth: .infinity)
            }
            .font(.body.weight(.medium))
            .foregroundStyle(.tint)
            .padding(.vertical, 12)
        }
        .onAppear {
            index = years.firstIndex(where: { $0 == selection }) ?? 0
        }
    }

    private func title(for i: Int) -> String {
        guard years.indices.contains(i), let year = years[i] else { return "全部年份" }
        return year
    }
}
