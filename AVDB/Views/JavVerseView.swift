import SwiftUI

// AVDB's own loader decrypts tp.spfcas.com image streams. AsyncImage cannot decode them.
@MainActor private struct JavVerseArtwork: View {
    let entry: JavVerseEntry
    @ObservedObject var mapper: JavVerseMapper
    var body: some View {
        Group {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--javverse-neutral-ui"), mapper.movie(for: entry) != nil || mapper.actor(for: entry) != nil {
                Image(uiImage: JavVerseNeutralFixture.artwork).resizable().scaledToFit()
                    .accessibilityIdentifier("javverse-neutral-cover-\(entry.rank)")
            } else { production }
            #else
            production
            #endif
        }.clipped()
    }
    @ViewBuilder private var production: some View {
        if let movie = mapper.movie(for: entry) {
            let source = [movie.coverURL, movie.thumbURL].compactMap { $0 }.first { !$0.isEmpty }
            if let source {
                JavDBImage(url: source, fallbackURL: movie.thumbURL, contentMode: .fit, frontPoster: true)
            } else { Text("已匹配 · AVDB未提供图片").font(.caption2) }
        } else if let actor = mapper.actor(for: entry) {
            let source = [actor.avatarURL, actor.coverURL].compactMap { $0 }.first { !$0.isEmpty }
            if let source { JavDBImage(url: source, contentMode: .fit) }
            else { Text("已匹配 · AVDB未提供头像").font(.caption2) }
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
                    NavigationLink { JavVerseHomeView() } label: { Text("精选 / 其他榜单").font(.caption) }
                        .accessibilityIdentifier("javverse-other-boards")
                }.padding(.horizontal, 16).padding(.vertical, 10)
                if tab == .grok {
                    if let grok = snapshot.grok { JavVerseGrokView(snapshot: grok) }
                    else { Text("该快照尚无已核实的Grok名单").foregroundStyle(.secondary); Spacer() }
                } else if let selected {
                    // Identity replacement cancels old image work and resets paging before a new period renders.
                    JavVerseBoardView(board: selected).id(selected.selectionKey)
                } else { Text("该期暂无已核实快照"); Spacer() }
            } else if let failure { Text(failure).foregroundStyle(.red); Spacer() }
            else { ProgressView("读取本地榜单…"); Spacer() }
        }
        .navigationTitle("JavVerse 榜单")
        // Do not tag the parent container: SwiftUI propagates its identifier over child controls.
        .task {
            guard snapshot == nil else { return }
            let start = ProcessInfo.processInfo.systemUptime
            do {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--javverse-neutral-ui") { snapshot = try JavVerseNeutralFixture.snapshot() }
                else { snapshot = try JavVerseSnapshot.bundled() }
                #else
                snapshot = try JavVerseSnapshot.bundled()
                #endif
                #if DEBUG
                print("JAVVERSE241 metadataReadyMs=\((ProcessInfo.processInfo.systemUptime-start)*1000) rows=\(snapshot?.boards.reduce(0) { $0+$1.entries.count } ?? 0) noArtworkWait=true")
                #endif
            } catch { failure = error.localizedDescription }
        }
    }
}

@MainActor private struct JavVerseHomeView: View {
    @StateObject private var mapper = JavVerseMapper()
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--javverse-neutral-ui") {
            _mapper = StateObject(wrappedValue: JavVerseNeutralFixture.mapper())
        }
        #endif
    }
    @State private var snapshot: JavVerseSnapshot?
    @State private var failure: String?
    @State private var probe = "未测试设备HTTP；当前仅显示离线快照"
    @State private var probing = false
    @State private var probeGeneration = UUID()
    var body: some View {
        List {
            Section {
                Text("静态快照，非实时").font(.headline).foregroundStyle(.orange)
                Text("原站名单及顺序来自 JavVerse 公开文字；图片、资料和播放只通过 AVDB 核验。无网站账户或社区同步。")
                    .font(.footnote).foregroundStyle(.secondary)
                Text(probe).font(.caption)
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
                            NavigationLink { JavVerseBoardView(board: board) } label: { boardLabel(board) }
                                .accessibilityIdentifier("javverse-board-\(board.id)")
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
                            Text("采集 UTC：\(board.capturedAt) · 仅原站首页横栏")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("其他 FANZA 榜单") {
                    ForEach(snapshot.boards.filter { ["actresses", "series"].contains($0.id) }) { board in
                        NavigationLink { JavVerseBoardView(board: board) } label: { boardLabel(board) }
                            .accessibilityIdentifier("javverse-board-\(board.id)")
                    }
                }
                Section("来源边界") {
                    Text("销量历史期与Grok五分榜在榜单首页切换。所有名单均为带采集时间的静态快照；其他目录、社区、账户同步未接入。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let failure { Text(failure).foregroundStyle(.red) }
        }
        .navigationTitle("JavVerse · 原站名单")
        // Do not tag the parent container: SwiftUI propagates its identifier over child controls.
        .task(id: probing) {
            guard probing else { return }
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
                probe = "设备普通HTTP诊断（\(statuses.count)次，最多3次）：\(statuses.map(String.init).joined(separator: ", "))。" + (statuses.contains(403) ? "原站拒绝请求，仍为静态快照。" : "状态不证明有可用实时名单接口，仍为静态快照。")
            } catch {
                if !Task.isCancelled && probeGeneration == epoch { probe = "检测失败：\(error.localizedDescription)。仍为静态快照。" }
            }
        }
        .onDisappear { probeGeneration = UUID(); probing = false; mapper.cancel() }
        .task(id: snapshot != nil) {
            guard let snapshot else { return }
            await mapper.resolve(snapshot.boards.filter { ["featured", "recent"].contains($0.id) }.flatMap(\.entries))?.value
        }
        .task {
            guard snapshot == nil else { return }
            do {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--javverse-neutral-ui") {
                    snapshot = try JavVerseNeutralFixture.snapshot()
                    return
                }
                #endif
                snapshot = try JavVerseSnapshot.bundled()
            } catch { failure = error.localizedDescription }
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
    @StateObject private var mapper = JavVerseMapper()
    @State private var page = 0
    private var rows: [JavVerseEntry] { JavVersePagination.rows(board.entries, page: page) }
    init(board: JavVerseBoard) {
        self.board = board
        _mapper = StateObject(wrappedValue: JavVerseMapper(scope: board.selectionKey))
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--javverse-neutral-ui") {
            _mapper = StateObject(wrappedValue: JavVerseNeutralFixture.mapper())
        }
        #endif
    }
    var body: some View {
        List {
            Section {
                Text("静态快照，非实时").font(.caption).foregroundStyle(.orange)
                Text("期间：\(board.period)").font(.subheadline)
                    .accessibilityIdentifier("javverse-selected-period")
                DisclosureGroup("采集时间与来源") {
                    Text("采集时间 UTC：\(board.capturedAt)").font(.caption)
                    Text("来源：\(board.sourceURL)").font(.caption).textSelection(.enabled)
                    Text("保留原站名次，不补位。先显示文字名单；仅首6项异步核验AVDB图片，其余可单独核验，系列不猜映射。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if mapper.busy {
                    ProgressView("核验本页 \(mapper.completed)/\(mapper.total)")
                    Button("取消核验") { mapper.cancel() }
                } else {
                    Button("重试本页未匹配项") { mapper.resolve(rows, retry: true) }
                }
            }
            Section {
                ForEach(rows) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        Text(String(format: "%02d", entry.rank)).font(.headline.monospacedDigit()).frame(width: 34)
                        JavVerseArtwork(entry: entry, mapper: mapper).frame(width: 64, height: 88)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.label).textSelection(.enabled).accessibilityIdentifier("javverse-row-\(entry.rank)")
                            if let movie = mapper.movie(for: entry) {
                                NavigationLink("AVDB 资料与播放") { MovieDetailView(movieID: movie.id) }
                            } else if let actor = mapper.actor(for: entry) {
                                NavigationLink("AVDB 演员资料") { ActorDetailView(actorID: actor.id) }
                            } else if entry.kind == "movie" || entry.kind == "actor" {
                                Text(mapper.messages[entry.id] ?? "尚未请求").font(.caption).foregroundStyle(.secondary)
                                Button("单独核验 / 重试") { mapper.resolve([entry], retry: true) }.disabled(mapper.busy)
                            } else {
                                Text("系列未接映射 · 不使用网站数字ID直达AVDB").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section {
                HStack {
                    Button("上一页") { mapper.cancel(); page -= 1 }.disabled(page == 0)
                    Spacer()
                    Text("\(page + 1) / \(JavVersePagination.count(board.entries))").font(.caption)
                    Spacer()
                    Button("下一页") { mapper.cancel(); page += 1 }.disabled((page + 1) * 20 >= board.entries.count)
                }
            }
        }
        .navigationTitle(board.title)
        .task(id: page) { await mapper.resolve(Array(rows.prefix(6)))?.value }
        .onDisappear { mapper.cancel() }
    }
}

@MainActor private struct JavVerseGrokView: View {
    let snapshot: JavVerseGrokSnapshot
    @State private var metric: JavVerseGrokMetric = .total
    @State private var status: JavVerseGrokStatus = .all
    @State private var page = 0
    private var rows: [JavVerseGrokRow] { snapshot.rows(metric: metric, status: status) }
    private var pages: Int { max(1, (rows.count + 19) / 20) }
    private var current: [JavVerseGrokRow] { Array(rows.dropFirst(page * 20).prefix(20)) }
    private var key: String { "javverse|grok250|\(metric.rawValue)|static|\(snapshot.capturedAt)|\(status.rawValue)" }
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
            JavVerseGrokPage(rows: current, metric: metric, capturedAt: snapshot.capturedAt, scope: key)
                .id("\(key)|\(page)")
            HStack {
                Button("上一页") { page -= 1 }.disabled(page == 0)
                Spacer()
                Text("\(page + 1) / \(pages)").font(.caption)
                    .accessibilityIdentifier("javverse-grok-page")
                Spacer()
                Button("下一页") { page += 1 }.disabled(page + 1 >= pages)
            }.padding(.horizontal, 20).padding(.vertical, 10)
        }
        .onChange(of: metric) { _ in page = 0 }
        .onChange(of: status) { _ in page = 0 }
    }
}

@MainActor private struct JavVerseGrokPage: View {
    let rows: [JavVerseGrokRow]
    let metric: JavVerseGrokMetric
    let capturedAt: String
    @StateObject private var mapper: JavVerseMapper
    init(rows: [JavVerseGrokRow], metric: JavVerseGrokMetric, capturedAt: String, scope: String) {
        self.rows = rows; self.metric = metric; self.capturedAt = capturedAt
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
                Text("静态快照，非实时 · Grok 来源，非 AVDB 分数").font(.caption).foregroundStyle(.orange)
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
                                NavigationLink("AVDB 演员资料") { ActorDetailView(actorID: actor.id) }
                            } else {
                                Text(mapper.messages[row.entry.id] ?? "尚未核验AVDB身份；无头像不代表榜单缺项")
                                    .font(.caption).foregroundStyle(.secondary)
                                Button("单独核验 / 重试") { mapper.resolve([row.entry], retry: true) }.disabled(mapper.busy)
                            }
                        }
                    }
                }
            }
        }
        .task { await mapper.resolve(Array(rows.prefix(6)).map(\.entry))?.value }
        .onDisappear { mapper.cancel() }
    }
}
