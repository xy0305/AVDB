import SwiftUI
import UniformTypeIdentifiers

@MainActor struct DMMRankingView: View {
    @StateObject private var store: DMMRankingStore
    init(store: DMMRankingStore? = nil) { _store = StateObject(wrappedValue: store ?? DMMRankingStore()) }
    @State private var importing = false
    @State private var importError: String?
    @AppStorage("dmm.authorizedAdultDeclaration") private var adultAuthorization = false
    @State private var visibleCount = 20
    private var autoRefreshKey: String { "\(store.kind.rawValue)|\(adultAuthorization)" }
    private func growVisible(total: Int) {
        guard visibleCount < total else { return }
        visibleCount = min(visibleCount + 20, total)
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
            Picker("榜单", selection: Binding(get: { store.kind }, set: { store.select($0); visibleCount = 20 })) {
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
                    Text("已显示 \(min(visibleCount, board.count)) / \(board.count) · \(sourceLabel)").font(.caption)
                    Spacer()
                    if store.status.contains("正在") { ProgressView().controlSize(.small) }
                }
                .accessibilityIdentifier("dmm-visible-count")
                if board.kind.isActress {
                    DMMActressRankingPage(
                        rows: Array(board.actressRows.prefix(visibleCount)),
                        onNearEnd: { growVisible(total: board.count) }
                    )
                    .id("\(board.kind.rawValue)|\(board.observedAt.timeIntervalSince1970)")
                } else {
                    DMMRankingPage(
                        store: store,
                        rows: Array(board.contentRows.prefix(visibleCount)),
                        kind: board.kind,
                        onNearEnd: { growVisible(total: board.count) }
                    )
                    .id("\(board.kind.rawValue)|\(board.observedAt.timeIntervalSince1970)")
                }
            } else {
                ContentUnavailableView("尚未加载榜单", systemImage: "arrow.clockwise", description: Text(adultAuthorization ? "正在自动静默刷新：优先隐藏网页渲染，其次 GraphQL；失败可点「刷新榜单」或导入合法取得的完整日/周/月作品榜或月间女优榜HTML。实时/系列尚未接入。" : "开启成年授权后进入本页会自动静默刷新：优先隐藏网页渲染，其次 GraphQL；仍失败可导入合法取得的完整日/周/月作品榜或月间女优榜HTML。实时/系列尚未接入。"))
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
                visibleCount = 20; importError = nil
            } catch { importError = "未导入：需要完整日榜20/周月榜100/女优榜100，或具有唯一canonical、同CID配信品番和唯一厂家品番的详情HTML。" }
        }
        .task(id: autoRefreshKey) {
            guard adultAuthorization else { return }
            visibleCount = 20
            await store.refresh()
        }
        .onChange(of: store.board?.observedAt) { _, _ in visibleCount = 20 }
        .onDisappear { store.cancel() }
    }
}

@MainActor private struct DMMRankingPage: View {
    @ObservedObject var store: DMMRankingStore
    @State private var manualSearch = false
    let rows: [DMMContentRow]
    let kind: DMMRankingKind
    var onNearEnd: () -> Void = {}
    @StateObject private var mapper: JavVerseMapper
    private let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12, alignment: .top), count: 3)
    init(store: DMMRankingStore, rows: [DMMContentRow], kind: DMMRankingKind, onNearEnd: @escaping () -> Void = {}) {
        self.store = store; self.rows = rows; self.kind = kind; self.onNearEnd = onNearEnd
        _mapper = StateObject(wrappedValue: JavVerseMapper(scope: "dmm|\(kind.rawValue)|manufacturer-verified"))
    }
    private func entry(_ row: DMMContentRow) -> JavVerseEntry? {
        guard let item = store.evidence[row.cid], item.cid == row.cid else { return nil }
        return JavVerseEntry(rank: row.rank, kind: "movie", label: item.code, sourceURL: row.sourceURL.absoluteString, code: item.code)
    }
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(rows) { row in
                    DMMMovieCard(
                        row: row,
                        entry: entry(row),
                        store: store,
                        mapper: mapper,
                        onManualSearch: { manualSearch = true }
                    )
                    .onAppear {
                        if row.cid == rows.last?.cid { onNearEnd() }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderless)
        .navigationDestination(isPresented: $manualSearch) { SearchView() }
        .onAppear { resolveMapped() }
        .onChange(of: store.evidence.count) { _, _ in resolveMapped() }
        .onChange(of: rows.map(\.cid)) { _, _ in resolveMapped() }
        .onDisappear { mapper.cancel() }
    }
    private func resolveMapped() {
        let items = rows.compactMap(entry)
        guard !items.isEmpty else { return }
        mapper.resolve(items, retry: false)
    }
}

@MainActor private struct DMMMovieCard: View {
    let row: DMMContentRow
    let entry: JavVerseEntry?
    @ObservedObject var store: DMMRankingStore
    @ObservedObject var mapper: JavVerseMapper
    let onManualSearch: () -> Void
    private var movie: Movie? { entry.flatMap(mapper.movie(for:)) }
    private var codeLabel: String { entry?.label ?? row.cid }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let movie, let entry {
                    NavigationLink { MovieDetailView(movieID: movie.id) } label: { poster(movie: movie) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("dmm-movie-\(row.rank)")
                } else if let entry {
                    Button { mapper.resolve([entry], retry: true) } label: { poster(movie: nil) }
                        .buttonStyle(.plain)
                        .disabled(mapper.busy)
                } else {
                    Button { store.request(row) } label: { poster(movie: nil) }
                        .buttonStyle(.plain)
                }
            }
            Text("#\(row.rank) · DMM · \(codeLabel)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .accessibilityIdentifier("dmm-rank-\(row.rank)")
            if let entry {
                Text(entry.label).font(.caption.weight(.semibold)).lineLimit(1)
                if movie == nil {
                    Text(mapper.messages[entry.id] ?? "未匹配 · 保留源榜位").font(.caption2).foregroundStyle(.secondary)
                    Button("精确核对AVDB") { mapper.resolve([entry], retry: true) }
                        .font(.caption2)
                        .disabled(mapper.busy)
                } else {
                    Text(mapper.messages[entry.id] ?? "已核验").font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            } else {
                Text("厂家品番未知 · 未匹配").font(.caption.weight(.semibold)).lineLimit(2)
                Text(store.messages[row.cid] ?? "按需核对，不从CID推号").font(.caption2).foregroundStyle(.secondary)
                Button("获取 / 重试详情") { store.request(row) }.font(.caption2)
            }
            Button("手动搜索核对（不自动认领）") { onManualSearch() }.font(.caption2)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
    }
    @ViewBuilder private func poster(movie: Movie?) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .aspectRatio(0.7, contentMode: .fit)
                .overlay {
                    if let movie, let cover = [movie.coverURL, movie.thumbURL].compactMap({ $0 }).first(where: { !$0.isEmpty }) {
                        JavDBImage(url: cover, fallbackURL: movie.thumbURL, contentMode: .fit, frontPoster: true)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else if mapper.messages[entry?.id ?? ""] == "请求中…" || mapper.messages[entry?.id ?? ""] == "排队中" {
                        ProgressView()
                    } else {
                        Image(systemName: "film")
                            .foregroundStyle(.secondary)
                    }
                }
            Text("\(row.rank)")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(row.rank <= 3 ? Color.orange.opacity(0.85) : Color.blue.opacity(0.75), in: Capsule())
                .foregroundStyle(.white)
                .padding(6)
        }
    }
}

@MainActor private final class DMMActressMapper: ObservableObject {
    @Published var actors: [String: Actor] = [:]
    @Published var candidates: [String: [Actor]] = [:]
    @Published var messages: [String: String] = [:]
    @Published var busy = false
    private var generation = UUID()
    private var task: Task<Void, Never>?
    func cancel() {
        task?.cancel(); task = nil; generation = UUID(); busy = false
        for (key, value) in messages where value == "排队中" || value == "正在精确核对AVDB演员…" {
            messages.removeValue(forKey: key)
        }
    }
    func resolve(_ row: DMMActressRow, retry: Bool = false) {
        resolveVisible([row], retry: retry)
    }
    func resolveVisible(_ rows: [DMMActressRow], retry: Bool = false) {
        guard !busy else { return }
        let batch = Array(rows.filter {
            actors[$0.actressID] == nil && (retry || messages[$0.actressID] == nil)
        }.prefix(20))
        guard !batch.isEmpty else { return }
        let epoch = generation
        busy = true
        for row in batch { messages[row.actressID] = "排队中" }
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.generation == epoch {
                    self.busy = false; self.task = nil
                    for (key, value) in self.messages where value == "排队中" || value == "正在精确核对AVDB演员…" {
                        self.messages.removeValue(forKey: key)
                    }
                }
            }
            await withTaskGroup(of: Void.self) { group in
                var index = 0
                func startNext() {
                    guard index < batch.count else { return }
                    let row = batch[index]
                    index += 1
                    group.addTask { @MainActor in await self.verify(row, epoch: epoch) }
                }
                startNext(); startNext(); startNext(); startNext()
                while await group.next() != nil {
                    if Task.isCancelled || self.generation != epoch { break }
                    startNext()
                }
            }
        }
    }
    private func verify(_ row: DMMActressRow, epoch: UUID) async {
        let key = row.actressID
        messages[key] = "正在精确核对AVDB演员…"
        do {
            try Task.checkCancellation()
            guard generation == epoch else { throw CancellationError() }
            let identity = ExternalActorIdentity.resolve(sourceName: row.name, aliases: [], catalog: .bundled())
            let resolution = try await ExternalActorResolver.inspect(identity: identity, search: { keyword, page in
                try await JavDBSDK.shared.searchActors(keyword: keyword, page: page)
            })
            guard !Task.isCancelled, generation == epoch else { return }
            switch resolution {
            case .matched(let match):
                actors[key] = match.actor
                candidates[key] = []
                messages[key] = "AVDB 演员精确匹配"
            case .notFound:
                actors.removeValue(forKey: key)
                candidates[key] = []
                messages[key] = "未匹配唯一AVDB演员 · 保留源榜位；不发明演员ID"
            case .ambiguous(let list):
                actors.removeValue(forKey: key)
                candidates[key] = list
                messages[key] = "多个精确姓名候选，待手动确认"
            case .incomplete(let list, _):
                actors.removeValue(forKey: key)
                candidates[key] = list
                messages[key] = "查询未完成 · 待手动核对；不发明演员ID"
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, generation == epoch else { return }
            messages[key] = "演员核对失败 · 可重试；不发明演员ID"
        }
    }
}

@MainActor private struct DMMActressRankingPage: View {
    let rows: [DMMActressRow]
    var onNearEnd: () -> Void = {}
    @StateObject private var mapper = DMMActressMapper()
    @State private var manualSearch = false
    private let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12, alignment: .top), count: 3)
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(rows) { row in
                    DMMActressCard(row: row, mapper: mapper, onManualSearch: { manualSearch = true })
                        .onAppear {
                            if row.actressID == rows.last?.actressID { onNearEnd() }
                        }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderless)
        .navigationDestination(isPresented: $manualSearch) { SearchView() }
        .onAppear { mapper.resolveVisible(rows, retry: false) }
        .onChange(of: rows.map(\.actressID)) { _, _ in mapper.resolveVisible(rows, retry: false) }
        .onDisappear { mapper.cancel() }
    }
}

@MainActor private struct DMMActressCard: View {
    let row: DMMActressRow
    @ObservedObject var mapper: DMMActressMapper
    let onManualSearch: () -> Void
    private var actor: Actor? { mapper.actors[row.actressID] }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let actor {
                    NavigationLink { ActorDetailView(actorID: actor.id) } label: { portrait(actor: actor) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("dmm-actress-\(row.rank)")
                } else {
                    Button { mapper.resolve(row, retry: true) } label: { portrait(actor: nil) }
                        .buttonStyle(.plain)
                        .disabled(mapper.busy)
                }
            }
            Text("#\(row.rank) · DMM女優 · \(row.actressID)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .accessibilityIdentifier("dmm-actress-rank-\(row.rank)")
            Text(row.name).font(.caption.weight(.semibold)).lineLimit(2)
            if let actor {
                Text(actor.displayName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Text(mapper.messages[row.actressID] ?? "已匹配").font(.caption2).foregroundStyle(.secondary)
            } else if let choices = mapper.candidates[row.actressID], !choices.isEmpty {
                Text(mapper.messages[row.actressID] ?? "候选待确认").font(.caption2)
                ForEach(choices.prefix(3), id: \.id) { choice in
                    NavigationLink { ActorDetailView(actorID: choice.id) } label: {
                        Text(choice.displayName).font(.caption2)
                    }
                }
            } else {
                Text(mapper.messages[row.actressID] ?? "未匹配 · 保留源榜位；按姓名精确核对，不发明演员ID")
                    .font(.caption2).foregroundStyle(.secondary)
                Button("精确核对AVDB演员") { mapper.resolve(row, retry: true) }
                    .font(.caption2)
                    .disabled(mapper.busy)
            }
            Link("来源女优列表", destination: row.sourceURL).font(.caption2)
            Button("手动搜索核对（不自动认领）") { onManualSearch() }.font(.caption2)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
    }
    @ViewBuilder private func portrait(actor: Actor?) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .aspectRatio(0.75, contentMode: .fit)
                .overlay {
                    if let actor, let source = [actor.avatarURL, actor.coverURL].compactMap({ $0 }).first(where: { !$0.isEmpty }) {
                        JavDBImage(url: source, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else if mapper.messages[row.actressID] == "请求中…"
                                || mapper.messages[row.actressID] == "排队中"
                                || mapper.messages[row.actressID] == "正在精确核对AVDB演员…" {
                        ProgressView()
                    } else {
                        Image(systemName: "person.crop.square")
                            .foregroundStyle(.secondary)
                    }
                }
            Text("\(row.rank)")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(row.rank <= 3 ? Color.orange.opacity(0.85) : Color.blue.opacity(0.75), in: Capsule())
                .foregroundStyle(.white)
                .padding(6)
        }
    }
}
