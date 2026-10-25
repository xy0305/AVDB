import SwiftUI

@MainActor
final class OnlinePlaybackModel: ObservableObject {
    enum State: Equatable {
        case idle, querying, found([OnlineLine]), failed(OnlineFailure)
        var label: String {
            switch self {
            case .idle: return "未查询"
            case .querying: return "查询中"
            case .found(let rows): return "找到候选，待解析 · \(Set(rows.map(\.recordID)).count) 版本 / \(rows.count) 线路"
            case .failed(let error): return error.localizedDescription
            }
        }
    }
    @Published private(set) var states: [OnlineSource:State] = [:]
    @Published var plan: OnlinePlaybackPlan?
    struct Resolution: Equatable {
        enum Status: Equatable { case resolving, validated, failed(OnlineFailure) }
        let line: OnlineLine
        var status: Status
        var label: String {
            let prefix = "\(line.source.label) · \(line.code) · 线路 \(line.lineKey)："
            switch status {
            case .resolving: return prefix + "正在重新解析并验证 HLS 清单…"
            case .validated: return prefix + "清单已验证，尚未确认首帧（若播放失败请重新查询，不自动换源）"
            case .failed(let error): return prefix + error.localizedDescription
            }
        }
    }
    @Published private(set) var resolving: String?
    @Published private(set) var resolutions: [OnlineSource:Resolution] = [:]
    @Published private(set) var queryMessages: [OnlineSource:String] = [:]
    private var selectedLine: OnlineLine?
    private var context: String?
    private func bind(number: String, versions: Bool) {
        let next = number + ":" + String(versions)
        if let context, context != next { reset() }
        context = next
    }
    private var tasks: [OnlineSource:Task<Void,Never>] = [:]
    private var epochs: [OnlineSource:UUID] = [:]
    private var selection: Task<Void,Never>?
    private var selectionEpoch = UUID()
    private var cache: [String:(Date,[OnlineLine])] = [:]
    private var namespace = UUID()
    static let proxyPreferenceKey = "online.systemProxyFakeIP.v1"
    @Published private(set) var systemProxyCompatibility: Bool
    private let preferences: UserDefaults
    private var provider: OnlineProvider
    init(provider: OnlineProvider = OnlineProvider(), preferences: UserDefaults = .standard) {
        self.preferences = preferences
        let enabled = preferences.bool(forKey: Self.proxyPreferenceKey)
        self.systemProxyCompatibility = enabled
        self.provider = OnlineProvider(transport: provider.transport.withDNSMode(enabled ? .systemProxy : .strict))
    }
    func setSystemProxyCompatibility(_ enabled: Bool) {
        guard enabled != systemProxyCompatibility else { return }
        // Invalidate generations before replacing policy; late strict/compat results
        // cannot populate states, candidate cache or a playback plan in the new mode.
        reset()
        provider = OnlineProvider(transport: provider.transport.withDNSMode(enabled ? .systemProxy : .strict))
        systemProxyCompatibility = enabled
        preferences.set(enabled, forKey: Self.proxyPreferenceKey)
    }
    var state: (OnlineSource) -> State { { self.states[$0] ?? .idle } }
    // The panel is inert on creation. Only explicit per-source buttons call query.
    func query(_ source: OnlineSource, number: String, versions: Bool) {
        guard states[source] != .querying else { return }
        bind(number: number, versions: versions)
        queryMessages[source] = nil
        if states[source] != .querying && states.values.filter({ $0 == .querying }).count >= 2 {
            queryMessages[source] = source.label + "：最多同时查询两个来源；请等待或取消一个查询。"; return
        }
        if selectedLine?.source == source { cancelSelection() }
        resolutions[source] = nil
        tasks[source]?.cancel()
        let epoch = UUID(); epochs[source] = epoch
        let key = namespace.uuidString + ":" + number + ":" + source.rawValue + ":" + String(versions)
        if let hit = cache[key], Date().timeIntervalSince(hit.0) < 120 { states[source] = .found(hit.1); return }
        states[source] = .querying
        let provider = self.provider
        tasks[source] = Task { [weak self] in
            guard let self else { return }
            do {
                let rows = try await Self.bounded { try await provider.discover(source, number: number, versions: versions) }
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
        guard resolving == nil else { return }
        bind(number: number, versions: versions)
        cancelSelection(); plan = nil
        selectionEpoch = UUID(); let epoch = selectionEpoch
        selectedLine = line; resolving = line.id
        resolutions[line.source] = Resolution(line: line, status: .resolving)
        let provider = self.provider
        selection = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await Self.bounded { try await provider.resolve(line, number: number, versions: versions) }
                guard !Task.isCancelled, self.selectionEpoch == epoch else { return }
                self.resolutions[line.source] = Resolution(line: line, status: .validated)
                self.plan = result; self.resolving = nil; self.selectedLine = nil
            } catch {
                guard !Task.isCancelled, self.selectionEpoch == epoch else { return }
                self.resolving = nil; self.selectedLine = nil
                self.resolutions[line.source] = Resolution(line: line, status: .failed(OnlineFailure.classify(error)))
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
    func cancelSelection() {
        selection?.cancel(); selection = nil; selectionEpoch = UUID()
        if let line = selectedLine, resolutions[line.source]?.status == .resolving {
            resolutions[line.source] = Resolution(line: line, status: .failed(.cancelled))
        }
        selectedLine = nil; resolving = nil
    }
    func cancelPending() {
        tasks.values.forEach { $0.cancel() }; tasks.removeAll(); epochs.removeAll()
        cancelSelection()
        for source in OnlineSource.allCases where states[source] == .querying { states[source] = .idle }
    }
    func reset() { cancelPending(); namespace = UUID(); context = nil; cache.removeAll(); states.removeAll(); plan = nil; resolutions.removeAll(); queryMessages.removeAll() }
}

#if !ONLINE_CORE_TEST
struct OnlinePlaybackPanel: View {
    let number: String
    @StateObject private var model = OnlinePlaybackModel()
    @State private var versions = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("在线播放 · 四源", systemImage: "play.rectangle").font(.headline)
            Text("清单验证通过才会交给播放器；来源拒绝、TLS 失败或协议未完成会停在该来源，不能保证四源都可播。").font(.caption).foregroundStyle(.secondary)
            Text("诊断：失败信息会显示域名、查询/详情/清单阶段与具体原因，不显示签名参数。默认严格 DNS 预检；不会更改你的 DNS 或代理设置。").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("online.diagnostic-help")
            Toggle("系统代理/Fake-IP兼容", isOn: Binding(get: { model.systemProxyCompatibility }, set: { model.setSystemProxyCompatibility($0) }))
                .accessibilityIdentifier("online.system-proxy-compatibility")
            Text("仅在你信任当前系统代理路由时开启。仅对已允许站点及已批准媒体域名接受 198.18.0.0/15 合成 DNS（含 mapped IPv6 / 标准 NAT64）；不支持 fd27 或其他私网。仍使用原域名 HTTPS 和正常 TLS 校验。会降低连接地址预检保证，无法验证代理内部最终目的地；这不是 DNS pinning，也不是播放器全生命周期网络沙箱。切换会取消旧查询/解析并清空候选缓存，请重新点击来源查询。").font(.caption).foregroundStyle(.secondary)
            Text("仅查询公开番号：\(number)").font(.subheadline).accessibilityIdentifier("online.public-number")
            Text("点击来源才会向对应第三方发送此番号；选择线路后重新解析并检查清单，不自动播放或替代 115。第三方可用性与内容授权不作保证；请仅使用你有权观看的内容。").font(.caption).foregroundStyle(.secondary)
            Toggle("包含 Jable / MissAV 明确标注的其他版本", isOn: $versions).font(.subheadline)
                .onChange(of: versions) { _, _ in model.reset() }
            if model.resolving != nil { Button("取消解析") { model.cancelSelection() }.buttonStyle(.bordered) }
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
                    Text(model.state(source).label).font(.caption)
                        .accessibilityLabel(Text(model.state(source).label))
                        .accessibilityAddTraits(.isStaticText)
                        .accessibilityIdentifier("online.state." + source.rawValue)
                    if let message = model.queryMessages[source] {
                        Text(message).font(.caption).accessibilityIdentifier("online.query-state." + source.rawValue)
                    }
                    if let resolution = model.resolutions[source] {
                        Text(resolution.label).font(.caption).foregroundStyle(.secondary)
                            .accessibilityLabel(Text(resolution.label))
                            .accessibilityAddTraits(.isStaticText)
                            .accessibilityIdentifier("online.resolve." + source.rawValue)
                    }
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
        }
        .padding(.horizontal)
        .onChange(of: number) { _, _ in model.reset() }
        .onReceive(NotificationCenter.default.publisher(for: .avdbCatalogAccountChanged)) { _ in model.reset() }
        .onDisappear { model.cancelPending() }
        .fullScreenCover(item: $model.plan, onDismiss: { model.cancelPending() }) { plan in
            // Fresh identity creates ONE caption pipeline; never inherit JavDB/115 headers.
            KSChromePlayer(url: plan.url, title: plan.number, subtitle: plan.source.label,
                           headers: plan.headers, progressID: "online:" + plan.id.uuidString,
                           supportsFramePreview: false, publicSubtitleQuery: plan.number)
                .id(plan.id)
        }
    }
}

#endif
