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
            if adultConfirmed {
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
    @State private var randomBatch: [JRBackendVideo]?
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var contentWidth: CGFloat = 350
    private var requestKey: String { "\(backend.generation):\(route):\(page):\(submitted):\(category):\(year):\(sort):\(attempt)" }
    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                masthead.id("jr-home-top")
                if route == "home" {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { homeActions }
                        VStack(alignment: .leading, spacing: 8) { homeActions }
                    }
                }
                if backend.endpoint == nil && !JRDesignFixture.enabled {
                    Text("JAV Ranking 后端尚未配置").font(.headline)
                    Text("默认复用与 JAVLibrary 相同的外部数据库。请先在外部数据库设置中启用服务并保存 API 令牌；也可选择独立受信 HTTPS 后端。未配置不是空榜单，不匿名回退或自动请求原站。")
                    NavigationLink("配置外部数据库或独立 HTTPS") { JavRankingSettingsView() }
                }
                if route == "index" {
                    TextField("完整番号或人物姓名 / 别名", text: $query).textFieldStyle(.roundedBorder)
                    Button("搜索索引") { submitted = query; page = 1 }.buttonStyle(.bordered).controlSize(.large)
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
                if !error.isEmpty { Text(error).foregroundStyle(.orange); Button("重试") { attempt += 1 }.buttonStyle(.bordered).controlSize(.large) }
                if let envelope {
                    DisclosureGroup("缓存状态 · \(envelope.status)") {
                        Text(envelope.notice).font(.caption).foregroundStyle(JRPalette.muted).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }.font(.caption).tint(JRPalette.gold).padding(12).background(JRPalette.panel, in: RoundedRectangle(cornerRadius: 10))
                    if let payload = envelope.data {
                        payloadView(payload)
                        if route == "home" {
                            homeFooter
                            Button("回到顶部 ↑") { withAnimation { proxy.scrollTo("jr-home-top", anchor: .top) } }
                                .frame(minHeight: 44).accessibilityIdentifier("jr-scroll-top")
                        }
                    }
                    else { Text("尚无成功快照，已显示真实排队 / 退避状态；请稍后手动重试。"); Button("重新读取") { attempt += 1 }.buttonStyle(.bordered).controlSize(.large) }
                }
            }.padding()
                .frame(maxWidth: 1100, alignment: .leading)
                .background { GeometryReader { g in Color.clear.preference(key: JRWidthKey.self, value: max(0, g.size.width - 32)) } }
                .onPreferenceChange(JRWidthKey.self) { if $0 > 0 { contentWidth = $0 } }
                .frame(maxWidth: .infinity)
        }
        .background(JRPalette.background.ignoresSafeArea())
        .foregroundStyle(JRPalette.ink).tint(JRPalette.gold)
        .preferredColorScheme(.dark) // Route-scoped preference; no persistent app appearance mutation.
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(JRPalette.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink { JavRankingSettingsView() } label: { Image(systemName: "gearshape") } } }
        .task(id: requestKey) { await load() }
        .onChange(of: backend.generation) { _, _ in envelope = nil; pick = nil; randomBatch = nil; error = ""; page = 1 }
        .onChange(of: category) { _, _ in page = 1 }
        .onChange(of: year) { _, _ in page = 1 }
        .onChange(of: sort) { _, _ in page = 1 }
        .refreshable { attempt += 1 }
        }
    }
    private var masthead: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("JAV Ranking").font(.largeTitle.weight(.black)).foregroundStyle(JRPalette.gold)
            Text(route == "home" ? "发现 · 榜单 · 原生片库" : title).font(.title2.bold())
            Text("来源顺序与排名 · 完整番号核验后打开 AVDB")
                .font(.caption).foregroundStyle(JRPalette.muted)
            Rectangle().fill(JRPalette.border).frame(height: 1).padding(.top, 8)
        }.accessibilityIdentifier("jr-native-masthead")
    }
    @ViewBuilder private var homeActions: some View {
        NavigationLink { JRBackendView(route: "topics", title: "全部榜单") } label: { Label("全部榜单", systemImage: "chart.bar.xaxis").frame(minHeight: 45).contentShape(Rectangle()) }.buttonStyle(.plain).foregroundStyle(JRPalette.gold).accessibilityIdentifier("jr-open-topics")
        NavigationLink { JRBackendView(route: "explore", title: "片库与分类") } label: { Label("片库分类", systemImage: "square.grid.2x2").frame(minHeight: 45).contentShape(Rectangle()) }.buttonStyle(.plain).foregroundStyle(JRPalette.gold)
        NavigationLink { JRBackendView(route: "index", title: "索引搜索") } label: { Label("搜索", systemImage: "magnifyingglass").frame(minHeight: 45).contentShape(Rectangle()) }.buttonStyle(.plain).foregroundStyle(JRPalette.gold)
    }
    @ViewBuilder private func payloadView(_ payload: JRBackendPayload) -> some View {
        if let sections = payload.sections {
            ForEach(Array(JRHomePresentation.orderedSections(sections).enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 14) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(sectionTitle(section)).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 10)
                            sectionAction(section, sections: sections)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sectionTitle(section)).font(.title2.bold())
                            sectionAction(section, sections: sections)
                        }
                    }
                    Rectangle().fill(JRPalette.border).frame(height: 1)
                    if section.id == "weekly" || section.id == "monthly" {
                        Text(section.id == "weekly" ? "来源每周热榜 · 快照时间见缓存状态" : "来源每月热榜 · 月份取自来源路径")
                            .font(.caption).foregroundStyle(JRPalette.muted)
                    }
                    if section.id == "pick" { luckyHero(sections) }
                    if section.kind == "topics" || section.id == "rankings" { links(section.links) }
                    if section.id == "pick", let pick { JRBackendFilmCell(item: pick, rankContext: section.label) }
                    if let items = section.items {
                        let displayed = section.id == "random" ? (randomBatch ?? items) : items
                        Text("当前预览 \(displayed.count) 部 · " + (section.id == "random" && randomBatch != nil ? "缓存随机" : "来源顺序")).font(.caption).foregroundStyle(JRPalette.muted)
                        films(displayed, context: section.label)
                    }
                    if let actors = section.actors { entities(actors) }
                }.padding(.top, 12).accessibilityIdentifier("jr-section-\(section.id)")
            }
        }
        if let topics = payload.topics { links(topics) }
        if let links = payload.links { self.links(links) }
        if let items = payload.items { films(items, context: title) }
        if let entities = payload.entities { self.entities(entities) }
        if let total = payload.total { Text("索引共 \(total) 项 · 第 \(payload.page ?? page) 页").font(.caption) }
        HStack {
            if page > 1 { Button("上一页") { page -= 1 } }
            if let next = payload.nextPage { Button("下一页") { page = next } }
            if let next = payload.nextSourcePath {
                NavigationLink("来源下一页") { JRBackendView(route: "page", title: title, fixedQuery: [.init(name: "path", value: next)]) }
            }
        }.buttonStyle(.bordered).controlSize(.large)
    }
    private func sectionTitle(_ section: JRBackendSection) -> String {
        if section.id == "monthly", let link = section.links.first {
            return "DMM 月度热销 · " + JRTopicStyle(path: link.sourcePath).period
        }
        return section.label
    }
    @ViewBuilder private func sectionAction(_ section: JRBackendSection, sections: [JRBackendSection]) -> some View {
        if section.id == "random" {
            Button("换一批") {
                let pool = cachedPool(sections)
                randomBatch = Array(pool.shuffled().prefix(section.items?.count ?? 8))
            }.frame(minWidth: 45, minHeight: 45)
                .accessibilityIdentifier("jr-random-refresh")
                .accessibilityHint("仅从去重的已缓存首页影片池随机抽选，不是来源算法")
        } else if let link = JRHomePresentation.moreLink(section) {
            NavigationLink { linkDestination(link) } label: {
                Label("更多", systemImage: "arrow.right").font(.subheadline.weight(.semibold)).frame(minWidth: 45, minHeight: 45).contentShape(Rectangle()).foregroundStyle(JRPalette.gold)
            }.accessibilityIdentifier("jr-more-\(section.id)")
        }
    }
    private func cachedPool(_ sections: [JRBackendSection]) -> [JRBackendVideo] {
        JRHomePresentation.cachedPool(sections)
    }
    private func luckyHero(_ sections: [JRBackendSection]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ForEach(["sparkles", "film.stack", "shuffle"], id: \.self) { symbol in
                    Image(systemName: symbol).font(.largeTitle).frame(maxWidth: .infinity, minHeight: 72)
                        .background(JRPalette.background, in: RoundedRectangle(cornerRadius: 14))
                        .rotationEffect(.degrees(symbol == "film.stack" ? 8 : -6))
                }
            }.foregroundStyle(JRPalette.gold).accessibilityHidden(true)
            Text("不再纠结，从当前已缓存的榜单与代表作品中寻找今晚目标。")
                .fixedSize(horizontal: false, vertical: true)
            Text("原生影片资料 · 完整番号核验 · 不复制来源抽签算法")
                .font(.caption).foregroundStyle(JRPalette.muted)
            Button { pick = cachedPool(sections).randomElement() } label: {
                Label(pick == nil ? "立即开抽" : "再抽一部", systemImage: "shuffle")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
            }.buttonStyle(.borderedProminent).tint(JRPalette.gold).foregroundStyle(.black)
                .accessibilityIdentifier("jr-lucky-start")
            Text("缓存池 \(cachedPool(sections).count) 部；随机结果不是来源站的推荐算法。")
                .font(.caption).foregroundStyle(JRPalette.muted)
        }.padding(18).background(JRPalette.panel, in: RoundedRectangle(cornerRadius: 18))
    }
    private var homeFooter: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle().fill(JRPalette.border).frame(height: 1)
            Text("JAV Ranking · 来源与导航").font(.title2.bold()).foregroundStyle(JRPalette.gold)
            Text("本页使用来源缓存的顺序、排名与可用数值。影片封面、演员与片名来自您配置的原生资料库；战力积分不等于 AVDB 评分。缓存暂缺的字段不推算、不补造。")
                .font(.footnote).foregroundStyle(JRPalette.muted)
            homeActions
            NavigationLink("神作总榜") { JRBackendView(route: "page", title: "神作总榜", fixedQuery: [.init(name: "path", value: "/zh-hans/most-awarded-videos/")]) }
            NavigationLink("女优总榜") { JRBackendView(route: "page", title: "女优总榜", fixedQuery: [.init(name: "path", value: "/zh-hans/most-awarded-actors/")]) }
            NavigationLink("男优总榜") { JRBackendView(route: "page", title: "男优总榜", fixedQuery: [.init(name: "path", value: "/zh-hans/most-awarded-male-actors/")]) }
            ForEach([("来源首页", ""), ("使用指南", "help/"), ("战力算法", "algorithm/"), ("产品与生态", "ecosystem/"), ("防迷路 / 来源域名", "domains/"), ("标记说明", "marks/"), ("关于来源", "about/"), ("反馈", "feedback/"), ("浏览器扩展", "extension/"), ("隐私政策", "privacy/"), ("使用条款", "terms/"), ("商业合作说明", "sponsor/")], id: \.1) { item in
                if let url = URL(string: "zh-hans/" + item.1, relativeTo: JavRankingSource.shared.base) {
                    Link(item.0 + " · 来源网页 ↗", destination: url).frame(minHeight: 44)
                }
            }
            Text("原创原生布局；不镜像来源图片、露骨简介、广告、赞助位或商业宣传。外部信息链接仅打开来源，不携带外部库令牌。")
                .font(.caption).foregroundStyle(JRPalette.muted)
        }.padding(.top, 24).accessibilityIdentifier("jr-home-footer")
    }
    private func films(_ items: [JRBackendVideo], context: String) -> some View {
        LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: min(contentWidth, 350)), spacing: 16)], spacing: 14) {
            // Offset identity intentionally preserves duplicates and original ranks.
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in JRBackendFilmCell(item: item, rankContext: context) }
        }
    }
    private func links(_ values: [JRBackendLink]) -> some View {
        JRTopicGrid(values: values.filter { $0.sourcePath != "/zh-hans/rankings/" })
    }
    @ViewBuilder private func linkDestination(_ link: JRBackendLink) -> some View {
        JRCollectionDestination(link: link)
    }
    private func entities(_ values: [JRBackendEntity]) -> some View {
        ForEach(Array(values.enumerated()), id: \.offset) { _, entity in
            VStack(alignment: .leading, spacing: 12) {
                RankingActorMatchLink(entity: entity)
                NavigationLink { JRBackendView(route: "page", title: entity.name, fixedQuery: [.init(name: "path", value: entity.sourcePath)]) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle").font(.title).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entity.name).font(.headline)
                            Text(entity.score.map { "来源战力总分：" + String(format: "%.0f", $0) } ?? "当前缓存未包含战力总分").font(.caption).foregroundStyle(JRPalette.gold)
                            Text("来源人物集合 · 作品更多").font(.caption).foregroundStyle(JRPalette.muted)
                        }
                        Spacer(); Image(systemName: "arrow.up.right")
                    }.frame(minHeight: 44)
                }.buttonStyle(.plain)
                if let aliases = entity.aliases, !aliases.isEmpty { Text(aliases.joined(separator: " / ")).font(.caption).foregroundStyle(JRPalette.muted) }
                if let items = entity.items {
                    Text("代表作品预览 \(items.count) 部").font(.caption).foregroundStyle(JRPalette.muted)
                    films(items, context: "\(entity.name) · 作品内来源排名")
                }
            }.padding(12).background(JRPalette.panel, in: RoundedRectangle(cornerRadius: 12))
        }
    }
    private func load() async {
        #if DEBUG
        if JRDesignFixture.enabled { envelope = JRDesignFixture.envelope(route: route); return }
        #endif
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

private struct RankingActorMatchLink: View {
    let entity: JRBackendEntity
    @State private var actor: Actor?
    @State private var message = "尚未核验 AVDB 演员身份"
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let actor {
                NavigationLink { ActorDetailView(actorID: actor.id) } label: {
                    Label("AVDB 演员资料", systemImage: "person.crop.circle")
                }.accessibilityIdentifier("jr-actor-\(entity.sourceID)")
            }
            Text(message).font(.caption).foregroundStyle(JRPalette.muted)
        }
        .task(id: entity.sourcePath) {
            let identity = ExternalActorIdentity.resolve(sourceName: entity.name, aliases: entity.aliases ?? [], catalog: .bundled())
            guard identity.queries.count <= 4 else { message = "别名过多，保留来源人物页"; return }
            do {
                let match = try await ExternalActorResolver.resolve(identity: identity) { name, page in
                    try await JavDBSDK.shared.searchActors(keyword: name, page: page, limit: 20)
                }
                actor = match?.actor
                message = match == nil ? "未唯一匹配；来源名次与人物页保留" : "已核验唯一 AVDB 演员"
            } catch is CancellationError {
                return
            } catch {
                message = "演员核验失败；来源人物页保留"
            }
        }
    }
}

private struct JRBackendFilmCell: View {
    let item: JRBackendVideo
    var rankContext: String = "来源集合"
    @ObservedObject private var source = JavRankingSource.shared
    @State private var movie: Movie?
    @State private var message = "等待原生核验"
    @State private var attempt = 0
    @State private var accountEpoch = 0
    var body: some View {
        Group {
            if let movie {
                NavigationLink { MovieDetailView(movieID: movie.id) } label: { JRFilmArtwork(item: item, movie: movie, message: message, rankContext: rankContext) }.buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    JRFilmArtwork(item: item, movie: nil, message: message, rankContext: rankContext)
                    Button { attempt += 1 } label: { Text("重试完整番号核验").font(.caption).frame(minHeight: 45).contentShape(Rectangle()) }.padding(.horizontal, 12)
                }
            }
        }
        .background(JRPalette.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(JRPalette.border, lineWidth: 1) }
        .accessibilityIdentifier("jr-film-\(item.sourceID)")
        .task(id: "\(source.generation):\(accountEpoch):\(attempt):\(item.sourcePath)") {
            #if DEBUG
            if JRDesignFixture.enabled { movie = JRDesignFixture.movie(item); message = "已核验 · 中性测试"; return }
            #endif
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

// Original native typography and gradients; no source artwork, CSS, logo or sponsor UI.
private enum JRPalette {
    static let background = Color(red: 0.055, green: 0.061, blue: 0.075)
    static let panel = Color(red: 0.095, green: 0.102, blue: 0.12)
    static let border = Color.white.opacity(0.16)
    static let gold = Color(red: 1, green: 0.73, blue: 0.27)
    static let ink = Color(red: 0.96, green: 0.95, blue: 0.92)
    static let muted = Color(red: 0.72, green: 0.73, blue: 0.76)
}

private struct JRFilmArtwork: View {
    let item: JRBackendVideo
    let movie: Movie?
    let message: String
    let rankContext: String
    @Environment(\.dynamicTypeSize) private var typeSize
    private var imageWidth: CGFloat { typeSize.isAccessibilitySize ? 92 : 144 }
    private var actorText: String {
        let names = movie?.actorNames ?? movie?.actors?.compactMap(\.name) ?? []
        return names.isEmpty ? "演员资料暂缺" : names.joined(separator: " · ")
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Color.clear.frame(width: imageWidth).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.number).font(.headline).foregroundStyle(JRPalette.gold).fixedSize(horizontal: false, vertical: true)
                Text(item.score.map { "来源战力：" + String(format: "%.0f 分", $0) } ?? "来源未提供战力积分").font(.caption).foregroundStyle(JRPalette.muted)
                Text(actorText).font(.caption.weight(.semibold)).foregroundStyle(JRPalette.gold).fixedSize(horizontal: false, vertical: true)
                Text(movie?.title?.isEmpty == false ? movie!.title! : "原生影片资料暂缺")
                    .font(.subheadline).foregroundStyle(JRPalette.ink).fixedSize(horizontal: false, vertical: true)
                if let synopsis = movie?.summary ?? movie?.desc, !synopsis.isEmpty, synopsis != movie?.title {
                    Text(synopsis).font(.caption).foregroundStyle(JRPalette.muted).fixedSize(horizontal: false, vertical: true)
                }
                Text(item.rank.map { "来源 #\($0) · \(movie == nil ? "待核验" : "已核验")" } ?? "来源未提供排名")
                    .font(.caption2).foregroundStyle(JRPalette.muted).fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(item.rank.map { "\(rankContext)，来源排名第 \($0)" } ?? "来源未提供排名")
                if movie == nil { Text(message).font(.caption2).foregroundStyle(JRPalette.muted) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8).padding(.trailing, 10)
        }.frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(alignment: .leading) {
            GeometryReader { geometry in
                Group {
                    if let movie {
                        // Own native landscape cover, never source artwork or source title fallback.
                        JavDBImage(url: movie.coverURL, fallbackURL: movie.thumbURL, contentMode: .fill, maxPixelSize: 600, frontPoster: false)
                    } else {
                        Rectangle().fill(JRPalette.border).overlay { Image(systemName: "film").font(.title).foregroundStyle(JRPalette.muted) }
                    }
                }.frame(width: imageWidth, height: geometry.size.height).clipped()
            }.frame(width: imageWidth).accessibilityHidden(true)
        }
        .overlay(alignment: .topLeading) {
            if let rank = item.rank {
                Text("#\(rank)").font(.caption.bold()).foregroundStyle(JRPalette.background)
                    .padding(.horizontal, 7).padding(.vertical, 6).background(JRPalette.gold, in: UnevenRoundedRectangle(topLeadingRadius: 11, bottomTrailingRadius: 8)).accessibilityHidden(true)
            }
        }.clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct JRCollectionDestination: View {
    let link: JRBackendLink
    var body: some View {
        Group {
            if link.sourcePath == "/zh-hans/rankings/" { JRBackendView(route: "topics", title: "全部榜单") }
            else if let topic = link.topic { JRBackendView(route: "rankings", title: JRTopicStyle(path: link.sourcePath).label, fixedQuery: [.init(name: "topic", value: topic)]) }
            else { JRBackendView(route: "page", title: JRTopicStyle(path: link.sourcePath).label, fixedQuery: [.init(name: "path", value: link.sourcePath)]) }
        }
    }
}
private struct JRTopicGrid: View {
    let values: [JRBackendLink]
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var width: CGFloat = 360
    private var tileWidth: CGFloat { typeSize.isAccessibilitySize ? width : max(0, (width - 12) / 2) }
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, link in
                NavigationLink { JRCollectionDestination(link: link) } label: { JRTopicTile(style: JRTopicStyle(path: link.sourcePath), width: tileWidth) }.buttonStyle(.plain)
            }
        }.accessibilityIdentifier("jr-topic-grid")
        .background { GeometryReader { g in Color.clear.preference(key: JRTopicWidthKey.self, value: g.size.width) } }
        .onPreferenceChange(JRTopicWidthKey.self) { if $0 > 0 { width = $0 } }
    }
}
private struct JRTopicWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 360
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
private struct JRTopicTile: View {
    let style: JRTopicStyle
    let width: CGFloat
    private var accent: Color {
        switch style.family {
        case "DMM": return Color(red: 0.73, green: 0.25, blue: 0.15)
        case "JAVDB": return Color(red: 0.16, green: 0.28, blue: 0.67)
        case "JAVLIBRARY": return Color(red: 0.48, green: 0.12, blue: 0.23)
        default: return Color(red: 0.46, green: 0.34, blue: 0.13)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Rectangle().fill(JRPalette.gold).frame(width: 5, height: 16); Text("RANKING ARCHIVE").font(.caption2.weight(.bold)); Spacer(minLength: 0) }
            Text(style.family).font(width > 300 ? .largeTitle.weight(.black) : .title3.weight(.black)).fontWidth(.condensed).fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(JRPalette.ink.opacity(0.45)).frame(height: 1)
            Text(style.edition).font(width > 300 ? .title2.weight(.heavy) : .headline.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
            HStack { Text(style.period).font(.caption.weight(.medium)); Spacer(minLength: 0); Image(systemName: "arrow.up.right") }
        }
        .foregroundStyle(JRPalette.ink).padding(12).frame(maxWidth: .infinity, minHeight: max(125, width / 1.55), alignment: .leading)
        .background(LinearGradient(colors: [accent, accent.opacity(0.38), JRPalette.panel], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(JRPalette.ink.opacity(0.24), lineWidth: 1) }
        .accessibilityElement(children: .ignore).accessibilityLabel(style.label)
    }
}

// Runtime fixtures exercise the shipping views and card components, without any
// cache transport, source requests, real identities, or explicit images.
private enum JRDesignFixture {
    static var enabled: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--jr-design-fixture")
        #else
        return false
        #endif
    }
    #if DEBUG
    static func movie(_ item: JRBackendVideo) -> Movie {
        let bytes = """
        {"id":"neutral-\(item.order)","number":"\(item.number)","title":"光影档案 · 城市与旅途的中性测试影片","actor_names":["示例演员 A","示例演员 B"],"thumb_url":"fixture://poster/wrap","cover_url":"fixture://poster/wrap"}
        """.data(using: .utf8)!
        return (try? JSONDecoder().decode(Movie.self, from: bytes)) ?? Movie(id: "neutral", number: item.number, title: "中性测试影片")
    }
    static func envelope(route: String) -> JRBackendEnvelope {
        let slugs = ["dmm-weekly", "dmm-monthly-2024-09", "javdb-top250", "javlibrary-top250", "javdb-uncensored-top250", "javdb-fc2-top250", "javdb-top250-2023", "dmm-monthly-2023-12"] + (2013...2022).map { "javdb-top250-\($0)" }
        let links = slugs.map { JRBackendLink(sourcePath: "/zh-hans/rankings/\($0)/", kind: "ranking", topic: $0) }
        let items = (1...8).map { JRBackendVideo(sourceID: "neutral-\($0)", sourcePath: "/neutral/videos/\($0)/", number: "TEST-00\($0)", exactNumber: "TEST00\($0)", score: Double(1000 + $0), rank: [75, 10, 42, 9, 8, 7, 6, 5][$0-1], order: $0) }
        let ids = ["pick", "random", "rankings", "weekly", "monthly", "awarded", "actors"]
        let labels = ["今天冲哪个？", "随机神作推荐", "查看全部排行榜", "DMM 本周热销", "DMM 来源月榜", "全站神作总榜", "女优战力总榜"]
        let sections: [JRBackendSection] = ids.enumerated().map { i, id in
            let sectionLinks: [JRBackendLink]
            switch id {
            case "rankings": sectionLinks = Array(links.prefix(8)) + [JRBackendLink(sourcePath: "/zh-hans/rankings/", kind: "collection", topic: nil)]
            case "monthly": sectionLinks = [links[1]]
            case "weekly": sectionLinks = [links[0]]
            case "awarded": sectionLinks = [JRBackendLink(sourcePath: "/zh-hans/most-awarded-videos/", kind: "collection", topic: nil)]
            case "actors": sectionLinks = [JRBackendLink(sourcePath: "/zh-hans/most-awarded-actors/", kind: "collection", topic: nil)]
            default: sectionLinks = []
            }
            let actors: [JRBackendEntity]? = id == "actors" ? (1...3).map {
                JRBackendEntity(sourceID: "neutral-actor-\($0)", sourcePath: "/zh-hans/actors/neutral-\($0)/", name: "中性示例演员 \($0)", aliases: ["示例别名"], score: Double($0 * 1000), items: Array(items.prefix(4)))
            } : nil
            return JRBackendSection(id: id, label: labels[i], order: i+1, kind: id == "rankings" ? "navigation" : "videos", links: sectionLinks, items: ["pick", "rankings", "actors"].contains(id) ? [] : items, actors: actors)
        }
        let isHome = route == "home", isTopics = route == "topics"
        let payload = JRBackendPayload(type: isTopics ? "topics" : isHome ? "home" : "collection", sections: isHome ? sections : nil, topics: isTopics ? links : nil, items: !isHome && !isTopics ? items : nil, entities: nil, links: nil, categories: nil, page: 1, nextPage: nil, nextSourcePath: nil, total: nil)
        return JRBackendEnvelope(schemaVersion: 1, sourcePath: "/neutral/", fetchedAt: "中性快照", lastAttempt: nil, status: "ok", stale: false, nextAttempt: nil, refresh: "not_due", data: payload)
    }
    #endif
}
