import SwiftUI
import UniformTypeIdentifiers

@MainActor struct DMMRankingView: View {
    @StateObject private var store: DMMRankingStore
    @ObservedObject private var matcher = AvfanMatchStore.shared
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
            if let status = matcher.statusText { Text(status).font(.caption).foregroundStyle(.secondary) }
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
    let rows: [DMMContentRow]
    let kind: DMMRankingKind
    var onNearEnd: () -> Void = {}
    @ObservedObject private var matcher = AvfanMatchStore.shared
    private let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12, alignment: .top), count: 3)
    init(store: DMMRankingStore, rows: [DMMContentRow], kind: DMMRankingKind, onNearEnd: @escaping () -> Void = {}) {
        self.store = store; self.rows = rows; self.kind = kind; self.onNearEnd = onNearEnd
    }
    /// The maker code DMMRankingStore resolved for this row, if any.
    /// Matching never derives a code from the CID.
    private func code(_ row: DMMContentRow) -> String? {
        guard let item = store.evidence[row.cid], item.cid == row.cid else { return nil }
        return item.code
    }
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(rows) { row in
                    DMMMovieCard(
                        row: row,
                        code: code(row),
                        store: store
                    )
                    .onAppear {
                        if row.cid == rows.last?.cid { onNearEnd() }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderless)
        .onAppear { enqueueMatches() }
        .onChange(of: store.evidence.count) { _, _ in enqueueMatches() }
        .onChange(of: rows.map(\.cid)) { _, _ in enqueueMatches() }
    }
    private func enqueueMatches() {
        // Build 353: entries match avfan by their DMM maker code.
        matcher.enqueue(codes: rows.compactMap { code($0) })
    }
}

@MainActor private struct DMMMovieCard: View {
    let row: DMMContentRow
    let code: String?
    @ObservedObject var store: DMMRankingStore
    @ObservedObject private var matcher = AvfanMatchStore.shared
    private var match: AvfanMatchStore.MovieMatch? { code.flatMap { matcher.match(forCode: $0) } }
    private var codeLabel: String { code ?? row.cid }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let code {
                    NavigationLink { AvfanRouteView(code: code, title: row.sourceTitle) } label: { poster }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("dmm-movie-\(row.rank)")
                } else {
                    Button { store.request(row) } label: { poster }
                        .buttonStyle(.plain)
                }
            }
            Text("#\(row.rank) · DMM · \(codeLabel)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .accessibilityIdentifier("dmm-rank-\(row.rank)")
            if let code {
                Text(code).font(.caption.weight(.semibold)).lineLimit(1)
                if match != nil {
                    Text("AVFan 已匹配").font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                } else if matcher.isMiss(code: code) {
                    Text("AVFan 暂无此作").font(.caption2).foregroundStyle(.secondary)
                    Button("重试 AVFan 匹配") { matcher.retry(code: code) }.font(.caption2)
                } else {
                    Text("等待 AVFan 匹配…").font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("厂家品番未知 · 未匹配").font(.caption.weight(.semibold)).lineLimit(2)
                Text(store.messages[row.cid] ?? "按需核对，不从CID推号").font(.caption2).foregroundStyle(.secondary)
                Button("获取 / 重试详情") { store.request(row) }.font(.caption2)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
    }
    private var poster: some View {
        MoviePosterCard(
            movie: Movie(
                id: match?.pathID ?? "dmm:" + row.cid,
                number: codeLabel,
                title: match?.title ?? row.sourceTitle,
                coverURL: match?.coverURL
            ),
            rank: row.rank,
            upgradesVisibleHQ: false
        )
    }
}

@MainActor private struct DMMActressRankingPage: View {
    let rows: [DMMActressRow]
    var onNearEnd: () -> Void = {}
    @ObservedObject private var matcher = AvfanMatchStore.shared
    private let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12, alignment: .top), count: 3)
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(rows) { row in
                    DMMActressCard(row: row)
                        .onAppear {
                            if row.actressID == rows.last?.actressID { onNearEnd() }
                        }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderless)
        .onAppear { enqueueMatches() }
        .onChange(of: rows.map(\.actressID)) { _, _ in enqueueMatches() }
    }
    private func enqueueMatches() {
        // Build 353: actresses match avfan by exact name.
        for row in rows { matcher.enqueueActor(name: row.name) }
    }
}

@MainActor private struct DMMActressCard: View {
    let row: DMMActressRow
    @ObservedObject private var matcher = AvfanMatchStore.shared
    private var match: AvfanMatchStore.ActorMatch? { matcher.actorMatch(forName: row.name) }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NavigationLink { AvfanActorRouteView(name: row.name) } label: { portrait }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dmm-actress-\(row.rank)")
            Text("#\(row.rank) · DMM女優 · \(row.actressID)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .accessibilityIdentifier("dmm-actress-rank-\(row.rank)")
            Text(row.name).font(.caption.weight(.semibold)).lineLimit(2)
            if match != nil {
                Text("AVFan 已匹配").font(.caption2).foregroundStyle(.secondary)
            } else if matcher.isActorMiss(name: row.name) {
                Text("AVFan 暂无此演员").font(.caption2).foregroundStyle(.secondary)
                Button("重试 AVFan 匹配") { matcher.retryActor(name: row.name) }.font(.caption2)
            } else {
                Text("等待 AVFan 匹配…").font(.caption2).foregroundStyle(.secondary)
            }
            Link("来源女优列表", destination: row.sourceURL).font(.caption2)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
    }
    private var portrait: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .aspectRatio(0.75, contentMode: .fit)
                .overlay {
                    if let avatar = match?.avatarURL {
                        JavDBImage(url: avatar, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
