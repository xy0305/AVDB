// Build 287 — live subtitle overlay, player-bar menu (字幕 关 / 日文 / 中文 / 双语), settings and status chip.
import SwiftUI
#if canImport(Translation)
import Translation
#endif

enum LiveSubtitleStyle {
    static let fontKey = "live.subtitle.fontPoints"
    static let positionKey = "live.subtitle.positionY"     // 0 = top … 1 = bottom of the free area
    static let japaneseScaleKey = "live.subtitle.jaScale"
    static let defaultFont = 20.0
    static let defaultPosition = 1.0
    static let defaultJapaneseScale = 0.78
    /// Height kept clear for the bottom chrome (progress bar + control row) while it is visible.
    static let chromeReserve: CGFloat = 118
}

/// Outline + soft shadow text. 8 hairline offsets give a solid stroke at any size; the blur keeps
/// legibility on bright frames without a box that would hide the picture.
struct LiveOutlinedText: View {
    var text: String
    var size: CGFloat
    var weight: Font.Weight = .semibold
    var color: Color = .white
    var italic = false
    @Environment(\.displayScale) private var displayScale
    var body: some View {
        let w = max(1, size / 14) / max(1, displayScale) * 2
        let t = Text(text).font(.system(size: size, weight: weight)).italic(italic)
        ZStack {
            ForEach(0 ..< 8, id: \.self) { i in
                let a = CGFloat(i) * .pi / 4
                t.foregroundStyle(.black.opacity(0.92)).offset(x: cos(a) * w, y: sin(a) * w)
            }
            t.foregroundStyle(color)
        }
        .multilineTextAlignment(.center)
        .shadow(color: .black.opacity(0.55), radius: 3, x: 0, y: 1)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct LiveSubtitleOverlay: View {
    var caption: LiveCaption
    var mode: LiveSubtitleMode
    var safeArea: EdgeInsets
    var chromeVisible: Bool
    var editing: Bool
    var finish: () -> Void
    @AppStorage(LiveSubtitleStyle.fontKey) private var points = LiveSubtitleStyle.defaultFont
    @AppStorage(LiveSubtitleStyle.positionKey) private var position = LiveSubtitleStyle.defaultPosition
    @AppStorage(LiveSubtitleStyle.japaneseScaleKey) private var jaScale = LiveSubtitleStyle.defaultJapaneseScale
    @GestureState private var drag: CGFloat = 0
    @State private var blockHeight: CGFloat = 60

    private var lines: (ja: String?, zh: String?) {
        if editing, caption.isEmpty { return (mode == .chinese ? nil : "字幕の位置をドラッグして調整", mode == .japanese ? nil : "拖动调整实时字幕位置") }
        return (caption.ja, caption.zh)
    }

    var body: some View {
        GeometryReader { geo in
            let top = safeArea.top + 64
            // Lift above the bottom controls while they are visible; never covers them.
            let bottom = safeArea.bottom + (chromeVisible || editing ? LiveSubtitleStyle.chromeReserve : 14)
            let travel = max(0, geo.size.height - top - bottom - blockHeight)
            let y = top + min(travel, max(0, CGFloat(min(1, max(0, position))) * travel + drag)) + blockHeight / 2
            let size = CGFloat(min(40, max(12, points)))
            let l = lines
            ZStack(alignment: .top) {
                if editing {
                    Color.black.opacity(0.001).contentShape(Rectangle()).onTapGesture {}
                    HStack {
                        Text("拖动实时字幕调整位置").font(.callout)
                        Spacer()
                        Button("重置") { position = LiveSubtitleStyle.defaultPosition }
                            .accessibilityIdentifier("live.subtitle.position.reset")
                        Button("完成", action: finish).accessibilityIdentifier("live.subtitle.position.done")
                    }
                    .foregroundStyle(.white).buttonStyle(.bordered)
                    .padding(12).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.leading, safeArea.leading + 12).padding(.trailing, safeArea.trailing + 12)
                    .padding(.top, safeArea.top + 8)
                }
                if l.ja != nil || l.zh != nil {
                    VStack(spacing: 3) {
                        if let zh = l.zh, !zh.isEmpty {
                            LiveOutlinedText(text: zh, size: size)
                                .accessibilityIdentifier("live.subtitle.zh")
                        }
                        if let ja = l.ja, !ja.isEmpty {
                            LiveOutlinedText(text: ja + (caption.partial ? " …" : ""), size: l.zh == nil ? size : size * CGFloat(jaScale),
                                             weight: l.zh == nil ? .semibold : .medium,
                                             color: l.zh == nil ? .white : Color(red: 1, green: 0.93, blue: 0.62),
                                             italic: caption.partial)
                                .opacity(caption.partial ? 0.86 : 1)
                                .accessibilityIdentifier(caption.partial ? "live.subtitle.partial" : "live.subtitle.ja")
                        }
                        if caption.pendingChinese, mode != .japanese {
                            ProgressView().controlSize(.mini).tint(.white).opacity(0.7)
                                .accessibilityIdentifier("live.subtitle.zh.pending")
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: min(geo.size.width - safeArea.leading - safeArea.trailing - 24, 900))
                    .background(GeometryReader { p in Color.clear.preference(key: LiveSubtitleHeightKey.self, value: p.size.height) })
                    .onPreferenceChange(LiveSubtitleHeightKey.self) { blockHeight = max(20, $0) }
                    .position(x: geo.size.width / 2 + (safeArea.leading - safeArea.trailing) / 2, y: y)
                    .animation(.easeOut(duration: 0.18), value: chromeVisible)
                    .gesture(DragGesture(minimumDistance: 2)
                        .updating($drag) { v, s, _ in if editing { s = v.translation.height } }
                        .onEnded { v in
                            guard editing, travel > 0 else { return }
                            position = Double(min(1, max(0, (CGFloat(position) * travel + v.translation.height) / travel)))
                        })
                    .allowsHitTesting(editing)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("live.subtitle.rendered")
                }
            }
        }
        .allowsHitTesting(editing)
    }
}

private struct LiveSubtitleHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 60
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Player-bar control: one tap menu with 关 / 日文 / 中文 / 双语 plus settings.
struct LiveSubtitleMenuButton: View {
    @ObservedObject var engine: LiveSubtitleEngine
    var openSettings: () -> Void
    var body: some View {
        Menu {
            Picker("实时字幕", selection: $engine.mode) {
                ForEach(LiveSubtitleMode.allCases) { m in Text(m.title).tag(m) }
            }
            Divider()
            Button { openSettings() } label: { Label("实时字幕设置…", systemImage: "slider.horizontal.3") }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: engine.mode == .off ? "captions.bubble" : "captions.bubble.fill")
                    .font(.system(size: 17, weight: .medium))
                Text(engine.mode == .off ? "字幕" : engine.mode.title)
                    .font(.caption.weight(.semibold)).lineLimit(1)
                if case .loading = engine.phase { ProgressView().controlSize(.mini).tint(.white) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).frame(minHeight: 48)
            .background(engine.mode == .off ? Color.clear : Color.white.opacity(0.18), in: Capsule())
            .contentShape(Rectangle())
        }
        .accessibilityLabel("实时字幕：\(engine.mode.title)")
        .accessibilityIdentifier("player.live.subtitle.menu")
    }
}

/// Small top-left chip: loading / paused-by-guard / reader errors. Never over the bottom controls.
struct LiveSubtitleStatusChip: View {
    @ObservedObject var engine: LiveSubtitleEngine
    var safeArea: EdgeInsets
    var body: some View {
        let text: String? = {
            switch engine.phase {
            case .loading(let m): return m
            case .paused(let why): return why
            case .failed(let m): return "实时字幕不可用：\(m)"
            default: return engine.mode == .off ? nil : engine.notice
            }
        }()
        if let text {
            HStack(spacing: 6) {
                if case .loading = engine.phase { ProgressView().controlSize(.mini).tint(.white) }
                Text(text).font(.caption.weight(.medium)).lineLimit(2)
                if engine.notice != nil, engine.phase == .running {
                    Button { engine.dismissNotice() } label: { Image(systemName: "xmark").font(.caption2.bold()) }.buttonStyle(.plain)
                }
                if case .failed = engine.phase {
                    Button { engine.retry() } label: {
                        Label("重试", systemImage: "arrow.clockwise").font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.white.opacity(0.22), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("live.subtitle.retry")
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.black.opacity(0.62), in: Capsule())
            .frame(maxWidth: 520, alignment: .leading)
            .padding(.top, safeArea.top + 62).padding(.leading, safeArea.leading + 16)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("live.subtitle.status")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct LiveSubtitleSettingsSheet: View {
    @ObservedObject var engine: LiveSubtitleEngine
    var adjustPosition: () -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage(LiveSubtitleStyle.fontKey) private var points = LiveSubtitleStyle.defaultFont
    @AppStorage(LiveSubtitleStyle.positionKey) private var position = LiveSubtitleStyle.defaultPosition
    @AppStorage(LiveSubtitleStyle.japaneseScaleKey) private var jaScale = LiveSubtitleStyle.defaultJapaneseScale
    @State private var cacheBytes = 0
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("显示", selection: $engine.mode) {
                        ForEach(LiveSubtitleMode.allCases) { m in Text(m.title).tag(m) }
                    }.pickerStyle(.segmented)
                        .accessibilityIdentifier("live.subtitle.settings.mode")
                } header: { Text("实时字幕（边播边识别，不预生成）") }
                Section {
                    LabeledContent("状态", value: engine.phaseText)
                        .accessibilityIdentifier("live.subtitle.settings.phase")
                    ForEach(engine.modelStatus, id: \.self) { Text($0).font(.caption).monospacedDigit() }
                    if case .failed = engine.phase {
                        Button { engine.retry() } label: { Label("重试加载", systemImage: "arrow.clockwise") }
                            .accessibilityIdentifier("live.subtitle.settings.retry")
                    }
                    Button {
                        UIPasteboard.general.string = engine.diagnosticReport()
                        copied = true
                    } label: { Label(copied ? "已复制诊断日志" : "复制诊断日志", systemImage: copied ? "checkmark" : "doc.on.doc") }
                        .accessibilityIdentifier("live.subtitle.settings.copylog")
                } header: { Text("模型状态与诊断") } footer: {
                    Text("自动模式先用 small 立即出字幕，同时在后台准备 large-v3-turbo，就绪后自动切换。turbo 首次在本机编译可能需要数分钟（每次安装/更新一次），请保持前台。全部使用 App 内置模型，不联网。")
                }
                Section("样式") {
                    HStack { Text("字号"); Slider(value: $points, in: 14 ... 36, step: 1); Text("\(Int(points))").monospacedDigit() }
                        .accessibilityIdentifier("live.subtitle.settings.font")
                    HStack { Text("日文比例"); Slider(value: $jaScale, in: 0.6 ... 1, step: 0.02); Text(String(format: "%.0f%%", jaScale * 100)).monospacedDigit() }
                    HStack { Text("位置"); Slider(value: $position, in: 0 ... 1); Text(position > 0.66 ? "底部" : position < 0.33 ? "顶部" : "中部") }
                        .accessibilityIdentifier("live.subtitle.settings.position")
                    Button("在画面上拖动调整位置") { adjustPosition() }
                        .accessibilityIdentifier("live.subtitle.settings.drag")
                }
                Section {
                    Picker("识别模型", selection: $engine.tierPreference) {
                        ForEach(LiveTierPreference.allCases) { t in Text(t.title).tag(t) }
                    }
                    LabeledContent("当前模型", value: engine.activeTier.map { "Whisper \($0.title)" } ?? "未加载")
                    LabeledContent("翻译引擎", value: engine.translatorName.isEmpty ? "未加载" : engine.translatorName)
                    LabeledContent("Apple 翻译", value: engine.appleStatus.title)
                    if engine.appleStatus == .needsDownload {
                        Button("下载 Apple 离线语言包（日语 → 简体中文）") { engine.requestApplePackDownload() }
                            .accessibilityIdentifier("live.subtitle.settings.apple.download")
                    }
                    HStack { Text("预读"); Slider(value: $engine.lead, in: 6 ... 40, step: 2); Text("\(Int(engine.lead)) 秒").monospacedDigit() }
                    if !engine.latencyText.isEmpty { LabeledContent("延迟", value: engine.latencyText).font(.caption) }
                } header: { Text("识别与翻译（全部在本机）") } footer: {
                    Text("在播放头前方预读音频并提前识别，字幕通常在台词开始前就已就绪；拖动进度后约 1–2 秒内先显示日文流式结果，中文随后。设备过热或低电量时自动切换 small 模型或暂停。")
                }
                Section("缓存") {
                    LabeledContent("已缓存字幕", value: ByteCountFormatter.string(fromByteCount: Int64(cacheBytes), countStyle: .file))
                    Button("清除实时字幕缓存", role: .destructive) { engine.clearCache(); cacheBytes = engine.cacheBytes }
                }
            }
            .navigationTitle("实时字幕")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .onAppear { cacheBytes = engine.cacheBytes }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("live.subtitle.settings")
    }
}

/// Hidden host for Apple Translation sessions (iOS 18–25 request loop and the pack-download prompt).
struct LiveTranslationHost: View {
    @ObservedObject var engine: LiveSubtitleEngine
    var body: some View {
        ZStack {
            #if canImport(Translation)
            if #available(iOS 18.0, *) { LiveBridgeSlot(engine: engine) }
            #endif
        }
        .frame(width: 1, height: 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#if canImport(Translation)
@available(iOS 18.0, *)
private struct LiveBridgeSlot: View {
    @ObservedObject var engine: LiveSubtitleEngine
    var body: some View {
        if let bridge = engine.appleBridgeBox as? AppleTranslationBridge { AppleBridgeHost(bridge: bridge) }
    }
}

@available(iOS 18.0, *)
private struct AppleBridgeHost: View {
    @ObservedObject var bridge: AppleTranslationBridge
    var body: some View {
        Color.clear.frame(width: 1, height: 1)
            .translationTask(bridge.configuration) { session in await bridge.serve(session) }
    }
}
#endif
