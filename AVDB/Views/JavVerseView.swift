import SwiftUI

// AVDB's own loader decrypts tp.spfcas.com image streams. AsyncImage cannot decode them.
@MainActor private struct JavVerseArtwork: View {
    let entry: JavVerseEntry
    @ObservedObject var mapper: JavVerseMapper
    var body: some View {
        Group {
            if JavVerseReleaseProbe.enabled {
                Image(systemName: "square.grid.3x3.fill").resizable().scaledToFit()
                    .accessibilityIdentifier("javverse-release-neutral-\(entry.rank)")
            } else {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--javverse-neutral-ui"), mapper.movie(for: entry) != nil || mapper.actor(for: entry) != nil {
                Image(uiImage: JavVerseNeutralFixture.artwork).resizable().scaledToFit()
                    .accessibilityIdentifier("javverse-neutral-cover-\(entry.rank)")
            } else { production }
            #else
            production
            #endif
            }
        }.clipped()
    }
    @ViewBuilder private var production: some View {
        if let movie = mapper.movie(for: entry) {
            let source = [movie.coverURL, movie.thumbURL].compactMap { $0 }.first { !$0.isEmpty }
            if let source {
                JavDBImage(url: source, fallbackURL: movie.thumbURL, contentMode: .fit, frontPoster: true)
            } else { Text("已匹配 · AVDB未提供图片").font(.caption2) }
        } else if let actor = mapper.actor(for: entry) {
            if let source = [actor.avatarURL, actor.coverURL].compactMap({ $0 }).first(where: { !$0.isEmpty }) {
                JavDBImage(url: source, contentMode: .fit)
            } else if let source = mapper.avatars[entry.id] {
                JavDBImage(url: source, contentMode: .fit)
            } else if mapper.avatarStatus[entry.id] == "未设置" {
                Text("未设置").font(.caption2).accessibilityIdentifier("tmdb-avatar-missing")
            } else { Text("已匹配 · AVDB未提供头像").font(.caption2) }
        } else if mapper.messages[entry.id] == "请求中…" || mapper.messages[entry.id] == "排队中" {
            ProgressView()
        } else {
            Image(systemName: entry.kind == "movie" ? "film" : "person.crop.square")
                .foregroundStyle(.secondary)
        }
    }
}

// Independent destination: NavigationLink { JavVerseView() } label: { Text("JavVerse · 原站名单") }
// Does not replace Home or AVDB rankings. Register all three Swift files and bundled JSON in Xcode.
private enum JavVerseRankingTab: String, CaseIterable {
    case daily, weekly, monthly, grok
    var title: String {
        switch self { case .daily: return "日榜"; case .weekly: return "周榜"; case .monthly: return "月榜"; case .grok: return "Grok Top250" }
    }
}

@MainActor struct JavVerseView: View {
    @State private var snapshot: JavVerseSnapshot?
    @State private var failure: String?
    @State private var tab: JavVerseRankingTab = .daily
    @State private var periods: [String: String] = [:]
    @State private var statusText = "加载中…"
    @State private var isLive = false
    @State private var refreshing = false
    private var available: [JavVerseBoard] {
        snapshot?.boards.filter { ($0.term ?? $0.id) == tab.rawValue } ?? []
    }
    private var selected: JavVerseBoard? {
        available.first { $0.id == periods[tab.rawValue] } ?? available.first
    }
    var body: some View {
        VStack(spacing: 0) {
            UnderlineTabBar(tabs: JavVerseRankingTab.allCases.map { ($0, $0.title) }, selection: $tab, scrolls: false)
                .padding(.top, 8).accessibilityIdentifier("javverse-ranking-tabs")
            if let snapshot {
                HStack {
                    if tab != .grok, let selected {
                        Menu {
                            ForEach(available) { board in
                                Button(board.selectionTitle ?? board.period) { periods[tab.rawValue] = board.id }
                                    .accessibilityIdentifier("javverse-period-\(board.periodKey ?? board.id)")
                            }
                        } label: {
                            Text(selected.selectionTitle ?? selected.period).font(.subheadline.weight(.semibold))
                        }
                        .accessibilityIdentifier("javverse-period-menu")
                        .disabled(available.count < 2)
                        if tab == .monthly { Text("原站仅一期").font(.caption2).foregroundStyle(.secondary) }
                    } else { Text("Grok 主观评分").font(.caption).foregroundStyle(.secondary) }
                    Spacer(minLength: 4)
                    NavigationLink { JavVerseHomeView(sharedSnapshot: snapshot, sharedStatus: statusText, sharedLive: isLive) } label: { Text("精选 / 其他榜单").font(.caption) }
                        .accessibilityIdentifier("javverse-other-boards")
                }.padding(.horizontal, 16).padding(.vertical, 4)
                HStack(spacing: 8) {
                    Text(statusText).font(.caption2)
                        .foregroundStyle(isLive ? Color.green : Color.orange)
                        .accessibilityIdentifier("javverse-live-status")
                    Spacer()
                    Button(refreshing ? "刷新中…" : "刷新") { Task { await reload(forceLive: true) } }
                        .font(.caption2).disabled(refreshing)
                        .accessibilityIdentifier("javverse-refresh")
                }.padding(.horizontal, 16).padding(.bottom, 8)
                if tab == .grok {
                    if let grok = snapshot.grok { JavVerseGrokView(snapshot: grok, isLive: isLive) }
                    else { Text("该快照尚无已核实的Grok名单").foregroundStyle(.secondary); Spacer() }
                } else if let selected {
                    // Identity replacement cancels old image work and resets paging before a new period renders.
                    JavVerseBoardView(board: selected, isLive: isLive).id(selected.selectionKey)
                } else { Text("该期暂无已核实快照"); Spacer() }
            } else if let failure { Text(failure).foregroundStyle(.red).accessibilityIdentifier("javverse-load-failure"); Spacer() }
            else { ProgressView("拉取榜单…"); Spacer() }
        }
        .navigationTitle("JavVerse 榜单")
        // Do not tag the parent container: SwiftUI propagates its identifier over child controls.
        .task {
            guard snapshot == nil else { return }
            await reload(forceLive: true)
        }
    }
    @MainActor private func reload(forceLive: Bool) async {
        refreshing = true
        defer { refreshing = false }
        let start = ProcessInfo.processInfo.systemUptime
        failure = nil
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--javverse-neutral-ui") {
            do {
                snapshot = try JavVerseNeutralFixture.snapshot()
                isLive = false
                statusText = "中性夹具 · 非实时"
            } catch { failure = JavVerseFailure.diagnostic(error) }
            return
        }
        #endif
        if forceLive {
            do {
                let live = try await JavVerseLiveClient.fetchSnapshot()
                snapshot = live
                isLive = true
                statusText = "实时 · \(Self.shortStamp(live.preparedAt))"
                #if DEBUG
                print("JAVVERSE241 metadataReadyMs=\((ProcessInfo.processInfo.systemUptime-start)*1000) rows=\(live.boards.reduce(0) { $0+$1.entries.count }) live=true")
                #endif
                return
            } catch {
                // Fall through to offline snapshot; keep a short Chinese reason.
                statusText = "实时失败，改用离线快照"
            }
        }
        do {
            let bundled = try JavVerseSnapshot.bundled()
            snapshot = bundled
            isLive = false
            if !statusText.hasPrefix("实时失败") {
                statusText = "离线快照 · \(Self.shortStamp(bundled.preparedAt))"
            } else {
                statusText = "离线快照（实时不可用）· \(Self.shortStamp(bundled.preparedAt))"
            }
            #if DEBUG
            print("JAVVERSE241 metadataReadyMs=\((ProcessInfo.processInfo.systemUptime-start)*1000) rows=\(bundled.boards.reduce(0) { $0+$1.entries.count }) live=false")
            #endif
        } catch { failure = JavVerseFailure.diagnostic(error) }
    }
    private static func shortStamp(_ iso: String) -> String {
        String(iso.prefix(19)).replacingOccurrences(of: "T", with: " ") + " UTC"
    }
}

@MainActor private struct JavVerseHomeView: View {
    @StateObject private var mapper = JavVerseMapper()
    private let sharedSnapshot: JavVerseSnapshot?
    private let sharedStatus: String
    private let sharedLive: Bool
    init(sharedSnapshot: JavVerseSnapshot? = nil, sharedStatus: String = "离线快照", sharedLive: Bool = false) {
        self.sharedSnapshot = sharedSnapshot
        self.sharedStatus = sharedStatus
        self.sharedLive = sharedLive
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--javverse-neutral-ui") {
            _mapper = StateObject(wrappedValue: JavVerseNeutralFixture.mapper())
        }
        #endif
    }
    @State private var snapshot: JavVerseSnapshot?
    @State private var failure: String?
    @State private var probe = "未测试设备HTTP；打开页时会优先实时拉取"
    @State private var probing = false
    @State private var probeGeneration = UUID()
    @State private var statusText = "加载中…"
    @State private var isLive = false
    var body: some View {
        List {
            Section {
                Text(isLive ? "实时榜单" : "静态快照，非实时").font(.headline)
                    .foregroundStyle(isLive ? Color.green : Color.orange)
                    .accessibilityIdentifier("javverse-home-mode")
                Text("原站名单及顺序来自 JavVerse 公开文字；图片、资料和播放只通过 AVDB 核验。无网站账户或社区同步。")
                    .font(.footnote).foregroundStyle(.secondary)
                Text(statusText).font(.caption)
                Text(probe).font(.caption2).foregroundStyle(.secondary)
                Button(probing ? "检测中…" : "检测普通HTTP（不刷新快照）") { probing = true }
                    .disabled(probing)
                    .accessibilityIdentifier("javverse-http-probe")
            }
            if let snapshot {
                Section("首页 · 原站当日内容") {
                    if mapper.busy { ProgressView("核验首页 \(mapper.completed)/\(mapper.total)") }
                    Button("重试首页未匹配项") { mapper.resolve(snapshot.boards.filter { ["featured", "recent"].contains($0.id) }.flatMap(\.entries), retry: true) }.disabled(mapper.busy)
                    ForEach(snapshot.boards.filter { ["featured", "recent"].contains($0.id) }) { board in
                        VStack(alignment: .leading, spacing: 10) {
                            NavigationLink { JavVerseBoardView(board: board, isLive: isLive) } label: { boardLabel(board) }
                                .accessibilityIdentifier("javverse-board-\(board.id)")
                            if board.entries.allSatisfy({ $0.kind == "movie" }) {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12, alignment: .top), count: 3), spacing: 16) {
                                    ForEach(board.entries) { entry in
                                        JavVerseMovieCard(entry: entry, mapper: mapper)
                                    }
                                }.frame(maxWidth: 728).frame(maxWidth: .infinity)
                            } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 12) {
                                    ForEach(board.entries) { entry in
                                        VStack(spacing: 6) {
                                            JavVerseArtwork(entry: entry, mapper: mapper).frame(width: 84, height: 104)
                                            Text(entry.label).font(.caption).lineLimit(2)
                                            Text(mapper.messages[entry.id] ?? "尚未请求").font(.caption2).lineLimit(2)
                                            if let movie = mapper.movie(for: entry) {
                                                NavigationLink("AVDB 资料") { MovieDetailView(movieID: movie.id) }
                                            } else if let actor = mapper.actor(for: entry) {
                                                NavigationLink("AVDB 演员") { ActorDetailView(actorID: actor.id) }
                                            }
                                        }
                                        .frame(width: 112, height: 205, alignment: .top)
                                        .padding(8)
                                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                            }
                            }
                            Text("采集 UTC：\(board.capturedAt) · 仅原站首页横栏")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("其他 FANZA 榜单") {
                    ForEach(snapshot.boards.filter { ["actresses", "series"].contains($0.id) }) { board in
                        NavigationLink { JavVerseBoardView(board: board, isLive: isLive) } label: { boardLabel(board) }
                            .accessibilityIdentifier("javverse-board-\(board.id)")
                    }
                }
                Section("来源边界") {
                    Text(isLive
                         ? "销量历史期与Grok五分榜在榜单首页切换。当前为实时拉取（失败时回退离线快照）；其他目录、社区、账户同步未接入。"
                         : "销量历史期与Grok五分榜在榜单首页切换。当前为带采集时间的离线快照；其他目录、社区、账户同步未接入。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let failure { Text(failure).foregroundStyle(.red) }
        }
        .navigationTitle("JavVerse · 原站名单")
        // Do not tag the parent container: SwiftUI propagates its identifier over child controls.
        .task(id: probing) {
            guard probing, !JavVerseReleaseProbe.enabled else { return }
            #if DEBUG
            guard !ProcessInfo.processInfo.arguments.contains("--javverse-neutral-ui") else { probing = false; return }
            #endif
            let epoch = probeGeneration
            defer { if probeGeneration == epoch { probing = false } }
            do {
                var statuses: [Int] = []
                for _ in 0..<3 {
                    try Task.checkCancellation()
                    let status = try await JavVerseHTTPProbe.status()
                    statuses.append(status)
                    if status == 403 { break } // Respect refusal; never retry a WAF rejection.
                }
                try Task.checkCancellation()
                guard probeGeneration == epoch else { return }
                probe = "设备普通HTTP诊断（\(statuses.count)次，最多3次）：\(statuses.map(String.init).joined(separator: ", "))。" + (statuses.contains(403) ? "无cookie探测被拒属预期；实时通道另走年龄门。" : "无cookie探测仅作诊断；实时通道另走年龄门。")
            } catch {
                if !Task.isCancelled && probeGeneration == epoch { probe = "检测失败：\(error.localizedDescription)。静态快照仍可作离线回退。" }
            }
        }
        .onDisappear { probeGeneration = UUID(); probing = false; mapper.cancel() }
        .task(id: snapshot != nil) {
            guard let snapshot else { return }
            await mapper.resolve(snapshot.boards.filter { ["featured", "recent"].contains($0.id) }.flatMap(\.entries))?.value
        }
        .task {
            guard snapshot == nil else { return }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--javverse-neutral-ui") {
                do {
                    snapshot = try JavVerseNeutralFixture.snapshot()
                    isLive = false
                    statusText = "中性夹具 · 非实时"
                } catch { failure = JavVerseFailure.diagnostic(error) }
                return
            }
            #endif
            if let sharedSnapshot {
                snapshot = sharedSnapshot
                isLive = sharedLive
                statusText = sharedStatus
                return
            }
            do {
                let live = try await JavVerseLiveClient.fetchSnapshot()
                snapshot = live
                isLive = true
                statusText = "实时 · \(live.preparedAt.prefix(19))"
            } catch {
                do {
                    snapshot = try JavVerseSnapshot.bundled()
                    isLive = false
                    statusText = "离线快照（实时不可用）"
                } catch { failure = JavVerseFailure.diagnostic(error) }
            }
        }
    }
    private func boardLabel(_ board: JavVerseBoard) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(board.title)
            Text("\(board.entries.count)条 · \(board.period)").font(.caption).foregroundStyle(.secondary)
        }
    }
}

@MainActor private struct JavVerseBoardView: View {
    let board: JavVerseBoard
    var isLive: Bool = false
    @StateObject private var mapper = JavVerseMapper()
    @State private var visibleCount = JavVersePagination.size
    private var rows: [JavVerseEntry] { Array(board.entries.prefix(visibleCount)) }
    private func growVisible() {
        guard visibleCount < board.entries.count else { return }
        visibleCount = min(visibleCount + JavVersePagination.size, board.entries.count)
    }
    init(board: JavVerseBoard, isLive: Bool = false) {
        self.board = board
        self.isLive = isLive
        _mapper = StateObject(wrappedValue: JavVerseMapper(scope: board.selectionKey))
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--javverse-neutral-ui") {
            _mapper = StateObject(wrappedValue: JavVerseNeutralFixture.mapper())
        }
        #endif
    }
    private var isMovieBoard: Bool { board.entries.allSatisfy { $0.kind == "movie" } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(isLive ? "实时榜单" : "静态快照，非实时").font(.caption)
                    .foregroundStyle(isLive ? Color.green : Color.orange)
                Text("期间：\(board.period)").font(.subheadline)
                    .accessibilityIdentifier("javverse-selected-period")
                DisclosureGroup("采集时间与来源") {
                    Text("采集时间 UTC：\(board.capturedAt)").font(.caption)
                    Text("来源：\(board.sourceURL)").font(.caption).textSelection(.enabled)
                    Text("保留原站名次，不补位。先显示名单；滑到底自动加载下一批并核验，每批最多20项、同时最多4项。系列不猜映射。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if mapper.busy {
                    HStack {
                        ProgressView("核验本批 \(mapper.completed)/\(mapper.total)").font(.caption)
                        Spacer()
                        Button("取消核验") { mapper.cancel() }.font(.caption)
                    }
                } else {
                    Button("重试可见未匹配项（最多本批）") { mapper.resolve(rows, retry: true) }
                        .font(.caption)
                }
                if isMovieBoard {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12, alignment: .top), count: 3), alignment: .leading, spacing: 16) {
                        ForEach(rows) { entry in
                            JavVerseMovieCard(entry: entry, mapper: mapper)
                                .onAppear { if entry.id == rows.last?.id { growVisible() } }
                        }
                    }
                } else {
                    ForEach(rows) { entry in
                        HStack(alignment: .top, spacing: 12) {
                            Text(String(format: "%02d", entry.rank)).font(.headline.monospacedDigit()).frame(width: 34)
                            JavVerseArtwork(entry: entry, mapper: mapper).frame(width: 64, height: 88)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.label).textSelection(.enabled).accessibilityIdentifier("javverse-row-\(entry.rank)")
                                if let actor = mapper.actor(for: entry) {
                                    Text(mapper.messages[entry.id] ?? "已匹配").font(.caption).foregroundStyle(.secondary)
                                    NavigationLink("AVDB 演员资料") { ActorDetailView(actorID: actor.id) }
                                        .accessibilityIdentifier("javverse-actor-open-\(entry.rank)")
                                } else if entry.kind == "actor" {
                                    Text(mapper.messages[entry.id] ?? "尚未请求").font(.caption).foregroundStyle(.secondary)
                                    let choices = mapper.candidates(for: entry)
                                    if !choices.isEmpty {
                                        NavigationLink("确认候选（\(choices.count)）") {
                                            JavVerseActorConfirmView(title: entry.label, actors: choices)
                                        }
                                        .font(.caption)
                                        .accessibilityIdentifier("javverse-confirm-\(entry.rank)")
                                    }
                                    Button("单独核验 / 重试") { mapper.resolve([entry], retry: true) }.disabled(mapper.busy)
                                } else {
                                    Text("系列未接映射 · 不使用网站数字ID直达AVDB").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onAppear { if entry.id == rows.last?.id { growVisible() } }
                    }
                }
                HStack {
                    Text("已显示 \(rows.count) / \(board.entries.count)").font(.caption)
                        .accessibilityIdentifier("javverse-visible-count")
                    Spacer()
                    if visibleCount < board.entries.count {
                        ProgressView().controlSize(.small)
                        Text("滑到底加载更多").font(.caption2).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(board.title)
        .task(id: visibleCount) { await mapper.resolve(rows)?.value }
        .onDisappear { mapper.cancel() }
    }
}

// One push from a ranking row. Actor pages are reached only by an explicit choice inside this page.
@MainActor private struct JavVerseActorConfirmView: View {
    let title: String
    let actors: [Actor]
    var body: some View {
        List(actors) { actor in
            NavigationLink { ActorDetailView(actorID: actor.id) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(actor.name ?? actor.displayName)
                    Text(actor.videosCount.map { "ID \(actor.id) · \($0)部" } ?? "ID \(actor.id) · 作品数未知")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("javverse-confirm-choice-\(actor.id)")
        }
        .navigationTitle(title)
        .accessibilityIdentifier("javverse-actor-confirm")
    }
}

// Same production poster/rank/resource badges as JAVLibrary, with JavVerse-owned identity and queue.
@MainActor private struct JavVerseMovieCard: View {
    let entry: JavVerseEntry
    @ObservedObject var mapper: JavVerseMapper
    private var movie: Movie? { mapper.movie(for: entry) }
    private var state: String {
        mapper.messages[entry.id] ?? "尚未核验 · 点击卡片核验"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let movie {
                NavigationLink {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--javverse-neutral-ui") {
                        Text("Neutral detail \(entry.label)").accessibilityIdentifier("javverse-detail-\(entry.rank)")
                    } else { MovieDetailView(movieID: movie.id) }
                    #else
                    MovieDetailView(movieID: movie.id)
                    #endif
                } label: { poster }.buttonStyle(.plain)
            } else {
                Button { mapper.resolve([entry], retry: true) } label: { poster }
                    .buttonStyle(.plain).disabled(mapper.busy)
            }
            Text(state).font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("javverse-state-\(entry.rank)")
        }.frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
    }
    private var poster: some View {
        MoviePosterCard(movie: movie ?? Movie(id: "javverse:\(entry.id)", number: entry.label, title: entry.label),
                        rank: entry.rank, artwork: AnyView(JavVerseArtwork(entry: entry, mapper: mapper)),
                        expandsTitle: true, sourceNumber: entry.label, numberIdentifier: "javverse-row-\(entry.rank)")
    }
}

@MainActor private struct JavVerseGrokView: View {
    let snapshot: JavVerseGrokSnapshot
    var isLive: Bool = false
    @State private var metric: JavVerseGrokMetric = .total
    @State private var status: JavVerseGrokStatus = .all
    @State private var visibleCount = 20
    private var rows: [JavVerseGrokRow] { snapshot.rows(metric: metric, status: status) }
    private var current: [JavVerseGrokRow] { Array(rows.prefix(visibleCount)) }
    private var key: String { "javverse|grok250|\(metric.rawValue)|static|\(snapshot.capturedAt)|\(status.rawValue)" }
    private func growVisible() {
        guard visibleCount < rows.count else { return }
        visibleCount = min(visibleCount + 20, rows.count)
    }
    var body: some View {
        VStack(spacing: 0) {
            UnderlineTabBar(tabs: JavVerseGrokMetric.allCases.map { ($0, $0.title) }, selection: $metric, scrolls: false)
                .accessibilityIdentifier("javverse-grok-metrics")
            HStack {
                Picker("参榜状态", selection: $status) {
                    ForEach(JavVerseGrokStatus.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("javverse-grok-status")
                Spacer()
                Text("\(rows.count)位 · Grok \(metric.title)分").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 16)
            JavVerseGrokPage(rows: current, metric: metric, capturedAt: snapshot.capturedAt, scope: key, isLive: isLive, onNearEnd: growVisible)
                .id(key)
            HStack {
                Text("已显示 \(current.count) / \(rows.count)").font(.caption)
                    .accessibilityIdentifier("javverse-grok-page")
                Spacer()
                if visibleCount < rows.count {
                    Text("滑到底加载更多").font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 20).padding(.vertical, 10)
        }
        .onChange(of: metric) { _ in visibleCount = 20 }
        .onChange(of: status) { _ in visibleCount = 20 }
    }
}

@MainActor private struct JavVerseGrokPage: View {
    let rows: [JavVerseGrokRow]
    let metric: JavVerseGrokMetric
    let capturedAt: String
    var isLive: Bool = false
    var onNearEnd: () -> Void = {}
    @StateObject private var mapper: JavVerseMapper
    init(rows: [JavVerseGrokRow], metric: JavVerseGrokMetric, capturedAt: String, scope: String, isLive: Bool = false, onNearEnd: @escaping () -> Void = {}) {
        self.rows = rows; self.metric = metric; self.capturedAt = capturedAt; self.isLive = isLive; self.onNearEnd = onNearEnd
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--javverse-neutral-ui") {
            _mapper = StateObject(wrappedValue: JavVerseNeutralFixture.mapper())
        } else { _mapper = StateObject(wrappedValue: JavVerseMapper(scope: scope)) }
        #else
        _mapper = StateObject(wrappedValue: JavVerseMapper(scope: scope))
        #endif
    }
    var body: some View {
        List {
            Section {
                Text(isLive ? "实时 · Grok 来源，非 AVDB 分数" : "静态快照，非实时 · Grok 来源，非 AVDB 分数").font(.caption)
                    .foregroundStyle(isLive ? Color.green : Color.orange)
                DisclosureGroup("采集时间与评分规则") {
                    Text("采集 UTC：\(capturedAt)").font(.caption)
                    Text("来源：https://javverse.com/actresses/top250").font(.caption).textSelection(.enabled)
                    Text("综合：总分降序，同分按作品分、日文姓名、ID；其他维度同分并列（如1、1、3），按日文姓名、ID排列。现役/引退过滤后按原站规则重新编号。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("分数保留原值，六维为作品、人气、颜值、身材、行业认可、生涯长度。AVDB身份未唯一匹配时不猜头像或直达。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: 12) {
                        Text(String(format: "%02d", row.rank)).font(.headline.monospacedDigit()).frame(width: 34)
                        JavVerseArtwork(entry: row.entry, mapper: mapper).frame(width: 64, height: 88)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(row.person.nameZh).accessibilityIdentifier("javverse-grok-\(row.person.id)")
                            Text("\(row.person.nameJa) · \(row.person.years) · \(row.person.status)").font(.caption).foregroundStyle(.secondary)
                            Text("Grok \(metric.title)：\(row.person.scoreText[metric.rawValue] ?? "—")").font(.subheadline.monospacedDigit())
                                .accessibilityIdentifier("javverse-grok-score-\(row.person.id)")
                            if let actor = mapper.actor(for: row.entry) {
                                Text(mapper.messages[row.entry.id] ?? "已匹配").font(.caption).foregroundStyle(.secondary)
                                NavigationLink("AVDB 演员资料") { ActorDetailView(actorID: actor.id) }
                                    .accessibilityIdentifier("javverse-actor-open-\(row.rank)")
                            } else {
                                Text(mapper.messages[row.entry.id] ?? "尚未核验AVDB身份；无头像不代表榜单缺项")
                                    .font(.caption).foregroundStyle(.secondary)
                                let choices = mapper.candidates(for: row.entry)
                                if !choices.isEmpty {
                                    NavigationLink("确认候选（\(choices.count)）") {
                                        JavVerseActorConfirmView(title: row.person.nameZh, actors: choices)
                                    }
                                    .font(.caption)
                                    .accessibilityIdentifier("javverse-confirm-\(row.rank)")
                                }
                                Button("单独核验 / 重试") { mapper.resolve([row.entry], retry: true) }.disabled(mapper.busy)
                            }
                        }
                    }
                    .onAppear { if row.id == rows.last?.id { onNearEnd() } }
                }
            }
        }
        .task(id: rows.count) { await mapper.resolve(rows.map(\.entry))?.value }
        .onDisappear { mapper.cancel() }
    }
}
