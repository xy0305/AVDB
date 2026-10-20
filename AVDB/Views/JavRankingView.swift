import SwiftUI

struct JavRankingView: View {
    var rankingsOnly = false
    @ObservedObject private var source = JavRankingSource.shared
    @AppStorage("javranking.adultConfirmed") private var adultConfirmed = false
    private let entries: [(String, String, String)] = [
        ("来源首页", "/zh-hans/", "house"), ("全部榜单 / 历年年度榜", "/zh-hans/rankings/", "list.number"),
        ("片库 / 题材分类 / 发行日期", "explore", "square.grid.3x3"), ("搜索影片 / 演员 / 片商 / 导演", "search", "magnifyingglass"),
        ("今天冲哪个？", "pick", "shuffle"), ("神作榜", "/zh-hans/most-awarded-videos/", "crown"),
        ("女优榜", "/zh-hans/most-awarded-actors/", "person.2"), ("男优榜", "/zh-hans/most-awarded-male-actors/", "person.2.fill"),
        ("使用指南", "/zh-hans/help/", "questionmark.circle"), ("关于来源", "/zh-hans/about/", "info.circle"),
        ("反馈说明", "/zh-hans/feedback/", "bubble"), ("插件说明", "/zh-hans/extension/", "puzzlepiece"),
        ("隐私政策", "/zh-hans/privacy/", "hand.raised"), ("使用条款", "/zh-hans/terms/", "doc.text"), ("商业合作说明", "/zh-hans/sponsor/", "info.circle")]
    var body: some View {
        Group {
            if adultConfirmed && rankingsOnly {
                JRBackendView(route: "topics", title: "全部榜单")
            } else if adultConfirmed {
                JRBackendView(route: "home", title: "JAV Ranking")
            } else {
                ContentUnavailableView {
                    Label("仅限成年人", systemImage: "18.circle")
                } description: {
                    Text("此来源包含成人影片的公开资料。仅在您已满 18 岁且所在地法律允许时进入。")
                } actions: { Button("我已满 18 岁，继续") { adultConfirmed = true }.buttonStyle(.borderedProminent) }
            }
        }
        .navigationTitle("JAV Ranking").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
    @ViewBuilder private func destination(_ path: String) -> some View {
        switch path {
        case "explore": JRPageView(path: "/zh-hans/explore/")
        case "search": JRIndexView(mode: .search)
        case "pick": JRIndexView(mode: .pick)
        default: JRPageView(path: path)
        }
    }
}

struct JavRankingSettingsView: View {
    @ObservedObject private var source = JavRankingSource.shared
    @State private var domain = ""
    @State private var backendURL = ""
    @ObservedObject private var backend = JRBackendClient.shared
    @State private var message = ""
    var body: some View {
        Form {
            Section("默认 · 与 JAVLibrary 共用外部数据库") {
                Button("复用已配置的外部数据库与钥匙串令牌") { backend.useExternalLibrary(); message = "已切换；旧请求与显示已取消。" }
                NavigationLink("配置外部数据库 / API 令牌") { ExternalLibrarySettingsView() }
                Text(backend.externalMode ? "当前：外部数据库同源模式" : "当前：独立 HTTPS 模式")
                Text("若外部数据库使用 HTTP，地址与令牌均以未加密明文传输。仅向您已配置的同一协议、主机和端口发送令牌；不自动降级、不转发至来源站点。未启用或缺少令牌时请先完成外部数据库设置。") .font(.footnote)
                if backend.externalMode, let endpoint = backend.endpoint { Text(endpoint.absoluteString).font(.caption).textSelection(.enabled) }
            }
            Section("可选 · 独立缓存后端 HTTPS（不携带外部库令牌）") {
                TextField("尚未配置；不要填回环地址", text: $backendURL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Button("保存 HTTPS 后端") {
                    do { try backend.configure(backendURL); backendURL = backend.endpoint?.absoluteString ?? ""; message = "后端设置已保存；是否可用取决于公网 HTTPS 激活。" }
                    catch { message = error.localizedDescription }
                }
                Text("仅使用系统受信 TLS。没有内置 IP、密钥或自动降级；留空表示未启用。此项不修改下方来源域名或 JavDB。") .font(.footnote)
                NavigationLink("可选：原站 HTML 直连（可能受限，不自动回退）") { JRPageView(path: "/zh-hans/") }
            }
            Section("JAV Ranking 来源域名") {
                TextField("https://javranking.cc", text: $domain)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Button("保存并重新加载来源") {
                    do { try source.configure(domain); domain = source.base.absoluteString; message = "已保存；旧请求已取消，来源缓存已清空。" }
                    catch { message = error.localizedDescription }
                }
                Button("恢复默认域名") { domain = JRPolicy.defaultDomain }
                if !message.isEmpty { Text(message).font(.footnote) }
            }
            Section {
                Text("仅接受域名或 HTTP(S) 根地址，统一使用 HTTPS。禁止账号、路径、端口、查询及片段。只影响 JAV Ranking，不修改 JavDB、115 或播放器设置。")
                Text("列表、索引、详情和站内导航均跟随此域名；远程图片仅接受来源域名/子域名或已发现的 jdbstatic HTTPS CDN。")
                Button("清空来源缓存并重载") { source.resetCache(); message = "来源缓存已清空。" }
            }.font(.footnote)
        }
        .onAppear { domain = source.base.absoluteString; backendURL = UserDefaults.standard.string(forKey: "javranking.backendHTTPS") ?? "" }
        .navigationTitle("来源设置").toolbar(.visible, for: .navigationBar)
    }
}

// Same native poster card and responsive column policy as JavDB, separate destinations.
struct JRPosterGrid: View {
    let videos: [JRVideo]
    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .preference(key: JRWidthKey.self, value: geometry.size.width)
        }.frame(height: 0)
        JRMeasuredGrid(videos: videos)
    }
}
private struct JRWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
private struct JRMeasuredGrid: View {
    let videos: [JRVideo]
    @State private var width: CGFloat = 390
    @ObservedObject private var source = JavRankingSource.shared
    @State private var mapped: [String: Movie] = [:]
    @State private var completed = Set<String>()
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12, alignment: .top), count: AdaptiveLayout.columnCount(width: width, padding: AdaptiveLayout.gridPadding, spacing: 12)), spacing: 16) {
            ForEach(videos) { video in
                VStack(alignment: .leading, spacing: 4) {
                    NavigationLink { posterDestination(video) } label: {
                        // Keep the source card geometry and metadata stable after verification.
                        // Native metadata belongs in the destination, not a differently sized row.
                        MoviePosterCard(movie: Movie(id: video.id, number: video.code, title: video.title, thumbURL: video.image, coverURL: video.image))
                    }.buttonStyle(.plain).accessibilityIdentifier("jr-poster-\(video.rank ?? 0)")
                    if let rank = video.rank { Text("来源排名 #\(rank)").font(.caption).foregroundStyle(.secondary) }
                    if !video.code.isEmpty {
                        Text(mapped[video.path] != nil ? "完整番号已核验 · JavDB" : completed.contains(video.path) ? "点击重试核验 · 来源资料仅辅助" : "点击核验并打开原生详情")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(2).frame(height: 30, alignment: .topLeading)
                    }
                }.id(video.path).frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading).contentShape(Rectangle()).clipped()
            }
        }.scrollTargetLayout().padding(.horizontal, AdaptiveLayout.gridPadding)
        .background { GeometryReader { g in Color.clear.preference(key: JRWidthKey.self, value: g.size.width) } }
        .onPreferenceChange(JRWidthKey.self) { if $0 > 0 { width = $0 } }
        .task(id: "\(source.generation):" + videos.map(\.path).joined(separator: ",")) {
            // Never launch speculative JavDB searches while posters are loading.
            // Reuse only verified cache entries; an actual tap owns resolution.
            mapped.removeAll(); completed.removeAll()
            for video in videos {
                if let movie = source.cachedMovie(code: video.code) { mapped[video.path] = movie }
            }
        }

    }
    @ViewBuilder private func posterDestination(_ video: JRVideo) -> some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--jr-navigation-fixture") {
            // Same page, grid and navigation lifecycle; no live account/backend.
            Text("Neutral detail \(video.rank ?? 0)")
                .accessibilityIdentifier("jr-detail-\(video.rank ?? 0)")
                .navigationTitle("Neutral detail")
        } else {
            JRMovieRoute(video: video)
        }
        #else
        JRMovieRoute(video: video)
        #endif
    }

}

struct JRIndexView: View {
    enum Mode { case explore, search, pick }
    let mode: Mode
    @ObservedObject private var source = JavRankingSource.shared
    @State private var index: JRIndex?
    @State private var query = ""
    @State private var selected = Set<Int>()
    @State private var sort = "score"
    @State private var year = "全部年份"
    @State private var limit = 12
    @State private var loading = false
    @State private var error = ""
    @State private var picked: JRVideo?
    private var title: String { mode == .search ? "来源搜索" : mode == .pick ? "今天冲哪个？" : "片库与题材" }
    @State private var filtered: [JRVideo] = []
    @State private var entities: [JRLink] = []
    private var filterKey: String { "\(source.generation):\(query):\(sort):\(year):" + selected.sorted().map(String.init).joined(separator: ",") }
    private func updateResults() async {
        guard let snapshot = index else { filtered = []; entities = []; return }
        let epoch = source.generation, request = filterKey
        let q = JRPolicy.normalizedCode(query), chosen = selected, ordering = sort, chosenYear = year
        let worker = Task.detached(priority: .userInitiated) { () -> ([JRVideo], [JRLink]) in
            let videos = snapshot.videos.filter { v in
                (q.isEmpty || JRPolicy.normalizedCode(v.code + v.title + v.subtitle).contains(q)) && chosen.isSubset(of: Set(v.categories)) && (chosenYear == "全部年份" || v.date.hasPrefix(chosenYear))
            }.sorted { a, b in
                if ordering == "newest", a.date != b.date { return a.date > b.date }
                if ordering == "oldest", a.date != b.date { return (a.date.isEmpty ? "9999" : a.date) < (b.date.isEmpty ? "9999" : b.date) }
                if a.score != b.score { return a.score > b.score }; return a.path < b.path
            }
            let links = q.isEmpty ? [] : snapshot.entities.filter { JRPolicy.normalizedCode(snapshot.aliases[$0.path] ?? $0.title).contains(q) }
            return (videos, links)
        }
        let value = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
        guard !Task.isCancelled, epoch == source.generation, request == filterKey else { return }
        filtered = value.0; entities = value.1
    }
    private var years: [String] {
        var values = Set<String>()
        for video in index?.videos ?? [] {
            let value = String(video.date.prefix(4))
            if value.count == 4 { values.insert(value) }
        }
        let ordered: [String] = values.sorted { (left: String, right: String) -> Bool in left > right }
        return ["全部年份"] + ordered
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if loading { ProgressView("加载公开索引…").frame(maxWidth: .infinity) }
                if !error.isEmpty { Text(error).foregroundStyle(.secondary); Button("重试") { Task { await load() } } }
                if mode == .search && index == nil { results }
                if let index { indexContent(index) }
            }.padding(.vertical).frame(maxWidth: AdaptiveLayout.contentMaxWidth).frame(maxWidth: .infinity)
        }
        .background { LiquidGlassBackground() }
        .searchable(text: $query, prompt: "番号 / 名称")
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .task(id: source.generation) { await load() }
        .refreshable { await load(refresh: true) }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink { JavRankingSettingsView() } label: { Image(systemName: "gearshape") } } }
        .task(id: filterKey) {
            if mode == .search && index == nil && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
                await load()
            }
            await updateResults()
        }
        .onChange(of: query) { _,_ in limit = 12; picked = nil }
        .onChange(of: selected) { _,_ in limit = 12; picked = nil }
        .onChange(of: sort) { _,_ in limit = 12 }
        .onChange(of: year) { _,_ in limit = 12; picked = nil }
    }
    @ViewBuilder private func indexContent(_ index: JRIndex) -> some View {
        if mode != .search { filters(index) }
        if mode == .pick {
            Text("从来源当前公开片库按题材和年份随机抽取；不复制网站专用抽签算法。")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            Button("随机抽取") { picked = filtered.randomElement() }.buttonStyle(.borderedProminent).padding(.horizontal)
            if let picked { JRPosterGrid(videos: [picked]) }
        } else { results }
    }
    @ViewBuilder private func filters(_ index: JRIndex) -> some View {
        HStack {
            Picker("排序", selection: $sort) {
                Text("战力积分").tag("score")
                Text("最新发行").tag("newest")
                Text("最早发行").tag("oldest")
            }
            Picker("年份", selection: $year) { ForEach(years, id: \.self) { Text($0).tag($0) } }
            Menu("题材 \(selected.count)") {
                Button("清除筛选") { selected.removeAll() }
                ForEach(index.categories) { category in
                    Button { toggleCategory(category.id) } label: {
                        Label(category.name, systemImage: selected.contains(category.id) ? "checkmark.circle.fill" : "circle")
                    }
                }
            }
        }.padding(.horizontal, AdaptiveLayout.horizontalPadding)
        if !selected.isEmpty {
            Text(index.categories.filter { selected.contains($0.id) }.map(\.name).joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, AdaptiveLayout.horizontalPadding)
        }
    }
    private func toggleCategory(_ id: Int) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
    @ViewBuilder private var results: some View {
        if mode == .search && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView("输入番号或名称", systemImage: "magnifyingglass", description: Text("搜索影片、演员别名、片商和导演。仅搜索来源收录的公开资料。"))
        } else {
            Text("\(filtered.count) 部影片 · \(entities.count) 个相关人物/机构")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            ForEach(Array(entities.prefix(limit))) { link in
                NavigationLink { JRPageView(path: link.path) } label: {
                    Label(link.title, systemImage: "person.text.rectangle")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
                }
            }
            JRPosterGrid(videos: Array(filtered.prefix(limit)))
            if filtered.isEmpty && entities.isEmpty { ContentUnavailableView("没有匹配资料", systemImage: "magnifyingglass") }
            if filtered.count > limit || entities.count > limit {
                Button("加载更多") { limit += 12 }.frame(maxWidth: .infinity).padding()
            }
        }
    }
    private func load(refresh: Bool = false) async {
        let epoch = source.generation
        index = source.cachedIndex(search: mode == .search); picked = nil; error = ""
        if mode == .search && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { loading = false; return }
        loading = true
        if let _ = index { await updateResults() }
        do { let value = try await source.index(search: mode == .search, refresh: refresh); guard epoch == source.generation, !Task.isCancelled else { return }; index = value; await updateResults() }
        catch { if epoch == source.generation && !Task.isCancelled { self.error = error.localizedDescription } }
        if epoch == source.generation { loading = false }
    }
}

// Owned by one navigation route, not keyed globally by URL: opening the same
// source twice must not overwrite another instance's loaded count or position.
private final class JRPageState: ObservableObject {
    @Published var page: JRPage?
    @Published var isPreview = false
    @Published var error = ""
    @Published var loading = false
    @Published var limit = 12
    @Published var anchor: String?
    var loadedGeneration: Int?
}

struct JRPageView: View {
    let path: String
    var sourceOnly = false
    @ObservedObject private var source = JavRankingSource.shared
    @StateObject private var state = JRPageState()
    private var page: JRPage? { state.page }
    private var isPreview: Bool { state.isPreview }
    private var error: String { state.error }
    private var loading: Bool { state.loading }
    private var limit: Int { state.limit }
    var body: some View {
        Group {
            if let detail = page?.detail, !sourceOnly {
                JRMovieRoute(video: detail)
            } else { sourceContent }
        }
        .task(id: source.generation) { await load() }
    }
    private var sourceContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if path.hasPrefix("/zh-hans/explore/") {
                    NavigationLink { JRIndexView(mode: .explore) } label: { Label("题材 / 年份 / 排序筛选（按需加载索引）", systemImage: "line.3.horizontal.decrease.circle") }.padding(.horizontal)
                }
                if loading { ProgressView("加载公开内容…").frame(maxWidth: .infinity) }
                if !error.isEmpty { Text(error).foregroundStyle(.secondary); Button("重试") { Task { await load() } } }
                if let page {
                    if let detail = page.detail {
                        JavDBImage(url: detail.image).aspectRatio(4/3, contentMode: .fit).frame(maxHeight: 340).clipShape(RoundedRectangle(cornerRadius: 14)).padding(.horizontal)
                        VStack(alignment: .leading, spacing: 12) {
                            Text(detail.code).font(.headline).foregroundStyle(.tint)
                            Text(detail.title).font(.title3.bold()).textSelection(.enabled)
                            ForEach(Array(page.metadata.enumerated()), id: \.offset) { _, text in Text(text).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled) }
                            NavigationLink("核验并打开原生详情") { JRMovieRoute(video: detail) }
                            if let url = URL(string: path, relativeTo: source.base)?.absoluteURL { Link("在外部浏览器查看来源页", destination: url).font(.footnote) }
                        }.padding(.horizontal, AdaptiveLayout.horizontalPadding)
                    }
                    if !page.videos.isEmpty {
                        Text(isPreview ? "首批 \(page.videos.count) 部 · 正在读取完整榜单" : "\(page.videos.count) 部公开影片（来源顺序）").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                        JRPosterGrid(videos: Array(page.videos.prefix(limit)))
                        if limit < page.videos.count { Button("加载更多") { state.limit += 12 }.accessibilityIdentifier("jr-load-more").frame(maxWidth: .infinity).padding() }
                    }
                    if !page.links.isEmpty {
                        if page.videos.isEmpty { sourceNavigation(page) }
                        else {
                            DisclosureGroup("来源导航 / 人物 / 榜单（\(page.links.count)）") { sourceNavigation(page) }.padding(.horizontal)
                        }
                    }
                    ForEach(Array(page.paragraphs.enumerated()), id: \.offset) { _, text in Text(text).font(.subheadline).textSelection(.enabled).padding(.horizontal, AdaptiveLayout.horizontalPadding) }
                    if !page.images.isEmpty {
                        DisclosureGroup("公开图片（\(page.images.count)）") {
                            ForEach(page.images, id: \.self) { image in JavDBImage(url: image).aspectRatio(4/3, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12)) }
                        }.padding(.horizontal)
                    }
                    if !page.magnets.isEmpty {
                        DisclosureGroup("公开磁链（只读，不提交离线任务）") {
                            ForEach(page.magnets, id: \.self) { magnet in Text(magnet).font(.caption2.monospaced()).textSelection(.enabled).lineLimit(4).padding(.vertical, 4) }
                        }.padding(.horizontal)
                    }
                    if let next = page.next { NavigationLink("来源下一页") { JRPageView(path: next) }.padding() }
                    if page.videos.isEmpty && page.detail == nil && page.paragraphs.isEmpty && page.links.isEmpty { ContentUnavailableView("没有可读取的公开资料", systemImage: "doc.text", description: Text("此页可能依赖网站脚本或已变更，未伪造内容。")) }
                }
            }.padding(.vertical).frame(maxWidth: AdaptiveLayout.contentMaxWidth).frame(maxWidth: .infinity)
        }.scrollPosition(id: $state.anchor, anchor: .top)
        .background { LiquidGlassBackground() }
        .navigationTitle(page?.title ?? "JAV Ranking").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .onReceive(source.$previews) { previews in
            if page == nil, let preview = previews[path] { state.page = preview; state.isPreview = true }
        }
        .refreshable { await load(refresh: true) }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink { JavRankingSettingsView() } label: { Image(systemName: "gearshape") } } }
    }
    private func sourceNavigation(_ page: JRPage) -> some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            Text(page.detail == nil ? "来源分类 / 人物 / 榜单导航" : "演员 / 片商 / 导演 / 入榜记录").font(.headline)
            ForEach(page.links) { link in
                NavigationLink { JRPageView(path: link.path) } label: {
                    HStack { Text(link.title).multilineTextAlignment(.leading); Spacer(); Image(systemName: "chevron.right").font(.caption) }.padding(.vertical, 4)
                }
            }
        }.padding(.horizontal, AdaptiveLayout.horizontalPadding)
    }
    private func load(refresh: Bool = false) async {
        let epoch = source.generation
        // SwiftUI restarts .task when returning from a pushed detail. That is
        // visibility, not invalidation: preserve loaded count, order and anchor.
        if !refresh, state.loadedGeneration == epoch, page != nil, !isPreview { return }
        if state.loadedGeneration != epoch {
            state.page = source.cachedPage(path); state.isPreview = false
            state.limit = 12; state.anchor = nil
        }
        state.loadedGeneration = epoch
        state.error = ""; state.loading = page == nil
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--jr-navigation-fixture") {
            state.page = JRPage(title: "Neutral ranking", videos: (1...60).map {
                JRVideo(path: "/neutral/\($0)/", code: "TEST-\($0)", title: "Neutral film \($0)", image: "fixture://poster/\($0)", rank: $0)
            })
            state.isPreview = false; state.loading = false
            return
        }
        #endif
        do {
            let result = try await source.page(path, refresh: refresh)
            guard epoch == source.generation, !Task.isCancelled else { return }; state.page = result; state.isPreview = false
        } catch { if epoch == source.generation && !Task.isCancelled { state.error = error.localizedDescription } }
        if epoch == source.generation { state.loading = false }
    }

}

// One gateway for every source movie entry. Only a verified JavDB identity may
// instantiate the application's existing detail (including its 115 actions).
struct JRMovieRoute: View {
    let video: JRVideo
    @ObservedObject private var source = JavRankingSource.shared
    @State private var movie: Movie?
    @State private var message = ""
    @State private var loading = true
    @State private var attempt = 0
    private var code: String { JRPolicy.exactCode(video.code) != nil ? video.code : (JRPolicy.catalogueCode(video.title) ?? "") }
    var body: some View {
        Group {
            if let movie = movie ?? source.cachedMovie(code: code) {
                MovieDetailView(movieID: movie.id)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink { JRPageView(path: video.path, sourceOnly: true) } label: { Image(systemName: "info.circle") }
                            .accessibilityLabel("榜单来源资料（辅助）")
                    } }
            } else {
                VStack(spacing: 16) {
                    Text(code.isEmpty ? "来源未提供可核验的完整番号" : code).font(.headline)
                    if loading { ProgressView("正在核验 JavDB 完整番号…") }
                    else {
                        Text(message).font(.callout).multilineTextAlignment(.center)
                        Button("重试核验") { attempt += 1 }
                    }
                    NavigationLink("来源资料（辅助，只读）") { JRPageView(path: video.path, sourceOnly: true) }
                }.padding().navigationTitle("影片核验")
            }
        }
        .task(id: "\(source.generation):\(attempt):\(video.path)") {
            let epoch = source.generation, request = attempt
            loading = true; message = ""
            // A known verified ID already renders MovieDetailView above. Do not
            // tear down that identity just because SwiftUI restarts this task.
            if attempt == 0, let known = source.cachedMovie(code: code) {
                movie = known; loading = false
                return
            }
            movie = nil
            defer { if epoch == source.generation, request == attempt { loading = false } }
            guard !code.isEmpty else { message = "不能从标题猜测影片；请查看来源资料。"; return }
            do {
                let match = try await source.matchedMovie(code: code, refresh: attempt > 0, interactive: true)
                guard !Task.isCancelled, epoch == source.generation, request == attempt else { return }
                movie = match
                if match == nil { message = "原生影片搜索前 3 页未找到番号 \(code) 的有效 ID 精确结果（不代表影片不存在）。请重试或在原生搜索中核对；不会自动打开辅助来源详情。" }
            } catch {
                guard !Task.isCancelled, epoch == source.generation, request == attempt else { return }
                message = "番号 \(code) 核验失败：" + error.localizedDescription
            }
        }
        .onDisappear { source.cancelMappings() }
    }
}

// Native cache UI: ordered sections; source media is never used as native metadata.
struct JRBackendView: View {
    let route: String
    var title: String = "JAV Ranking"
    var fixedQuery: [URLQueryItem] = []
    @ObservedObject private var backend = JRBackendClient.shared
    @State private var envelope: JRBackendEnvelope?
    @State private var error = ""
    @State private var loading = false
    @State private var page = 1
    @State private var query = ""
    @State private var submitted = ""
    @State private var category = ""
    @State private var year = ""
    @State private var sort = "source"
    @State private var attempt = 0
    @State private var pick: JRBackendVideo?
    private var requestKey: String { "\(backend.generation):\(route):\(page):\(submitted):\(category):\(year):\(sort):\(attempt)" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if route == "home" {
                    NavigationLink("全部榜单") { JRBackendView(route: "topics", title: "全部榜单") }
                    NavigationLink("片库与分类") { JRBackendView(route: "explore", title: "片库与分类") }
                    NavigationLink("番号 / 人物姓名与别名搜索") { JRBackendView(route: "index", title: "索引搜索") }
                }
                if backend.endpoint == nil {
                    Text("JAV Ranking 后端尚未配置").font(.headline)
                    Text("默认复用与 JAVLibrary 相同的外部数据库。请先在外部数据库设置中启用服务并保存 API 令牌；也可选择独立受信 HTTPS 后端。未配置不是空榜单，不匿名回退或自动请求原站。")
                    NavigationLink("配置外部数据库或独立 HTTPS") { JavRankingSettingsView() }
                }
                if route == "index" {
                    TextField("完整番号或人物姓名 / 别名", text: $query).textFieldStyle(.roundedBorder)
                    Button("搜索索引") { submitted = query; page = 1 }
                    Text("索引不支持影片标题全文；人物候选仅保留来源路径，不自动认领第一个原生演员。") .font(.caption).foregroundStyle(.secondary)
                }
                if route == "explore" {
                    HStack {
                        TextField("分类 ID（0 有效）", text: $category).keyboardType(.numberPad)
                        TextField("年份", text: $year).keyboardType(.numberPad)
                    }.textFieldStyle(.roundedBorder)
                    Picker("排序", selection: $sort) { Text("来源顺序").tag("source"); Text("发行日期").tag("date"); Text("评分").tag("score") }
                        .pickerStyle(.segmented)
                    if let categories = envelope?.data?.categories {
                        Menu("选择分类") {
                            Button("全部") { category = ""; page = 1 }
                            ForEach(categories, id: \.id) { cat in Button(cat.name) { category = String(cat.id); page = 1 } }
                        }
                    }
                }
                if loading { ProgressView("读取缓存…") }
                if !error.isEmpty { Text(error).foregroundStyle(.orange); Button("重试") { attempt += 1 } }
                if let envelope {
                    Text(envelope.notice).font(.caption).foregroundStyle(envelope.stale ? .orange : .secondary)
                    if let payload = envelope.data { payloadView(payload) }
                    else { Text("尚无成功快照，已显示真实排队 / 退避状态；请稍后手动重试。"); Button("重新读取") { attempt += 1 } }
                }
            }.padding()
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink { JavRankingSettingsView() } label: { Image(systemName: "gearshape") } } }
        .task(id: requestKey) { await load() }
        .onChange(of: backend.generation) { _, _ in envelope = nil; pick = nil; error = ""; page = 1 }
        .onChange(of: category) { _, _ in page = 1 }
        .onChange(of: year) { _, _ in page = 1 }
        .onChange(of: sort) { _, _ in page = 1 }
        .refreshable { attempt += 1 }
    }
    @ViewBuilder private func payloadView(_ payload: JRBackendPayload) -> some View {
        if let sections = payload.sections {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 12) {
                    Text(section.label).font(.title3.bold())
                    if section.id == "pick" {
                        Button("从已缓存首页预览中随机抽选（非来源算法）") {
                            pick = sections.flatMap { $0.items ?? [] }.randomElement()
                        }
                        if let pick { JRBackendFilmCell(item: pick) }
                    }
                    links(section.links)
                    if let items = section.items { films(items) }
                    if let actors = section.actors { entities(actors) }
                }
            }
        }
        if let topics = payload.topics { links(topics) }
        if let links = payload.links { self.links(links) }
        if let items = payload.items { films(items) }
        if let entities = payload.entities { self.entities(entities) }
        if let total = payload.total { Text("索引共 \(total) 项 · 第 \(payload.page ?? page) 页").font(.caption) }
        HStack {
            if page > 1 { Button("上一页") { page -= 1 } }
            if payload.nextPage != nil { Button("下一页") { page = payload.nextPage! } }
            if let next = payload.nextSourcePath {
                NavigationLink("来源下一页（分页差异尚未实测）") { JRBackendView(route: "page", title: title, fixedQuery: [.init(name: "path", value: next)]) }
            }
        }
    }
    private func films(_ items: [JRBackendVideo]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 12)], spacing: 18) {
            // Offset identity intentionally preserves duplicates and original ranks.
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in JRBackendFilmCell(item: item) }
        }
    }
    private func links(_ values: [JRBackendLink]) -> some View {
        ForEach(Array(values.enumerated()), id: \.offset) { _, link in
            NavigationLink(link.topic ?? link.sourcePath) {
                if link.sourcePath == "/zh-hans/rankings/" { JRBackendView(route: "topics", title: "全部榜单") }
                else if let topic = link.topic { JRBackendView(route: "rankings", title: topic, fixedQuery: [.init(name: "topic", value: topic)]) }
                else { JRBackendView(route: "page", title: "来源集合", fixedQuery: [.init(name: "path", value: link.sourcePath)]) }
            }
        }
    }
    private func entities(_ values: [JRBackendEntity]) -> some View {
        ForEach(Array(values.enumerated()), id: \.offset) { _, entity in
            VStack(alignment: .leading) {
                NavigationLink(entity.name) { JRBackendView(route: "page", title: entity.name, fixedQuery: [.init(name: "path", value: entity.sourcePath)]) }
                Text("来源身份 · \(entity.sourcePath)").font(.caption2).foregroundStyle(.secondary)
                if let aliases = entity.aliases, !aliases.isEmpty { Text(aliases.joined(separator: " / ")).font(.caption) }
                if let items = entity.items { films(items) }
            }
        }
    }
    private func load() async {
        guard backend.endpoint != nil else { envelope = nil; return }
        let key = requestKey; loading = true; error = ""
        var args = fixedQuery
        if route == "explore" || route == "index" {
            args += [.init(name: "page", value: String(page)), .init(name: "limit", value: "20")]
        }
        if route == "index" { args += [.init(name: "kind", value: "search"), .init(name: "q", value: submitted)] }
        if route == "explore" {
            args += [.init(name: "sort", value: sort)]
            if !category.isEmpty { args.append(.init(name: "cat", value: category)) }
            if !year.isEmpty { args.append(.init(name: "year", value: year)) }
        }
        do {
            let result = try await backend.fetch(route, query: args)
            guard !Task.isCancelled, key == requestKey else { return }
            envelope = result
        } catch {
            guard !Task.isCancelled, key == requestKey else { return }
            self.error = error.localizedDescription
        }
        if key == requestKey { loading = false }
    }
}

private struct JRBackendFilmCell: View {
    let item: JRBackendVideo
    @ObservedObject private var source = JavRankingSource.shared
    @State private var movie: Movie?
    @State private var message = "等待原生核验"
    @State private var attempt = 0
    @State private var accountEpoch = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let movie {
                NavigationLink { MovieDetailView(movieID: movie.id) } label: { MoviePosterCard(movie: movie) }.buttonStyle(.plain)
            } else {
                RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.12))
                    .aspectRatio(0.70, contentMode: .fit)
                    .overlay { VStack { Image(systemName: "film"); Text(item.number).font(.caption); Text(message).font(.caption2).multilineTextAlignment(.center) }.padding(8) }
                Button("重试完整番号核验") { attempt += 1 }.font(.caption)
            }
            if let rank = item.rank { Text("来源排名 #\(rank)").font(.caption) }
            Text(item.number).font(.caption).foregroundStyle(.secondary)
        }
        .task(id: "\(source.generation):\(accountEpoch):\(attempt):\(item.sourcePath)") {
            let account = APIClient.shared.token
            movie = nil; message = "核验中…"
            do {
                let found = try await source.matchedMovie(code: item.number, refresh: attempt > 0)
                guard !Task.isCancelled, account == APIClient.shared.token else { return }
                movie = found; message = found == nil ? "未找到唯一精确结果" : "已核验"
            } catch {
                guard !Task.isCancelled, account == APIClient.shared.token else { return }
                message = "核验失败，可重试"
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .avdbCatalogAccountChanged)) { _ in
            movie = nil; accountEpoch += 1; source.cancelMappings()
        }
    }
}
