import SwiftUI

struct JavRankingView: View {
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
        case "explore": JRIndexView(mode: .explore)
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
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12), count: AdaptiveLayout.columnCount(width: width, padding: AdaptiveLayout.gridPadding, spacing: 12)), spacing: 16) {
            ForEach(videos) { video in
                NavigationLink { JRPageView(path: video.path) } label: {
                    MoviePosterCard(movie: Movie(id: video.id, number: video.code, title: video.title, thumbURL: video.image, coverURL: video.image))
                }.buttonStyle(.plain).frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading).contentShape(Rectangle()).clipped()
            }
        }.padding(.horizontal, AdaptiveLayout.gridPadding)
        .background { GeometryReader { g in Color.clear.preference(key: JRWidthKey.self, value: g.size.width) } }
        .onPreferenceChange(JRWidthKey.self) { if $0 > 0 { width = $0 } }
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
    @State private var limit = 30
    @State private var loading = false
    @State private var error = ""
    @State private var picked: JRVideo?
    private var title: String { mode == .search ? "来源搜索" : mode == .pick ? "今天冲哪个？" : "片库与题材" }
    private var filtered: [JRVideo] {
        let q = JRPolicy.normalizedCode(query)
        return (index?.videos ?? []).filter { v in
            (q.isEmpty || JRPolicy.normalizedCode(v.code + v.title + v.subtitle).contains(q)) && selected.isSubset(of: Set(v.categories)) && (year == "全部年份" || v.date.hasPrefix(year))
        }.sorted { a,b in
            if sort == "newest", a.date != b.date { return a.date > b.date }
            if sort == "oldest", a.date != b.date { return (a.date.isEmpty ? "9999" : a.date) < (b.date.isEmpty ? "9999" : b.date) }
            if a.score != b.score { return a.score > b.score }; return a.path < b.path
        }
    }
    private var entities: [JRLink] {
        let q = JRPolicy.normalizedCode(query)
        guard !q.isEmpty else { return [] }
        return (index?.entities ?? []).filter { JRPolicy.normalizedCode(index?.aliases[$0.path] ?? $0.title).contains(q) }
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
                if let index { indexContent(index) }
            }.padding(.vertical).frame(maxWidth: AdaptiveLayout.contentMaxWidth).frame(maxWidth: .infinity)
        }
        .background { LiquidGlassBackground() }
        .searchable(text: $query, prompt: "番号 / 名称")
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .task(id: source.generation) { await load() }
        .onChange(of: query) { _,_ in limit = 30; picked = nil }
        .onChange(of: selected) { _,_ in limit = 30; picked = nil }
        .onChange(of: sort) { _,_ in limit = 30 }
        .onChange(of: year) { _,_ in limit = 30; picked = nil }
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
                Button("加载更多") { limit += 30 }.frame(maxWidth: .infinity).padding()
            }
        }
    }
    private func load() async {
        let epoch = source.generation
        index = nil; picked = nil; loading = true; error = ""; limit = 30; selected.removeAll()
        do { let value = try await source.index(search: mode == .search); guard epoch == source.generation, !Task.isCancelled else { return }; index = value }
        catch { if epoch == source.generation && !Task.isCancelled { self.error = error.localizedDescription } }
        if epoch == source.generation { loading = false }
    }
}

struct JRPageView: View {
    let path: String
    @ObservedObject private var source = JavRankingSource.shared
    @State private var page: JRPage?
    @State private var error = ""
    @State private var loading = false
    @State private var limit = 30
    @State private var verified: Movie?
    @State private var verification = ""
    @State private var checking = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if loading { ProgressView("加载公开内容…").frame(maxWidth: .infinity) }
                if !error.isEmpty { Text(error).foregroundStyle(.secondary); Button("重试") { Task { await load() } } }
                if let page {
                    if let detail = page.detail {
                        JavDBImage(url: detail.image).aspectRatio(4/3, contentMode: .fit).frame(maxHeight: 340).clipShape(RoundedRectangle(cornerRadius: 14)).padding(.horizontal)
                        VStack(alignment: .leading, spacing: 12) {
                            Text(detail.code).font(.headline).foregroundStyle(.tint)
                            Text(detail.title).font(.title3.bold()).textSelection(.enabled)
                            ForEach(Array(page.metadata.enumerated()), id: \.offset) { _, text in Text(text).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled) }
                            if !detail.code.isEmpty {
                                Button(checking ? "核验番号中…" : "按番号查找 JavDB / 115 播放入口") { Task { await verify(detail.code) } }.disabled(checking)
                                if !verification.isEmpty { Text(verification).font(.caption).foregroundStyle(.secondary) }
                                if let verified { NavigationLink("打开已核验的 JavDB 详情") { MovieDetailView(movieID: verified.id) } }
                            }
                            if let url = URL(string: path, relativeTo: source.base)?.absoluteURL { Link("在外部浏览器查看来源页", destination: url).font(.footnote) }
                        }.padding(.horizontal, AdaptiveLayout.horizontalPadding)
                    }
                    if !page.links.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(page.detail == nil ? "分类 / 人物 / 榜单导航" : "演员 / 片商 / 导演 / 入榜记录").font(.headline)
                            ForEach(page.links) { link in
                                NavigationLink { JRPageView(path: link.path) } label: { HStack { Text(link.title).multilineTextAlignment(.leading); Spacer(); Image(systemName: "chevron.right").font(.caption) }.padding(.vertical, 4) }
                            }
                        }.padding(.horizontal, AdaptiveLayout.horizontalPadding)
                    }
                    ForEach(Array(page.paragraphs.enumerated()), id: \.offset) { _, text in Text(text).font(.subheadline).textSelection(.enabled).padding(.horizontal, AdaptiveLayout.horizontalPadding) }
                    if !page.videos.isEmpty {
                        Text("\(page.videos.count) 部公开影片（来源顺序）").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                        JRPosterGrid(videos: Array(page.videos.prefix(limit)))
                        if limit < page.videos.count { Button("加载更多") { limit += 30 }.frame(maxWidth: .infinity).padding() }
                    }
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
        .task(id: source.generation) { await load() }
    }
    private func load() async {
        let epoch = source.generation
        page = nil; verified = nil; verification = ""; checking = false; limit = 30; error = ""; loading = true
        do {
            let result = try await source.page(path)
            guard epoch == source.generation, !Task.isCancelled else { return }; page = result
        } catch { if epoch == source.generation && !Task.isCancelled { self.error = error.localizedDescription } }
        if epoch == source.generation { loading = false }
    }
    private func verify(_ code: String) async {
        let epoch = source.generation
        checking = true; verified = nil; verification = ""
        do {
            let results = try await JavDBSDK.shared.search(keyword: code, type: "code", limit: 20)
            guard epoch == source.generation, !Task.isCancelled else { return }
            let matches = results.filter { JRPolicy.normalizedCode($0.number ?? "") == JRPolicy.normalizedCode(code) }
            if matches.count == 1 { verified = matches[0]; verification = "已按完整番号核验；后续播放由原有 JavDB / 115 流程处理。" }
            else { verification = "没有唯一且完整番号一致的 JavDB 结果；保留来源原生详情，不猜测 ID。" }
        } catch { if epoch == source.generation { verification = "JavDB 核验暂不可用：" + error.localizedDescription } }
        if epoch == source.generation { checking = false }
    }
}
