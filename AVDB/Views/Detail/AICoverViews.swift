import SwiftUI
import UIKit

/// Build 285/286: 「AI 增强」 controls for the detail hero (below the art, in the metadata area) and the fullscreen viewer.
/// Standalone (only the enhancer model), so the simulator screenshot host can compile it as is.
enum AICoverStyle {
    static let gradient = tinted(1)
    static func tinted(_ alpha: Double) -> LinearGradient {
        LinearGradient(colors: [Color(red: 0.62, green: 0.45, blue: 1.0).opacity(alpha), Color(red: 0.28, green: 0.78, blue: 1.0).opacity(alpha)],
                       startPoint: .leading, endPoint: .trailing)
    }
}

/// Small 「AI 增强」 badge shown whenever the displayed raster is the AI result.
struct AICoverBadge: View {
    var compact = false
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles").font(.system(size: compact ? 10 : 11, weight: .bold))
            Text("AI 增强").font(.system(size: compact ? 11 : 12, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 8 : 10).padding(.vertical, compact ? 4 : 5)
        .background(AICoverStyle.tinted(0.92), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AI 增强")
        .accessibilityIdentifier("ai-cover-badge")
    }
}

/// Circular determinate progress ring.
struct AICoverProgressRing: View {
    let value: Double
    var size: CGFloat = 16
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: 2.2)
            Circle().trim(from: 0, to: max(0.02, value))
                .stroke(AICoverStyle.gradient, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.2), value: value)
        }
        .frame(width: size, height: size)
    }
}

/// Hold-to-compare: while pressed, the original raster is shown.
struct AICoverHoldToCompare: ViewModifier {
    @ObservedObject var model: AICoverEnhanceModel
    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if model.isEnhanced && !model.showingOriginal { model.showingOriginal = true; UIImpactFeedbackGenerator(style: .light).impactOccurred() } }
                .onEnded { _ in if model.isEnhanced { model.showingOriginal = false } }
        )
    }
}

/// Build 286: hold the cover itself to see the original raster (long-press, then keep holding).
/// A plain tap still opens the viewer; scrolling cancels the long press before it begins.
struct AICoverPressToCompare: ViewModifier {
    @ObservedObject var model: AICoverEnhanceModel
    @GestureState private var holding = false
    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.28, maximumDistance: 12)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .updating($holding) { value, state, _ in
                        if case .second(true, _) = value { state = true }
                    },
                including: model.isEnhanced ? .all : .subviews)
            .onChange(of: holding) { _, now in
                guard model.isEnhanced else { return }
                if now { model.lastCompareEnded = .distantFuture; UIImpactFeedbackGenerator(style: .light).impactOccurred() } else { model.lastCompareEnded = Date() }
                model.showingOriginal = now
            }
            .accessibilityAction(named: "对比原图") { if model.isEnhanced { model.showingOriginal.toggle() } }
    }
}

/// Build 286: the AI 增强 state lives in the metadata area BELOW the cover art (never over it).
/// idle → 「✦ AI 增强」 button · running → ring + % (tap cancels) · done → badge + 「按住对比」 ·
/// holding → 「原图」. A one-off 「长按封面也可对比原图」 hint fades out after ~1.6 s.
struct AICoverMetaChip: View {
    @ObservedObject var model: AICoverEnhanceModel
    let openViewer: () -> Void
    @State private var hint = false
    @State private var hintTask: Task<Void, Never>?

    static func visible(_ model: AICoverEnhanceModel) -> Bool {
        switch model.phase {
        case .ineligible: return false
        case .idle: return model.canEnhance
        case .running, .done, .failed: return true
        }
    }

    var body: some View {
        ZStack {
            switch model.phase {
            case .ineligible:
                EmptyView()
            case .idle:
                if model.canEnhance {
                    Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); model.toggle() } label: {
                        pill(stroke: true) {
                            Image(systemName: "sparkles").font(.system(size: 10, weight: .bold))
                            Text("AI 增强").font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ai-cover-enhance-button")
                }
            case .running(let p):
                Button { model.cancel() } label: {
                    pill(stroke: true) {
                        AICoverProgressRing(value: p, size: 12)
                        Text(verbatim: model.cloudFetching ? "云端加载中" : "AI 增强中 \(Int((p * 100).rounded()))%").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).opacity(0.7)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: model.cloudFetching ? "云端加载中" : "AI 增强中 \(Int((p * 100).rounded()))%"))
                .accessibilityHint("轻点取消")
                .accessibilityIdentifier("ai-cover-progress")
            case .done:
                HStack(spacing: 0) {
                    Button(action: openViewer) {
                        HStack(spacing: 4) {
                            Image(systemName: model.showingOriginal ? "photo" : "sparkles").font(.system(size: 10, weight: .bold))
                            Text(model.showingOriginal ? "原图" : "AI 增强").font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.leading, 10).padding(.trailing, 8).frame(height: 26)
                        .background(model.showingOriginal ? AnyShapeStyle(Color.white.opacity(0.22)) : AnyShapeStyle(AICoverStyle.tinted(0.9)), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(model.showingOriginal ? "原图" : "AI 增强")
                    .accessibilityHint("轻点查看大图")
                    .accessibilityIdentifier("ai-cover-badge")
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.lefthalf.inset.filled").font(.system(size: 10, weight: .semibold))
                        Text(hint ? "长按封面也可对比原图" : (model.showingOriginal ? "松开恢复" : "按住对比"))
                            .font(.system(size: 12, weight: .medium))
                            .contentTransition(.opacity)
                    }
                    .padding(.leading, 8).padding(.trailing, 10).frame(height: 26)
                    .contentShape(Rectangle())
                    .modifier(AICoverHoldToCompare(model: model))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("按住对比原图")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { model.showingOriginal.toggle() }
                    .accessibilityIdentifier("ai-cover-compare")
                }
                .padding(2)
                .foregroundStyle(.white)
                .background(.black.opacity(0.22), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 0.5))
            case .failed(let text):
                Button { model.toggle() } label: {
                    pill(stroke: false) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
                        Text(text + " · 重试").font(.system(size: 12, weight: .medium)).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ai-cover-failed")
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.phase)
        .animation(.easeInOut(duration: 0.25), value: hint)
        .onChange(of: model.phase) { old, new in
            // Fresh result (not a cache hit on open): show the cover long-press hint briefly.
            guard new == .done, case .running = old else { return }
            hintTask?.cancel(); hint = true
            hintTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                if !Task.isCancelled { hint = false }
            }
        }
        .onDisappear { hintTask?.cancel() }
    }

    private func pill<C: View>(stroke: Bool, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 5, content: content)
            .foregroundStyle(.white)
            .padding(.horizontal, 11).frame(height: 28)
            .background(.black.opacity(0.22), in: Capsule())
            .overlay(Capsule().stroke(stroke ? AnyShapeStyle(AICoverStyle.tinted(0.8)) : AnyShapeStyle(Color.white.opacity(0.3)), lineWidth: 1))
            .contentShape(Capsule())
    }
}

/// Fullscreen cover viewer: pinch / double-tap zoom, 「AI 增强」 action, hold-to-compare.
struct AICoverViewer: View {
    let image: UIImage
    @ObservedObject var model: AICoverEnhanceModel
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        // Build 286: top bar / image / toolbar are stacked, so at 1× nothing overlays the cover.
        // Zoomed content is clipped to the image region instead of running under the controls.
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 38, height: 38).background(Color.white.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel("关闭").accessibilityIdentifier("ai-cover-viewer-close")
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
            GeometryReader { _ in
                Image(uiImage: model.display(image))
                    .resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(zoom).offset(offset)
                    .contentShape(Rectangle())
                    .gesture(MagnificationGesture()
                        .onChanged { zoom = min(6, max(1, lastZoom * $0)) }
                        .onEnded { _ in lastZoom = zoom; if zoom <= 1.01 { withAnimation(.spring()) { offset = .zero; lastOffset = .zero } } })
                    .simultaneousGesture(DragGesture()
                        .onChanged { v in guard zoom > 1 else { return }; offset = CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height) }
                        .onEnded { _ in lastOffset = offset })
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            if zoom > 1 { zoom = 1; lastZoom = 1; offset = .zero; lastOffset = .zero } else { zoom = 2.5; lastZoom = 2.5 }
                        }
                    }
                    .accessibilityIdentifier("ai-cover-viewer-image")
            }
            .clipped()
            toolbar.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
    }

    private var sizeText: String {
        let n = model.nativeSize
        guard n.width > 0 else { return "" }
        let native = "\(Int(n.width))×\(Int(n.height))"
        if let o = model.outputSize, model.isEnhanced { return "原图 \(native)  →  AI \(Int(o.width))×\(Int(o.height))" }
        return "原图 \(native)"
    }

    @ViewBuilder private var toolbar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                if model.isEnhanced {
                    if model.showingOriginal {
                        Text("原图").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3).background(Color.white.opacity(0.2), in: Capsule())
                    } else { AICoverBadge(compact: true) }
                }
                if !sizeText.isEmpty {
                    Text(sizeText).font(.system(size: 12, weight: .medium)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.85))
                        .accessibilityIdentifier("ai-cover-viewer-size")
                }
            }
            switch model.phase {
            case .done:
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap.fill").font(.system(size: 14, weight: .semibold))
                    Text(model.showingOriginal ? "松开显示 AI 增强" : "按住对比原图").font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(AICoverStyle.gradient, lineWidth: 1.2))
                .contentShape(Capsule())
                .modifier(AICoverHoldToCompare(model: model))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("ai-cover-viewer-compare")
            case .running(let p):
                VStack(spacing: 8) {
                    HStack {
                        AICoverProgressRing(value: p, size: 18)
                        Text(model.cloudFetching ? "云端加载中…" : "AI 增强中…").font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text(verbatim: "\(Int((p * 100).rounded()))%").font(.system(size: 15, weight: .semibold)).monospacedDigit()
                        Button { model.cancel() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 18)) }
                            .buttonStyle(.plain).accessibilityLabel("取消")
                    }
                    ProgressView(value: p).tint(Color(red: 0.45, green: 0.62, blue: 1.0))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("ai-cover-viewer-progress")
            case .idle, .failed:
                if model.canEnhance {
                    Button { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); model.toggle() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles").font(.system(size: 15, weight: .bold))
                            Text(failedText ?? "AI 增强").font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(AICoverStyle.gradient, in: Capsule())
                        .shadow(color: Color(red: 0.4, green: 0.5, blue: 1).opacity(0.45), radius: 12, y: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ai-cover-viewer-enhance")
                }
            case .ineligible:
                Text("已是高清原图，无需 AI 增强").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                    .accessibilityIdentifier("ai-cover-viewer-hq")
            }
        }
    }

    private var failedText: String? { if case .failed(let t) = model.phase { return t + "，轻点重试" }; return nil }
}

/// Build 285: 「AI 画质增强」 mode (自动 / 仅手动 / 关). Build 290: 云端增强图 (R2), local LRU cap, 仅 Wi‑Fi 上传,
/// 清除缓存 with current usage, cloud stats and copyable diagnostics.
struct AICoverSettingsSection: View {
    @AppStorage(AICoverEnhanceMode.defaultsKey) private var mode = AICoverEnhanceMode.auto.rawValue
    @AppStorage(AICoverCloudSettings.enabledKey) private var cloudOn = true
    @AppStorage(AICoverCloudSettings.capKey) private var capMB = AICoverCloudSettings.defaultCapMB
    @AppStorage(AICoverCloudSettings.wifiOnlyKey) private var wifiOnly = false
    @State private var cacheBytes = 0
    @State private var cacheFiles = 0
    @State private var stats = AICoverCloudStats.read()
    @State private var copied = false

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(AICoverStyle.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    Text("AI 封面画质增强").font(.body.weight(.medium))
                }
                Picker("AI 封面画质增强", selection: $mode) {
                    ForEach(AICoverEnhanceMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("ai-cover-mode-setting")
            }
            .padding(.vertical, 4)
            Toggle("云端增强图", isOn: $cloudOn).accessibilityIdentifier("ai-cover-cloud-toggle")
            Toggle("仅 Wi‑Fi 上传", isOn: $wifiOnly).disabled(!cloudOn).accessibilityIdentifier("ai-cover-cloud-wifi")
            Picker("本地缓存上限", selection: $capMB) {
                ForEach(AICoverCloudSettings.capChoicesMB, id: \.self) { Text(Self.mb($0)).tag($0) }
            }
            .accessibilityIdentifier("ai-cover-cache-cap")
            .onChange(of: capMB) { _, _ in AICoverDiskCache.shared.trimNow(); refreshSoon() }
            HStack {
                Text("本地缓存")
                Spacer()
                Text(verbatim: "\(ByteCountFormatter.string(fromByteCount: Int64(cacheBytes), countStyle: .file)) / \(Self.mb(capMB)) · \(cacheFiles) 张")
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            .accessibilityIdentifier("ai-cover-cache-usage")
            Button("清除缓存", role: .destructive) {
                AICoverDiskCache.shared.clear(); refresh()
            }
            .disabled(cacheBytes == 0)
            .accessibilityIdentifier("ai-cover-cache-clear")
            HStack {
                Text("云端")
                Spacer()
                Text(verbatim: "命中 \(stats.hits) · 未命中 \(stats.misses) · 上传 \(stats.uploads)（\(ByteCountFormatter.string(fromByteCount: Int64(stats.uploadBytes), countStyle: .file))）")
                    .foregroundStyle(.secondary).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            }
            .accessibilityIdentifier("ai-cover-cloud-stats")
            if stats.quotaFull {
                Label("云端空间将满（507），已暂停上传；仍可读取云端图，本机继续增强。", systemImage: "externaldrive.badge.exclamationmark")
                    .font(.footnote).foregroundStyle(.orange)
                    .accessibilityIdentifier("ai-cover-cloud-quota")
            }
            if !stats.configured {
                Label("此版本未配置云端密钥，仅本机增强。", systemImage: "key.slash").font(.footnote).foregroundStyle(.secondary)
            }
            Button {
                UIPasteboard.general.string = AICoverCloudStats.diagnostics()
                copied = true
            } label: {
                Label(copied ? "已复制诊断信息" : "复制云端诊断信息", systemImage: "doc.on.doc")
            }
            .accessibilityIdentifier("ai-cover-cloud-diagnostics")
        } header: {
            Text("AI 画质增强")
        } footer: {
            Text("内置超分辨率模型。只处理低清封面（如 800px 封套裁切、MGS 小图、JavDB 兜底图），DMM 等高清原图永不增强。自动：打开详情时自动增强（低电量模式或电量低于 20% 时暂停）；仅手动：点封面下方信息行里的「AI 增强」；关：不显示。云端增强图开启时，先从云端读取别人/自己已增强过的封面（约 2.5 秒超时，不影响原图显示），没有才在本机增强并在后台上传到云端；增强图不长期保存在手机上，本机只保留上限内的少量缓存。按住「按住对比」或长按封面可查看原图。")
        }
        .onAppear { refresh() }
    }

    static func mb(_ v: Int) -> String { v >= 1000 ? "\(v / 1000) GB" : "\(v) MB" }
    private func refresh() {
        cacheBytes = AICoverDiskCache.shared.totalBytes(); cacheFiles = AICoverDiskCache.shared.fileCount(); stats = AICoverCloudStats.read()
    }
    private func refreshSoon() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { refresh() } }
}

/// Snapshot for the settings rows and the copyable diagnostics (never includes the key itself).
struct AICoverCloudStats {
    var hits = 0, misses = 0, uploads = 0, uploadBytes = 0, failures = 0
    var quotaFull = false, configured = false
    var lastError: String?
    static func read(_ s: AICoverCloudSettings = .shared) -> AICoverCloudStats {
        AICoverCloudStats(hits: s.hits, misses: s.misses, uploads: s.uploads, uploadBytes: s.uploadBytes, failures: s.failures,
                          quotaFull: s.quotaFull(), configured: AICoverCloudConfig.appKey() != nil, lastError: s.lastError)
    }
    static func diagnostics() -> String {
        let s = AICoverCloudSettings.shared, st = read()
        let bundle = Bundle.main.infoDictionary
        return [
            "AVDB \(bundle?["CFBundleShortVersionString"] ?? "?") (\(bundle?["CFBundleVersion"] ?? "?")) AI 封面云端诊断",
            "云端: \(s.enabled ? "开" : "关") · 仅 Wi‑Fi 上传: \(s.wifiOnly ? "开" : "关") · 蜂窝/昂贵网络: \(AICoverNetworkState.isExpensive)",
            "端点: \(AICoverCloudConfig.bases().map(\.absoluteString).joined(separator: " → ")) · 前缀: \(AICoverCloudConfig.prefix)",
            "密钥: \(st.configured ? "已配置（构建时注入，不显示）" : "未配置")",
            "本地缓存: \(AICoverDiskCache.shared.totalBytes()) B / 上限 \(s.capBytes) B · \(AICoverDiskCache.shared.fileCount()) 个文件",
            "迁移保护至: \(AICoverMigration.protectBefore().map { "\($0.addingTimeInterval(AICoverMigration.grace))" } ?? "无")",
            "命中 \(st.hits) · 未命中 \(st.misses) · 上传 \(st.uploads) (\(st.uploadBytes) B) · 失败 \(st.failures)",
            "507 暂停上传: \(st.quotaFull ? "是，直到 \(s.quotaFullUntil.map { "\($0)" } ?? "?")" : "否")",
            "最近错误: \(st.lastError ?? "无")",
            "模型: \(AICoverSREngine.modelVersion)",
        ].joined(separator: "\n")
    }
}
