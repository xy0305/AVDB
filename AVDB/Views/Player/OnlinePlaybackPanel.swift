import SwiftUI

@MainActor
final class OnlinePlaybackModel: ObservableObject {
    enum State: Equatable {
        case idle, querying, found([OnlineLine]), failed(OnlineFailure)
        var label: String {
            switch self {
            case .idle: return "未查询"
            case .querying: return "查询中"
            case .found(let rows): return "找到 \(Set(rows.map(\.recordID)).count) 版本 / \(rows.count) 线路"
            case .failed(let error): return error.localizedDescription
            }
        }
    }
    @Published private(set) var states: [OnlineSource:State] = [:]
    @Published var plan: OnlinePlaybackPlan?
    @Published private(set) var resolving: String?
    @Published private(set) var resolutionMessage: String?
    private var tasks: [OnlineSource:Task<Void,Never>] = [:]
    private var epochs: [OnlineSource:UUID] = [:]
    private var selection: Task<Void,Never>?
    private var selectionEpoch = UUID()
    private var cache: [String:(Date,[OnlineLine])] = [:]
    private var namespace = UUID()
    private let provider: OnlineProvider
    init(provider: OnlineProvider = OnlineProvider()) {
        #if DEBUG && !ONLINE_CORE_TEST
        if ProcessInfo.processInfo.arguments.contains("--online-playback-fixture") {
            self.provider = OnlineProvider(transport: OnlineTransport(loader: { request in try OnlineNeutralFixture.response(request.url!) }))
            return
        }
        #endif
        self.provider = provider
    }
    var state: (OnlineSource) -> State { { self.states[$0] ?? .idle } }
    // The panel is inert on creation. Only explicit per-source buttons call query.
    func query(_ source: OnlineSource, number: String, versions: Bool) {
        guard resolving == nil else { return }
        if states[source] != .querying && states.values.filter({ $0 == .querying }).count >= 2 {
            resolutionMessage = "最多同时查询两个来源；请等待或取消一个查询。"; return
        }
        tasks[source]?.cancel()
        let epoch = UUID(); epochs[source] = epoch
        let key = namespace.uuidString + ":" + number + ":" + source.rawValue + ":" + String(versions)
        if let hit = cache[key], Date().timeIntervalSince(hit.0) < 120 { states[source] = .found(hit.1); return }
        states[source] = .querying
        tasks[source] = Task { [weak self] in
            guard let self else { return }
            do {
                let rows = try await Self.bounded { try await self.provider.discover(source, number: number, versions: versions) }
                guard !Task.isCancelled, self.epochs[source] == epoch else { return }
                if rows.isEmpty { self.states[source] = .failed(.noMatch) }
                else { self.states[source] = .found(rows); self.cache[key] = (Date(),rows) }
            } catch {
                guard !Task.isCancelled, self.epochs[source] == epoch else { return }
                self.states[source] = .failed(OnlineFailure.classify(error))
            }
        }
    }
    func choose(_ line: OnlineLine, number: String, versions: Bool) {
        selection?.cancel(); selectionEpoch = UUID(); let epoch = selectionEpoch
        resolving = line.id; resolutionMessage = "正在重新解析并验证 HLS 清单…"
        selection = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await Self.bounded { try await self.provider.resolve(line, number: number, versions: versions) }
                guard !Task.isCancelled, self.selectionEpoch == epoch else { return }
                self.plan = result; self.resolving = nil; self.resolutionMessage = nil
            } catch {
                guard !Task.isCancelled, self.selectionEpoch == epoch else { return }
                self.resolving = nil; self.resolutionMessage = OnlineFailure.classify(error).localizedDescription
            }
        }
    }
    static func bounded<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask { try await Task.sleep(nanoseconds: 25_000_000_000); throw OnlineFailure.timeout }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw OnlineFailure.cancelled }; return result
        }
    }
    func cancel(_ source: OnlineSource) {
        tasks[source]?.cancel(); tasks[source] = nil; epochs[source] = nil
        if states[source] == .querying { states[source] = .idle }
    }
    func cancelPending() {
        tasks.values.forEach { $0.cancel() }; tasks.removeAll(); epochs.removeAll()
        selection?.cancel(); selection = nil; selectionEpoch = UUID(); resolving = nil
        for source in OnlineSource.allCases where states[source] == .querying { states[source] = .idle }
    }
    func reset() { cancelPending(); namespace = UUID(); cache.removeAll(); states.removeAll(); plan = nil; resolutionMessage = nil }
}

#if !ONLINE_CORE_TEST
struct OnlinePlaybackPanel: View {
    let number: String
    @StateObject private var model = OnlinePlaybackModel()
    @State private var versions = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("在线播放 · 试验接入", systemImage: "play.rectangle").font(.headline)
            Text("真实媒体首帧尚未验证；TLS / 失效 / 受保护线路将明确报错，不能保证可播。").font(.caption).foregroundStyle(.secondary)
            Text("仅查询公开番号：\(number)").font(.subheadline).accessibilityIdentifier("online.public-number")
            Text("点击来源才会向对应第三方发送此番号；选择线路后重新解析并检查清单，不自动播放或替代 115。第三方可用性与内容授权不作保证；请仅使用你有权观看的内容。").font(.caption).foregroundStyle(.secondary)
            Toggle("包含明确标注的其他版本", isOn: $versions).font(.subheadline)
                .onChange(of: versions) { _, _ in model.reset() }
            ForEach(OnlineSource.allCases) { source in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(source.label).font(.subheadline.bold())
                        Spacer()
                        Button(model.state(source) == .querying ? "取消" : "查询") {
                            if model.state(source) == .querying { model.cancel(source) }
                            else { model.query(source, number: number, versions: versions) }
                        }.buttonStyle(.bordered).accessibilityIdentifier("online.query." + source.rawValue)
                    }
                    Text(model.state(source).label).font(.caption).accessibilityIdentifier("online.state." + source.rawValue)
                    if case .found(let rows) = model.state(source) {
                        ForEach(rows) { line in
                            Button {
                                model.choose(line, number: number, versions: versions)
                            } label: {
                                Label("\(line.code) · \(line.version) · 线路 \(line.lineKey == "0" ? "1" : line.lineKey)", systemImage: "play.circle")
                                    .font(.subheadline).multilineTextAlignment(.leading)
                            }.disabled(model.resolving != nil).accessibilityIdentifier("online.line." + line.id)
                        }
                    }
                }.padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            }
            if let message = model.resolutionMessage { Text(message).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("online.resolve-state") }
        }
        .padding(.horizontal)
        .accessibilityIdentifier("online.panel")
        .onChange(of: number) { _, _ in model.reset() }
        .onReceive(NotificationCenter.default.publisher(for: .avdbCatalogAccountChanged)) { _ in model.reset() }
        .onDisappear { model.cancelPending() }
        .fullScreenCover(item: $model.plan, onDismiss: { model.cancelPending() }) { plan in
            // Fresh identity creates ONE caption pipeline; never inherit JavDB/115 headers.
            KSChromePlayer(url: plan.url, title: plan.number, subtitle: plan.source.label,
                           headers: plan.headers, progressID: "online:" + plan.id.uuidString,
                           supportsFramePreview: false, publicSubtitleQuery: plan.number)
                .id(plan.id)
                .accessibilityIdentifier("online.native-player")
        }
    }
}

#endif
