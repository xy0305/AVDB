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
                JRPageView(path: "/zh-hans/rankings/").id(source.generation)
            } else if adultConfirmed {
                List {
                    Section { Text("独立公开元数据来源 · 不替换原 JavDB 标签页。账号、网站清单、插件安装及第三方播放不在此执行。") .font(.footnote).foregroundStyle(.secondary) }
                    Section("浏览") {
                        ForEach(entries, id: \.1) { e in
                            NavigationLink { destination(e.1) } label: { Label(e.0, systemImage: e.2) }
                        }
                    }
                    Section("来源") {
                        NavigationLink { JavRankingSettingsView() } label: { Label("域名与来源设置", systemImage: "gearshape") }
                        Text(source.base.host ?? "").font(.caption).foregroundStyle(.secondary)
                    }
                }.id(source.generation)
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
    @State private var message = ""
    var body: some View {
        Form {
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
        .onAppear { domain = source.base.absoluteString }
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
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12), count: AdaptiveLayout.columnCount(width: width, padding: AdaptiveLayout.gridPadding, spacing: 12)), spacing: 16) {
            ForEach(videos) { video in
                VStack(alignment: .leading, spacing: 4) {
                    NavigationLink { JRMovieRoute(video: video) } label: {
                        MoviePosterCard(movie: mapped[video.path] ?? Movie(id: video.id, number: video.code, title: video.title, thumbURL: video.image, coverURL: video.image))
                    }.buttonStyle(.plain)
                    if let rank = video.rank { Text("来源排名 #\(rank)").font(.caption).foregroundStyle(.secondary) }
                    if mapped[video.path] != nil {
                        Text(video.title).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        NavigationLink("来源资料") { JRPageView(path: video.path, sourceOnly: true) }.font(.caption2)
                    }
                    if !video.code.isEmpty {
                        Text(mapped[video.path] != nil ? "完整番号已核验 · JavDB" : completed.contains(video.path) ? "点击重试核验 · 来源资料仅辅助" : "点击核验并打开原生详情")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }.frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading).contentShape(Rectangle()).clipped()
            }
        }.padding(.horizontal, AdaptiveLayout.gridPadding)
        .background { GeometryReader { g in Color.clear.preference(key: JRWidthKey.self, value: g.size.width) } }
        .onPreferenceChange(JRWidthKey.self) { if $0 > 0 { width = $0 } }
        .task(id: "\(source.generation):" + videos.map(\.path).joined(separator: ",")) {
            let epoch = source.generation
            mapped.removeAll(); completed.removeAll()
            // Only the explicitly displayed page, three lookups at a time.
            // Source placeholders are already rendered; publish each match alone.
            await withTaskGroup(of: (String, Movie?).self) { group in
                var iterator = videos.filter { !$0.code.isEmpty && mapped[$0.path] == nil }.makeIterator()
                func add(_ video: JRVideo) {
                    group.addTask {
                        guard !Task.isCancelled else { return (video.path, nil) }
                        let movie = try? await source.matchedMovie(code: video.code)
                        return (video.path, movie)
                    }
                }
                for _ in 0..<3 { if let video = iterator.next() { add(video) } }
                while let (path, movie) = await group.next() {
                    guard !Task.isCancelled, epoch == source.generation else { group.cancelAll(); break }
                    if let movie { mapped[path] = movie }
                    completed.insert(path)
                    if let video = iterator.next() { add(video) }
                }
            }
        }

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

struct JRPageView: View {
    let path: String
    var sourceOnly = false
    @ObservedObject private var source = JavRankingSource.shared
    @State private var page: JRPage?
    @State private var isPreview = false
    @State private var error = ""
    @State private var loading = false
    @State private var limit = 12
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
                        if limit < page.videos.count { Button("加载更多") { limit += 12 }.frame(maxWidth: .infinity).padding() }
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
        }.background { LiquidGlassBackground() }
        .navigationTitle(page?.title ?? "JAV Ranking").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .onReceive(source.$previews) { previews in
            if page == nil, let preview = previews[path] { page = preview; isPreview = true }
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
        page = source.cachedPage(path); isPreview = false; limit = 12; error = ""; loading = true
        do {
            let result = try await source.page(path, refresh: refresh)
            guard epoch == source.generation, !Task.isCancelled else { return }; page = result; isPreview = false
        } catch { if epoch == source.generation && !Task.isCancelled { self.error = error.localizedDescription } }
        if epoch == source.generation { loading = false }
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
            if let movie {
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
            loading = true; movie = nil; message = ""
            defer { if epoch == source.generation, request == attempt { loading = false } }
            guard !code.isEmpty else { message = "不能从标题猜测影片；请查看来源资料。"; return }
            do {
                let match = try await source.matchedMovie(code: code, refresh: attempt > 0)
                guard !Task.isCancelled, epoch == source.generation, request == attempt else { return }
                movie = match
                if match == nil { message = "原生影片搜索前 3 页未找到番号 \(code) 的有效 ID 精确结果（不代表影片不存在）。请重试或在原生搜索中核对；不会自动打开辅助来源详情。" }
            } catch {
                guard !Task.isCancelled, epoch == source.generation, request == attempt else { return }
                message = "番号 \(code) 核验失败：" + error.localizedDescription
            }
        }
    }
}
