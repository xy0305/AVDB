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
            case .failed(let error): return error.presentation(at: .discovery).display
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
            case .failed(let error): return prefix + error.presentation(at: .document).display
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
        bind(number: number, versions: versions)
        guard states[source] != .querying else { return }
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
                self.states[source] = .failed(OnlineFailure.captured(error, at: .discovery))
            }
        }
    }
    func choose(_ line: OnlineLine, number: String, versions: Bool) {
        bind(number: number, versions: versions)
        guard resolving == nil else { return }
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
                self.resolutions[line.source] = Resolution(line: line, status: .failed(OnlineFailure.captured(error, at: .document)))
            }
        }
    }
    static func bounded<T: Sendable>(nanoseconds: UInt64 = 25_000_000_000, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await PlaybackDeadline<T>.run(nanoseconds: nanoseconds, work: work)
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
import SwiftUI

/// Compact peer actions shared by the detail screen and the offline UI host.
struct PlaybackResourceActions: View {
    let onlineAvailable: Bool
    let play115: () -> Void
    let openOnline: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            resourceButton("115 原画", icon: "play.fill", id: "detail.resource.115", action: play115)
            if onlineAvailable {
                resourceButton("在线播放", icon: "play.rectangle", id: "detail.resource.online", action: openOnline)
            }
        }
        .accessibilityIdentifier("detail.resource.actions")
    }
    private func resourceButton(_ title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

struct OnlinePlaybackSheet: View {
    let number: String
    @ObservedObject var model: OnlinePlaybackModel
    @Binding var versions: Bool
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                OnlinePlaybackPanel(number: number, model: model, versions: $versions)
                    .padding(.vertical, 16)
            }
            .navigationTitle("在线播放")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("关闭") { dismiss() }.accessibilityIdentifier("online.close")
            } }
            .accessibilityIdentifier("online.sheet")
        }
        .onDisappear { model.cancelPending() }
    }
}

struct OnlinePlaybackPanel: View {
    let number: String
    @ObservedObject var model: OnlinePlaybackModel
    @Binding var versions: Bool
    @State private var advancedExpanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("公开番号：\(number)").font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("online.public-number")
            Text("点「发送番号查询」才会向该第三方发送此番号；选择候选后重新解析并验证清单。不自动查源或换源，请仅观看有权使用的内容。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(OnlineSource.allCases) { source in
                    sourceRow(source)
                    if source != OnlineSource.allCases.last { Divider().padding(.vertical, 10) }
                }
            }.padding(14).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            DisclosureGroup(isExpanded: $advancedExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("系统代理/Fake-IP兼容", isOn: Binding(get: { model.systemProxyCompatibility }, set: { model.setSystemProxyCompatibility($0) }))
                        .accessibilityIdentifier("online.system-proxy-compatibility")
                    Text("仅信任系统代理时开启；会降低连接地址预检保证，无法验证代理最终目的地。仅允许已批准域名的 198.18.0.0/15 合成 DNS（含 mapped IPv6 / 标准 NAT64），仍保留 HTTPS/TLS 校验；不支持 fd27 或其他私网。这不是 DNS pinning 或播放器全生命周期沙箱。切换会取消请求并清空候选，需重新主动查询。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Toggle("包含明确标注的其他版本", isOn: $versions).font(.subheadline)
                        .onChange(of: versions) { _, _ in model.reset() }
                    Text("诊断保留域名、阶段与原因，不显示签名参数。清单验证不代表已确认首帧；错误不会自动触发重试或替代 115。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("online.diagnostic-help")
                }.padding(.top, 12)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("高级设置").font(.subheadline.weight(.semibold))
                    Text(model.systemProxyCompatibility ? "系统代理兼容：已开启（已保存）" : "系统代理兼容：关闭 · 严格预检")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("online.proxy-status")
                }
            }.accessibilityIdentifier("online.advanced")
            if model.resolving != nil {
                Button("取消解析") { model.cancelSelection() }.buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 16)
        .onChange(of: number) { _, _ in model.reset() }
        .onReceive(NotificationCenter.default.publisher(for: .avdbCatalogAccountChanged)) { _ in model.reset() }
        .onDisappear { model.cancelPending() }
        .fullScreenCover(item: $model.plan, onDismiss: { model.cancelPending() }) { plan in
            KSChromePlayer(url: plan.url, title: plan.number, subtitle: plan.source.label,
                           headers: plan.headers, progressID: "online:" + plan.id.uuidString,
                           supportsFramePreview: false, publicSubtitleQuery: plan.number)
                .id(plan.id)
        }
    }
    private func sourceRow(_ source: OnlineSource) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.label).font(.subheadline.bold())
                    Text(model.state(source).label).font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("online.state." + source.rawValue)
                }
                Spacer(minLength: 4)
                Button(model.state(source) == .querying ? "取消" : "发送番号查询") {
                    if model.state(source) == .querying { model.cancel(source) }
                    else { model.query(source, number: number, versions: versions) }
                }.font(.caption.weight(.semibold)).buttonStyle(.bordered)
                    .accessibilityIdentifier("online.query." + source.rawValue)
            }
            if let message = model.queryMessages[source] {
                Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("online.query-state." + source.rawValue)
            }
            if let resolution = model.resolutions[source] {
                Text(resolution.label).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("online.resolve." + source.rawValue)
            }
            if case .found(let rows) = model.state(source) {
                DisclosureGroup("候选线路（\(rows.count)）") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(rows) { line in
                            Button {
                                model.choose(line, number: number, versions: versions)
                            } label: {
                                Label("\(line.code) · \(line.version) · 线路 \(line.lineKey == "0" ? "1" : line.lineKey)", systemImage: "play.circle")
                                    .font(.subheadline).multilineTextAlignment(.leading)
                            }.disabled(model.resolving != nil).accessibilityIdentifier("online.line." + line.id)
                        }
                    }.padding(.top, 8)
                }.font(.subheadline)
            }
        }
    }
}

#endif
