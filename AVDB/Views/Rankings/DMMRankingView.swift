import SwiftUI
import UniformTypeIdentifiers

@MainActor struct DMMRankingView: View {
    @StateObject private var store: DMMRankingStore
    init(store: DMMRankingStore? = nil) { _store = StateObject(wrappedValue: store ?? DMMRankingStore()) }
    @State private var importing = false
    @State private var importError: String?
    @AppStorage("dmm.authorizedAdultDeclaration") private var adultAuthorization = false
    @State private var page = 0
    private var pageCount: Int {
        guard let board = store.board else { return 1 }
        return max(1, (board.count + 19) / 20)
    }
    private var sourceLabel: String {
        switch store.fetchSource {
        case .webView: return "页面渲染"
        case .graphql: return "GraphQL"
        case .direct: return "直连文档"
        case .imported: return "用户导入"
        case nil: return store.imported ? "用户导入" : "未加载"
        }
    }
    var body: some View {
        VStack(spacing: 8) {
            Picker("榜单", selection: Binding(get: { store.kind }, set: { store.select($0); page = 0 })) {
                ForEach(DMMRankingKind.allCases) { kind in
                    Text(kind.periodLabel).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("dmm-kind-picker")
            Text("\(store.kind.periodLabel) · \(store.kind.expectedCount)榜位 · 统计起止未知").font(.headline)
            Text(store.status).font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("dmm-source-status")
            Toggle("我已满18岁，授权按官方自声明并记住选择", isOn: Binding(get: { adultAuthorization }, set: { value in
                adultAuthorization = value; store.authorizeAdultDeclaration = value
                if !value { Task { await store.forgetSession() } }
            })).font(.caption).accessibilityIdentifier("dmm-adult-authorization")
            HStack {
                Button("刷新榜单") { Task { await store.refresh() } }
                    .accessibilityIdentifier("dmm-refresh")
                Button("导入HTML") { importing = true }.accessibilityIdentifier("dmm-import")
                Link("正常访问来源", destination: store.kind.sourceURL)
            }.font(.caption)
            if let importError { Text(importError).font(.caption).foregroundStyle(.red) }
            if let board = store.board {
                HStack {
                    Button("上一页") { store.cancel(); page -= 1 }.disabled(page == 0)
                    Spacer()
                    Text("\(page + 1) / \(pageCount) · \(sourceLabel)").font(.caption)
                    Spacer()
                    Button("下一页") { store.cancel(); page += 1 }.disabled(page >= pageCount - 1)
                }
                if board.kind.isActress {
                    DMMActressRankingPage(rows: Array(board.actressRows.dropFirst(page * 20).prefix(20)))
                        .id("\(board.kind.rawValue)|\(board.observedAt.timeIntervalSince1970)|\(page)")
                } else {
                    DMMRankingPage(store: store, rows: Array(board.contentRows.dropFirst(page * 20).prefix(20)), kind: board.kind)
                        .id("\(board.kind.rawValue)|\(board.observedAt.timeIntervalSince1970)|\(page)")
                }
            } else {
                ContentUnavailableView("尚未加载榜单", systemImage: "arrow.clockwise", description: Text("开启成年授权后点「刷新榜单」：优先隐藏网页渲染，其次 GraphQL；仍失败可导入合法取得的完整日/周/月作品榜或月间女优榜HTML。实时/系列尚未接入。"))
            }
        }
        .padding(.horizontal)
        .background { LiquidGlassBackground() }
        .navigationTitle("DMM 榜单 · Preview")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.html], allowsMultipleSelection: true) { result in
            do {
                let urls = try result.get()
                for url in urls {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    try store.importHTML(Data(contentsOf: url))
                }
                page = 0; importError = nil
            } catch { importError = "未导入：需要完整日榜20/周月榜100/女优榜100，或具有唯一canonical、同CID配信品番和唯一厂家品番的详情HTML。" }
        }
        .onDisappear { store.cancel() }
    }
}

@MainActor private struct DMMRankingPage: View {
    @ObservedObject var store: DMMRankingStore
    @State private var manualSearch = false
    let rows: [DMMContentRow]
    let kind: DMMRankingKind
    @StateObject private var mapper: JavVerseMapper
    init(store: DMMRankingStore, rows: [DMMContentRow], kind: DMMRankingKind) {
        self.store = store; self.rows = rows; self.kind = kind
        _mapper = StateObject(wrappedValue: JavVerseMapper(scope: "dmm|\(kind.rawValue)|manufacturer-verified"))
    }
    private func entry(_ row: DMMContentRow) -> JavVerseEntry? {
        guard let item = store.evidence[row.cid], item.cid == row.cid else { return nil }
        return JavVerseEntry(rank: row.rank, kind: "movie", label: item.code, sourceURL: row.sourceURL.absoluteString, code: item.code)
    }
    var body: some View {
        List(rows) { row in
            VStack(alignment: .leading, spacing: 6) {
                Text("#\(row.rank) · DMM · \(row.cid)").font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("dmm-rank-\(row.rank)")
                if let item = entry(row) {
                    Text(item.label).font(.headline)
                    if let movie = mapper.movie(for: item) {
                        NavigationLink { MovieDetailView(movieID: movie.id) } label: {
                            HStack {
                                if let cover = movie.coverURL {
                                    JavDBImage(url: cover, fallbackURL: movie.thumbURL, contentMode: .fit, frontPoster: true)
                                        .frame(width: 64, height: 90)
                                }
                                Text(movie.title ?? item.label)
                            }
                        }.accessibilityIdentifier("dmm-movie-\(row.rank)")
                    } else {
                        Text(mapper.messages[item.id] ?? "未匹配 · 保留源榜位").font(.caption)
                        Button("精确核对AVDB") { mapper.resolve([item], retry: true) }
                            .disabled(mapper.busy)
                    }
                } else {
                    Text("厂家品番未知 · 未匹配").font(.headline)
                    Text(store.messages[row.cid] ?? "按需核对，不从CID推号").font(.caption)
                    Button("获取 / 重试详情") { store.request(row) }
                }
                Button("手动搜索核对（不自动认领）") { manualSearch = true }.font(.caption)
            }.padding(.vertical, 4)
        }.listStyle(.plain)
        .buttonStyle(.borderless)
        .navigationDestination(isPresented: $manualSearch) { SearchView() }
        .onDisappear { mapper.cancel() }
    }
}

@MainActor private final class DMMActressMapper: ObservableObject {
    @Published var actors: [String: Actor] = [:]
    @Published var candidates: [String: [Actor]] = [:]
    @Published var messages: [String: String] = [:]
    @Published var busy = false
    private var tasks: [String: Task<Void, Never>] = [:]
    func cancel() { tasks.values.forEach { $0.cancel() }; tasks.removeAll() }
    func resolve(_ row: DMMActressRow, retry: Bool = false) {
        let key = row.actressID
        if !retry, actors[key] != nil || tasks[key] != nil { return }
        tasks[key]?.cancel()
        busy = true
        messages[key] = "正在精确核对AVDB演员…"
        tasks[key] = Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.tasks.removeValue(forKey: key); self.busy = !self.tasks.isEmpty } }
            do {
                let identity = ExternalActorIdentity.resolve(sourceName: row.name, aliases: [], catalog: .bundled())
                let resolution = try await ExternalActorResolver.inspect(identity: identity, search: { keyword, page in
                    try await JavDBSDK.shared.searchActors(keyword: keyword, page: page)
                })
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    switch resolution {
                    case .matched(let match):
                        self.actors[key] = match.actor
                        self.candidates[key] = []
                        self.messages[key] = "AVDB 演员精确匹配"
                    case .notFound:
                        self.actors.removeValue(forKey: key)
                        self.candidates[key] = []
                        self.messages[key] = "未匹配唯一AVDB演员 · 保留源榜位；不发明演员ID"
                    case .ambiguous(let list):
                        self.actors.removeValue(forKey: key)
                        self.candidates[key] = list
                        self.messages[key] = "多个精确姓名候选，待手动确认"
                    case .incomplete(let list, _):
                        self.actors.removeValue(forKey: key)
                        self.candidates[key] = list
                        self.messages[key] = "查询未完成 · 待手动核对；不发明演员ID"
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.messages[key] = "演员核对失败 · 可重试；不发明演员ID"
                }
            }
        }
    }
}

@MainActor private struct DMMActressRankingPage: View {
    let rows: [DMMActressRow]
    @StateObject private var mapper = DMMActressMapper()
    @State private var manualSearch = false
    var body: some View {
        List(rows) { row in
            VStack(alignment: .leading, spacing: 6) {
                Text("#\(row.rank) · DMM女優 · \(row.actressID)").font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("dmm-actress-rank-\(row.rank)")
                Text(row.name).font(.headline)
                if let actor = mapper.actors[row.actressID] {
                    NavigationLink { ActorDetailView(actorID: actor.id) } label: {
                        Text(actor.displayName)
                    }.accessibilityIdentifier("dmm-actress-\(row.rank)")
                } else if let choices = mapper.candidates[row.actressID], !choices.isEmpty {
                    Text(mapper.messages[row.actressID] ?? "候选待确认").font(.caption)
                    ForEach(choices.prefix(5), id: \.id) { actor in
                        NavigationLink { ActorDetailView(actorID: actor.id) } label: {
                            Text(actor.displayName).font(.caption)
                        }
                    }
                } else {
                    Text(mapper.messages[row.actressID] ?? "未匹配 · 保留源榜位；按姓名精确核对，不发明演员ID").font(.caption)
                    Button("精确核对AVDB演员") { mapper.resolve(row, retry: true) }
                        .disabled(mapper.busy)
                }
                Link("来源女优列表", destination: row.sourceURL).font(.caption)
                Button("手动搜索核对（不自动认领）") { manualSearch = true }.font(.caption)
            }.padding(.vertical, 4)
        }.listStyle(.plain)
        .buttonStyle(.borderless)
        .navigationDestination(isPresented: $manualSearch) { SearchView() }
        .onDisappear { mapper.cancel() }
    }
}
