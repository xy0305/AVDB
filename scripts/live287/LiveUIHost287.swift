// Build 287 UI host (simulator screenshots). Production views: LiveSubtitleOverlay, LiveOutlinedText,
// LiveSubtitleMenuButton, LiveSubtitleStatusChip, LiveSubtitleSettingsSheet + LiveSubtitleCore caption logic.
// The engine is a fixture with the production engine's published surface (no models on the simulator);
// the player chrome is a neutral stand-in with the same reserved bottom height as KSChromePlayer.
import SwiftUI

@MainActor
final class LiveSubtitleEngine: ObservableObject {
    enum Phase: Equatable { case off, loading(String), running, paused(String), failed(String) }
    @Published var caption = LiveCaption(ja: nil, zh: nil, partial: false, pendingChinese: false)
    @Published var phase: Phase = .running
    @Published var notice: String?
    @Published var activeTier: LiveASRTier? = .turbo
    @Published var translatorName = "Apple 翻译 → NLLB-200 600M (本地)"
    @Published var appleStatus: AppleTranslationStatus = .needsDownload
    @Published var latencyText = "同步 18/18 · 平均滞后 0.00s · ASR 212ms"
    @Published var mode: LiveSubtitleMode = .bilingual { didSet { recompute() } }
    @Published var tierPreference: LiveTierPreference = .automatic
    @Published var lead: Double = 20
    let appleBridgeBox: AnyObject? = nil
    var store = LiveSegmentStore()
    var t = 3.0
    func requestApplePackDownload() {}
    func clearCache() {}
    var cacheBytes: Int { 18_432 }
    func dismissNotice() { notice = nil }
    // Build 288 surface
    @Published var modelStatus: [String] = ["large-v3-turbo：就绪（加载 8.4s） · 使用中", "small：就绪（加载 2.1s）", "NLLB 就绪 3.8s"]
    @Published var translatorStatus = ""
    var phaseText: String {
        switch phase {
        case .off: "关闭"
        case .loading(let s): s
        case .running: "运行中"
        case .paused(let s): "暂停：\(s)"
        case .failed(let s): "失败：\(s)"
        }
    }
    func retry() { phase = .loading("正在加载 small… 0:00") }
    func diagnosticReport() -> String { "AVDB 实时字幕诊断 (fixture)" }
    func recompute() { caption = store.caption(at: t, mode: mode) }
}

@main
struct LiveUIHost287App: App {
    var body: some Scene { WindowGroup { LiveHostScreen() } }
}

struct LiveHostScreen: View {
    @StateObject private var engine = LiveSubtitleEngine()
    @State private var chrome = false
    @State private var settings = false
    @State private var editing = false
    private let args = ProcessInfo.processInfo.arguments
    private func arg(_ k: String) -> String? { args.firstIndex(of: k).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }

    var body: some View {
        GeometryReader { geo in
            let safe = geo.safeAreaInsets
            ZStack {
                scene
                LiveSubtitleOverlay(caption: engine.caption, mode: engine.mode, safeArea: safe, chromeVisible: chrome, editing: editing) { editing = false }
                    .zIndex(21)
                if chrome { chromeMock(safe).zIndex(10) }
                LiveSubtitleStatusChip(engine: engine, safeArea: safe).zIndex(22)
            }
            .frame(width: geo.size.width + safe.leading + safe.trailing, height: geo.size.height + safe.top + safe.bottom)
            .ignoresSafeArea()
        }
        .background(Color.black)
        .statusBarHidden(true)
        .sheet(isPresented: $settings) { LiveSubtitleSettingsSheet(engine: engine, adjustPosition: { settings = false; editing = true }) }
        .onAppear(perform: configure)
    }

    /// Neutral "video frame": a soft daylight gradient with simple shapes (bright areas test the outline).
    private var scene: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.55, green: 0.75, blue: 0.95), Color(red: 0.95, green: 0.93, blue: 0.85)], startPoint: .top, endPoint: .bottom)
            Circle().fill(Color.white.opacity(0.85)).frame(width: 220).offset(x: 90, y: -160)
            RoundedRectangle(cornerRadius: 30).fill(Color(red: 0.42, green: 0.6, blue: 0.38)).frame(height: 260).frame(maxHeight: .infinity, alignment: .bottom).offset(y: 60)
            Text("示例画面").font(.caption).foregroundStyle(.black.opacity(0.25)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(24)
        }
    }

    private func chromeMock(_ safe: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            HStack { Image(systemName: "xmark").font(.system(size: 18, weight: .bold)).frame(width: 52, height: 52); Text("示例视频").font(.subheadline.weight(.medium)); Spacer() }
                .foregroundStyle(.white).padding(.horizontal, 20).padding(.top, 16 + safe.top)
            Spacer()
            HStack(spacing: 8) {
                Text("01:12").font(.caption.monospacedDigit())
                Capsule().fill(.white.opacity(0.35)).frame(height: 4).overlay(alignment: .leading) { Capsule().fill(.white).frame(width: 90, height: 4) }
                Text("24:00").font(.caption.monospacedDigit())
            }.foregroundStyle(.white).padding(.horizontal, 16 + max(safe.leading, safe.trailing))
            HStack(spacing: 12) {
                Image(systemName: "pause.fill").font(.system(size: 22, weight: .semibold)).frame(width: 48, height: 48)
                Image(systemName: "forward.fill").font(.system(size: 18, weight: .semibold)).frame(width: 48, height: 48)
                Spacer()
                LiveSubtitleMenuButton(engine: engine) { settings = true }.fixedSize()
                Text("播放源").font(.caption.weight(.medium))
            }
            .foregroundStyle(.white).padding(.horizontal, 16 + max(safe.leading, safe.trailing)).padding(.bottom, 10 + safe.bottom).padding(.top, 6)
        }
        .background(LinearGradient(colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom).allowsHitTesting(false))
    }

    private func configure() {
        var s = LiveSegmentStore()
        _ = s.insert(start: 1.0, end: 4.2, ja: "雨が降りそうだから、傘を持って行ってね。", tier: "turbo")
        if let seg = s.segments.first { s.setChinese(id: seg.id, "好像要下雨了，带上伞吧。") }
        if args.contains("--pending"), let seg = s.segments.first { s = LiveSegmentStore(); _ = s.insert(start: 1.0, end: 4.2, ja: seg.ja, tier: "turbo") }
        if args.contains("--partial") {
            s = LiveSegmentStore()
            s.partial = LiveSegment(id: 0, start: 2.0, end: 3.4, ja: "ちょっと待って、どこに", zh: nil, final: false, tier: "turbo")
        }
        engine.store = s
        if let m = arg("--mode").flatMap(LiveSubtitleMode.init(rawValue:)) { engine.mode = m } else { engine.recompute() }
        chrome = args.contains("--chrome")
        if args.contains("--settings") { settings = true }
        if args.contains("--editing") { editing = true }
        if args.contains("--thermal") { engine.phase = .paused("设备温度过高，实时字幕已暂停（降温后自动恢复）") }
        if args.contains("--loading") { engine.phase = .loading("正在加载 small… 0:03"); engine.mode = .bilingual; engine.activeTier = nil
            engine.modelStatus = ["small：加载中 0:03"] }
        if args.contains("--staged") {   // small already subtitling; turbo compiling in background (288 auto mode)
            engine.activeTier = .small; engine.notice = "large-v3-turbo 后台编译中（首次）1:12 · 先用 small"
            engine.modelStatus = ["large-v3-turbo：编译中（首次） 1:12", "small：就绪（加载 2.4s） · 使用中", "NLLB 就绪 3.9s"] }
        if args.contains("--failed") {
            engine.phase = .failed("small 模型加载超过 120 秒仍未完成（首次编译可能较慢）"); engine.activeTier = nil
            engine.modelStatus = ["large-v3-turbo：失败 — 加载超时", "small：失败 — small 模型加载超过 120 秒仍未完成"]
            engine.store = LiveSegmentStore(); engine.recompute() }
        if let f = arg("--font"), let v = Double(f) { UserDefaults.standard.set(v, forKey: LiveSubtitleStyle.fontKey) }
        if let p = arg("--position"), let v = Double(p) { UserDefaults.standard.set(v, forKey: LiveSubtitleStyle.positionKey) }
        else { UserDefaults.standard.set(LiveSubtitleStyle.defaultPosition, forKey: LiveSubtitleStyle.positionKey) }
        if arg("--font") == nil { UserDefaults.standard.set(LiveSubtitleStyle.defaultFont, forKey: LiveSubtitleStyle.fontKey) }
    }
}
