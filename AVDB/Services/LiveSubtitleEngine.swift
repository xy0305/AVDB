// Build 289 — SenseVoice default, Apple on-device fallback (heat / falling behind), Whisper manual only (never
// compiled unless selected), utility-QoS worker, thermal-throttled read-ahead, main-thread hitch counter.
// Build 288 — staged model loading (small first, turbo warmed in background), timeouts + retry, diagnostics.
// Build 287 — live subtitle engine: look-ahead reader → VAD → Whisper → (Apple Translation | NLLB) → overlay.
// Nothing is generated ahead of playback beyond the ~lead window the reader keeps in front of the playhead;
// segments are cached per video and reused on rewatch.
import Combine
import Foundation
import SwiftUI
import UIKit
#if os(iOS)
import os
#endif

/// One in-flight load per tier, shared by every engine/player session (re-attaching never starts a second
/// compile), with a wall-clock timeout that fails the *wait* — the Core ML compile itself keeps going in the
/// background and its result is kept for the next attempt.
@MainActor
final class LiveModelLoader {
    static let shared = LiveModelLoader()
    enum State: Equatable { case idle, loading(since: Date), ready(seconds: Double), failed(String) }
    private(set) var states: [LiveASRTier: State] = [:]
    private var ready: [LiveASRTier: LiveSpeechRecognizer] = [:]
    private var tasks: [LiveASRTier: Task<LiveSpeechRecognizer, Error>] = [:]
    struct Timeout: LocalizedError {
        let tier: LiveASRTier, seconds: Double
        var errorDescription: String? { "\(tier.title) 模型加载超过 \(Int(seconds)) 秒仍未完成（首次编译可能较慢）" }
    }

    func state(_ t: LiveASRTier) -> State { states[t] ?? .idle }
    func cached(_ t: LiveASRTier) -> LiveSpeechRecognizer? { ready[t] }
    var isLoadingAny: Bool { states.values.contains { if case .loading = $0 { return true }; return false } }

    func release(_ t: LiveASRTier) {
        guard ready[t] != nil else { return }
        ready[t] = nil; states[t] = .idle
        LiveDiagnostics.shared.log("\(t.rawValue): 已释放")
    }

    /// Lets a failed tier be retried (a load still running is never restarted — retry just waits again).
    func resetFailures() { for (t, s) in states { if case .failed = s { states[t] = .idle } } }

    func get(_ tier: LiveASRTier, timeout: Double) async throws -> LiveSpeechRecognizer {
        if let r = ready[tier] { return r }
        let task: Task<LiveSpeechRecognizer, Error>
        if let t = tasks[tier] { task = t; LiveDiagnostics.shared.log("\(tier.rawValue): 复用进行中的加载") }
        else {
            let avail = Double(LiveMemory.availableMB)
            LiveDiagnostics.shared.log("\(tier.rawValue): 请求加载 可用内存 \(Int(avail)) MB")
            states[tier] = .loading(since: Date())
            task = Task.detached(priority: .utility) { () async throws -> LiveSpeechRecognizer in
                try await LiveRecognizerFactory.load(tier, log: { LiveDiagnostics.shared.log($0) })
            }
            tasks[tier] = task
            Task { [weak self] in
                do {
                    let r = try await task.value
                    self?.ready[tier] = r
                    self?.states[tier] = .ready(seconds: LiveRecognizerFactory.loadSeconds(r))
                    UserDefaults.standard.set(LiveRecognizerFactory.loadSeconds(r), forKey: "live.load.\(tier.rawValue)")
                } catch {
                    self?.states[tier] = .failed(error.localizedDescription)
                    LiveDiagnostics.shared.log("\(tier.rawValue): 加载失败 \(error)")
                }
                self?.tasks[tier] = nil
            }
        }
        return try await withThrowingTaskGroup(of: LiveSpeechRecognizer.self) { g in
            g.addTask { try await task.value }
            g.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw Timeout(tier: tier, seconds: timeout)
            }
            defer { g.cancelAll() }
            guard let r = try await g.next() else { throw Timeout(tier: tier, seconds: timeout) }
            return r
        }
    }
}

enum LiveMemory {
    /// App-available memory (jetsam headroom) on device; physical memory elsewhere.
    static var availableMB: Int {
        #if os(iOS) && !targetEnvironment(simulator)
        return Int(os_proc_available_memory() / 1_048_576)
        #else
        return Int(ProcessInfo.processInfo.physicalMemory / 1_048_576)
        #endif
    }
}

@MainActor
final class LiveSubtitleEngine: ObservableObject {
    enum Phase: Equatable {
        case off
        case loading(String)
        case running
        case paused(String)          // guard: thermal / battery
        case failed(String)
    }

    @Published private(set) var caption = LiveCaption(ja: nil, zh: nil, partial: false, pendingChinese: false)
    @Published private(set) var phase: Phase = .off
    @Published private(set) var notice: String?
    @Published private(set) var activeTier: LiveASRTier?
    @Published private(set) var translatorName = ""
    @Published private(set) var appleStatus: AppleTranslationStatus = .unknown
    @Published private(set) var latencyText = ""
    /// Per-model status lines for the settings sheet: 加载中 / 编译中（首次） / 就绪 / 失败原因.
    @Published private(set) var modelStatus: [String] = []
    @Published private(set) var translatorStatus = ""
    /// Apple on-device Japanese recognition (fallback) availability.
    @Published private(set) var appleASRStatus: AppleASRStatus = .unknown
    enum TurboDownload: Equatable { case idle, downloading(Double), failed(String) }
    @Published private(set) var turboDownload: TurboDownload = .idle
    @Published private(set) var hitchText = ""
    /// 292: optional on-device LLM translator (Sakura-1.5B, downloaded on request; 机翻).
    @Published private(set) var llmDownload: TurboDownload = .idle
    @Published private(set) var llmStatus = ""
    @Published var llmEnabled: Bool = LiveLLMModel.enabled {
        didSet { LiveLLMModel.enabled = llmEnabled; applyLLMSetting() }
    }
    var llmDownloaded: Bool { LiveLLMModel.downloaded }
    var llmLinked: Bool { LiveLLMModel.linked }
    /// Title metadata names (actresses) → translation glossary.
    private var glossary: [LiveGlossaryEntry] = []
    private var llmLoadTask: Task<Void, Never>?
    private var llmGuardBadSince: Date?
    @Published var mode: LiveSubtitleMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: LiveSubtitleMode.defaultsKey)
            pipeline.mode = mode
            modeChanged(from: oldValue)
        }
    }
    @Published var tierPreference: LiveTierPreference {
        didSet { UserDefaults.standard.set(tierPreference.rawValue, forKey: LiveTierPreference.defaultsKey); restartForTier() }
    }
    /// Seconds of audio kept decoded ahead of the playhead (look-ahead = subtitles appear in sync).
    @Published var lead: Double = UserDefaults.standard.object(forKey: "live.subtitle.lead") as? Double ?? 20 {
        didSet { UserDefaults.standard.set(lead, forKey: "live.subtitle.lead") }
    }

    #if canImport(Translation)
    /// iOS 18–25 session host (and the pack-download prompt on every iOS 18+ version).
    let appleBridgeBox: AnyObject? = {
        if #available(iOS 18.0, *) { return AppleTranslationBridge() }
        return nil
    }()
    #endif

    private(set) var pipeline = LivePipeline()
    private let reader = LiveAudioReader()
    private let cache = LiveSubtitleCache()
    private var source: LiveAudioReader.Source?
    private var videoKey = ""
    private var clock: (@MainActor () -> (time: Double, rate: Double, playing: Bool))?
    private var worker: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var mtTask: Task<Void, Never>?
    private var loadingLabel = ""
    private var loadingSince = Date()
    private var memoryObserver: NSObjectProtocol?
    private var toastTask: Task<Void, Never>?
    private let hitches = LiveHitchMonitor()
    /// Session-only override: .apple after SenseVoice/Whisper fell behind, .senseVoice after a memory warning.
    private var sessionOverride: LiveASRTier?
    static let smallTimeout: Double = 120
    static let turboTimeout: Double = 900
    static func timeout(_ t: LiveASRTier) -> Double {
        switch t {
        case .senseVoice: 60
        case .apple: 120          // may include the one-time system model download
        case .small: smallTimeout
        case .turbo: turboTimeout
        }
    }
    private var asr: LiveSpeechRecognizer?
    private var mt: LiveTranslating?
    private var lastTick: (wall: Double, media: Double, rate: Double)?
    private var lastSavedCount = 0
    private var guardTier: LiveASRTier?
    /// 291 diagnostics + hysteresis.
    private var restarts = 0, hotSwaps = 0, readerCatchUps = 0
    private var degradedAt: Date?
    private var lastCatchUp = Date.distantPast
    private var swapTask: Task<Void, Never>?
    private var activeObservers: [NSObjectProtocol] = []
    /// State the reader thread reads without hopping to the main actor.
    private final class Shared: @unchecked Sendable {
        private let lock = NSLock()
        private var _pipeline = LivePipeline(), _playhead = 0.0, _rate = 1.0, _lead = 20.0
        private var _wall = Date().timeIntervalSinceReferenceDate, _playing = false
        func set(pipeline: LivePipeline? = nil, playhead: Double? = nil, rate: Double? = nil, lead: Double? = nil, playing: Bool? = nil) {
            lock.lock(); defer { lock.unlock() }
            if let pipeline { _pipeline = pipeline }
            if let playhead { _playhead = playhead; _wall = Date().timeIntervalSinceReferenceDate }
            if let rate { _rate = rate }
            if let lead { _lead = lead }
            if let playing { _playing = playing }
        }
        var pipeline: LivePipeline { lock.lock(); defer { lock.unlock() }; return _pipeline }
        /// 291: the reader paces against an extrapolated playhead. Before, the playhead only moved when the main
        /// actor ticked, so a multi-second main-thread hang froze the reader at `stale playhead + lead`; when the
        /// hang ended the reader was behind real playback and every line arrived late (→ the bogus Apple switch).
        var pace: (playhead: Double, rate: Double, lead: Double) {
            lock.lock(); defer { lock.unlock() }
            let dt = _playing ? min(30, max(0, Date().timeIntervalSinceReferenceDate - _wall)) : 0
            return (_playhead + dt * _rate, _rate, _lead)
        }
        var rawPlayhead: Double { lock.lock(); defer { lock.unlock() }; return _playhead }
    }
    private let shared = Shared()

    /// Translators are expensive to load: keep the chain alive across player sessions (recognizers live in
    /// LiveModelLoader).
    private static var sharedMT: LiveTranslating?
    private var loader: LiveModelLoader { .shared }

    init() {
        mode = LiveSubtitleMode(rawValue: UserDefaults.standard.string(forKey: LiveSubtitleMode.defaultsKey) ?? "") ?? .off
        tierPreference = LiveTierPreference.current
        pipeline.mode = mode
        UIDevice.current.isBatteryMonitoringEnabled = true
        LiveLLMModel.log = { LiveDiagnostics.shared.log($0) }
        wireReader()
        hitches.context = { [weak self] in
            guard let self else { return "" }
            let st = self.pipeline.snapshotStats
            return String(format: "· %@ %@ 队列%d 读取%+.1fs", self.activeTier?.rawValue ?? "-", self.phaseText, st.queued, st.decodedEnd - self.shared.rawPlayhead)
        }
        Task { appleStatus = await AppleTranslation.status() }
        Task { appleASRStatus = await AppleSpeechRecognizer.status() }
        memoryObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.memoryWarning() }
        }
    }

    var preferredTier: LiveASRTier { tierPreference.resolve(physicalMemory: ProcessInfo.processInfo.physicalMemory) }

    // MARK: lifecycle

    /// Attach to the current item. `clock` returns the player's media time, rate and playing state.
    func attach(url: URL, headers: [String: String], videoKey: String,
                clock: @escaping @MainActor () -> (time: Double, rate: Double, playing: Bool)) {
        let newSource = LiveAudioReader.Source(url: url, headers: headers)
        if source == newSource, self.videoKey == videoKey { self.clock = clock; return }
        // 291: same title, re-resolved URL / refreshed headers (quality switch, token refresh): keep the models,
        // pipeline and queued lines; only the reader reopens on the new source at the playhead.
        if self.videoKey == videoKey, !videoKey.isEmpty, source != nil, phase == .running {
            source = newSource; self.clock = clock
            let t = clock().time
            let start = pipeline.resumePoint(after: max(0, t - 1.5)) ?? max(0, t - 1.5)
            pipeline.reset(at: start); pipeline.setPlayhead(t)
            reader.start(newSource, at: start, generation: pipeline.currentGeneration)
            LiveDiagnostics.shared.log(String(format: "换源（同一视频）读取从 %.1fs 继续，不重启识别", start))
            return
        }
        detach()
        source = newSource
        self.videoKey = videoKey
        self.clock = clock
        guard mode != .off else { return }
        start(reason: "打开视频")
    }

    func detach() {
        saveCache(force: true)
        stopRunning()
        hitches.stop()
        source = nil
        videoKey = ""
        caption = LiveCaption(ja: nil, zh: nil, partial: false, pendingChinese: false)
        if mode != .off { phase = .off }
    }

    /// Explicit seek from the player chrome (jumps found by the ticker are handled the same way).
    func didSeek(to t: Double) {
        guard phase == .running else { return }
        restartReader(at: t)
    }

    private func modeChanged(from old: LiveSubtitleMode) {
        if mode == .off { saveCache(force: true); stopRunning(); hitches.stop(); phase = .off; caption = .init(ja: nil, zh: nil, partial: false, pendingChinese: false); return }
        if old == .off { start(reason: "开启字幕"); return }
        if mode.needsChinese, mt == nil { loadTranslatorInBackground() }
        refreshCaption()
    }

    private func restartForTier() {
        sessionOverride = nil
        guard mode != .off, source != nil else { return }
        saveCache(force: true)
        stopRunning()
        start(reason: "切换识别器（用户）")
    }

    /// 重试: clears failed states (an in-flight compile is awaited again, never restarted) and starts over.
    func retry() {
        LiveDiagnostics.shared.log("用户点击重试")
        loader.resetFailures()
        if mode == .off { mode = .bilingual; return }
        start(reason: "重试")
    }

    func diagnosticReport() -> String {
        LiveDiagnostics.shared.report(extra: ["模式 \(mode.rawValue) · 偏好 \(tierPreference.rawValue) · 当前 \(activeTier?.rawValue ?? "-") · 阶段 \(phaseText)",
                                              "可用内存 \(LiveMemory.availableMB) MB · 翻译 \(translatorName) · Apple 翻译 \(appleStatus) · Apple 识别 \(appleASRStatus.rawValue)",
                                              "热状态 \(ProcessInfo.processInfo.thermalState.rawValue) · 预读 \(Int(effectiveLead))s · \(latencyText) · \(hitchText)",
                                              pipeline.snapshotStats.stageLine, pipeline.snapshotStats.mtLine,
                                              "重启 \(restarts) · 热切换识别器 \(hotSwaps) · 读取追帧 \(readerCatchUps) · 读取重连 \(reader.failureCount) · 读取进度 \(String(format: "%.1f", pipeline.snapshotStats.decodedEnd - shared.rawPlayhead))s"]
                                              + hitches.worst.map { "卡顿 \($0)" } + modelStatus)
    }

    var phaseText: String {
        switch phase {
        case .off: "关闭"
        case .loading(let s): s
        case .running: "运行中"
        case .paused(let s): "暂停：\(s)"
        case .failed(let s): "失败：\(s)"
        }
    }

    private func memoryWarning() {
        LiveDiagnostics.shared.log("收到内存警告 可用 \(LiveMemory.availableMB) MB")
        guard let t = activeTier, t.isWhisper, LiveModels.senseVoiceAvailable else { return }
        sessionOverride = .senseVoice
        toast("内存不足，已切换 SenseVoice")
        saveCache(force: true)
        hotSwap(to: .senseVoice, why: "内存警告") { [weak self] in self?.loader.release(t) }
    }

    /// Small non-blocking notice in the top-left chip (never over subtitles or the centre); auto-hides.
    private func toast(_ text: String, seconds: Double = 5) {
        notice = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, self?.notice == text else { return }
            self?.notice = nil
        }
    }

    /// Recognizers to try, in order, for `target` (only ones whose files exist; Whisper only when chosen).
    private func candidates(for target: LiveASRTier) -> [LiveASRTier] {
        let order: [LiveASRTier]
        switch target {
        case .senseVoice: order = [.senseVoice, .apple]
        case .apple: order = [.apple, .senseVoice]
        case .small, .turbo: order = [target, .senseVoice, .apple]
        }
        return order.filter { t in
            guard LiveModels.available(t) else { return false }
            if t == .apple { return appleASRStatus != .unsupported && appleASRStatus != .denied }
            return true
        }
    }

    private func start(reason: String) {
        guard source != nil, clock != nil, mode != .off else { return }
        restarts += 1
        stopRunning()
        let verdict = currentVerdict()
        if case .pause(let why) = verdict { phase = .paused(why); toast(why); startTicker(); return }
        var target = sessionOverride ?? preferredTier
        if case .degrade(let t, let why) = verdict {
            guardTier = t
            // Heat / Low Power: hand over to Apple only when its Japanese model is already on the device —
            // otherwise keep SenseVoice and rely on the throttled read-ahead.
            if t == .apple, appleASRStatus != .installed {
                target = target.isWhisper ? .senseVoice : (target == .apple ? .senseVoice : target)
                toast(why.replacingOccurrences(of: "已切换苹果系统识别", with: "已降低识别负载"))
            } else { target = t; toast(why) }
        } else { guardTier = target }
        let list = candidates(for: target)
        guard let first = list.first else {
            phase = .failed("没有可用的识别模型（\(target.title)）")
            LiveDiagnostics.shared.log("无可用识别器 target=\(target.rawValue)")
            return
        }
        if first != target { toast("\(target.title) 不可用，改用 \(first.title)") }
        setLoading(first == .turbo && UserDefaults.standard.object(forKey: "live.load.turbo") == nil
                   ? "正在编译 \(first.title)（首次较慢）" : "正在加载 \(first.title)")
        LiveDiagnostics.shared.log("start target=\(target.rawValue) candidates=\(list.map(\.rawValue)) reason=\(reason) #\(restarts)")
        let key = cacheKey, cache = self.cache
        loadTask = Task { [weak self] in
            guard let self else { return }
            var lastError: Error?
            for t in list {
                do {
                    if t != first { self.setLoading("正在加载 \(t.title)") }
                    let asr = try await self.loader.get(t, timeout: Self.timeout(t))
                    guard !Task.isCancelled, self.mode != .off else { return }
                    self.asr = asr
                    self.activeTier = asr.tier
                    if t != first { self.toast("\(first.title) 加载失败，已改用 \(t.title)") }
                    LiveDiagnostics.shared.log("运行 \(asr.tier.rawValue)")
                    // 291: the per-video cache is decoded off the main thread.
                    let stored = key.isEmpty ? nil : await Task.detached(priority: .userInitiated) { cache.load(key) }.value
                    guard !Task.isCancelled, self.mode != .off else { return }
                    self.beginRunning(store: stored)
                    self.loadTranslatorInBackground()
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    lastError = error
                    LiveDiagnostics.shared.log("\(t.rawValue) 加载失败 \(error.localizedDescription)")
                }
            }
            self.phase = .failed(lastError?.localizedDescription ?? "识别模型加载失败")
        }
        startTicker()
    }

    private func setLoading(_ label: String) {
        loadingLabel = label
        loadingSince = Date()
        phase = .loading(label + "…")
    }

    // MARK: settings actions

    /// Downloads the Apple Japanese on-device model (iOS 26 asset inventory); user-initiated from settings.
    func prepareAppleASR() {
        Task {
            do { try await AppleSpeechRecognizer.installAssets() } catch { toast("苹果日语识别模型下载失败：\(error.localizedDescription)") }
            appleASRStatus = await AppleSpeechRecognizer.status()
            LiveDiagnostics.shared.log("Apple 识别状态 \(appleASRStatus.rawValue)")
        }
    }

    /// Whisper turbo is downloaded only when the user asks (≈ 632 MB); never compiled unless selected.
    func downloadTurbo() {
        guard turboDownload == .idle || { if case .failed = turboDownload { return true }; return false }() else { return }
        turboDownload = .downloading(0)
        Task {
            do {
                _ = try await LiveModels.downloadTurbo { f in Task { @MainActor [weak self] in self?.turboDownload = .downloading(f) } }
                turboDownload = .idle
                toast("Whisper turbo 已下载")
                if tierPreference == .turbo { restartForTier() }
            } catch {
                turboDownload = .failed(error.localizedDescription)
            }
        }
    }

    func deleteTurbo() {
        loader.release(.turbo)
        LiveModels.deleteTurboDownload()
        if tierPreference == .turbo { restartForTier() }
    }

    var turboDownloaded: Bool { LiveModels.whisperAvailable(.turbo) }

    private func loadTranslatorInBackground() {
        guard Self.sharedMT == nil || mt == nil else { return }
        guard mtTask == nil else { return }
        mtTask = Task { [weak self] in
            await self?.ensureTranslator()
            self?.mtTask = nil
        }
    }

    private func ensureTranslator() async {
        if let mt = Self.sharedMT { self.mt = mt; translatorName = mt.name; if phase == .running { startWorker() }; return }
        appleStatus = await AppleTranslation.status()
        var primary: LiveTranslating?
        #if canImport(Translation)
        if appleStatus == .installed {
            if #available(iOS 26.0, *) { primary = AppleDirectTranslator() }
            else if #available(iOS 18.0, *), let bridge = appleBridgeBox as? AppleTranslationBridge { bridge.activate(); primary = bridge }
        }
        #endif
        var fallback: LiveTranslating?
        if let root = LiveModels.root, LiveModels.nllbAvailable {
            translatorStatus = "NLLB 加载中…"
            let t0 = Date()
            do {
                fallback = try await Task.detached(priority: .utility) { try NLLBCoreMLTranslator(root: root) }.value
                translatorStatus = String(format: "NLLB 就绪 %.1fs", Date().timeIntervalSince(t0))
            } catch {
                translatorStatus = "NLLB 加载失败：\(error.localizedDescription)"
            }
            LiveDiagnostics.shared.log(translatorStatus)
        }
        guard primary != nil || fallback != nil else { translatorName = "无可用翻译"; return }
        let chain = LiveTranslatorChain(primary: primary, fallback: fallback)
        Self.sharedMT = chain
        mt = chain
        translatorName = chain.name
        if phase == .running { startWorker() }
        applyLLMSetting()
    }

    // MARK: 292 LLM translator (optional download)

    /// Title names from metadata (ja name, optional Chinese form) → glossary for every translator.
    func setTitleNames(_ names: [(ja: String, zh: String?)]) {
        glossary = LiveMTPrep.glossary(names: names)
        pipeline.glossary = glossary
    }

    /// Loads / unloads the LLM into the shared chain (off-main; ≈ 1–3 s mmap + Metal warm-up). Subtitles keep running
    /// on Apple/NLLB meanwhile.
    private func applyLLMSetting() {
        guard let chain = Self.sharedMT as? LiveTranslatorChain else { return }
        guard llmEnabled, LiveLLMModel.linked, LiveLLMModel.downloaded else {
            if chain.llm != nil { chain.llm = nil; translatorName = chain.name; LiveDiagnostics.shared.log("LLM 翻译已关闭") }
            return
        }
        guard chain.llm == nil, llmLoadTask == nil else { return }
        #if canImport(llama)
        llmStatus = "LLM 加载中…"
        llmLoadTask = Task { [weak self] in
            let t0 = Date()
            do {
                let t = try await Task.detached(priority: .utility) { try LiveLLMTranslator.load() }.value
                guard let self else { return }
                if self.llmEnabled { chain.llm = t }
                self.translatorName = chain.name
                self.llmStatus = String(format: "LLM 就绪 %.1fs", Date().timeIntervalSince(t0))
            } catch {
                self?.llmStatus = "LLM 加载失败：\(error.localizedDescription)"
            }
            if let s = self?.llmStatus { LiveDiagnostics.shared.log(s) }
            self?.llmLoadTask = nil
        }
        #endif
    }

    func downloadLLM() {
        guard llmDownload == .idle || { if case .failed = llmDownload { return true }; return false }() else { return }
        llmDownload = .downloading(0)
        Task {
            do {
                try await LiveLLMModel.download { f in Task { @MainActor [weak self] in self?.llmDownload = .downloading(f) } }
                llmDownload = .idle
                toast("\(LiveLLMModel.displayName) 已下载")
                if !llmEnabled { llmEnabled = true } else { applyLLMSetting() }
            } catch {
                llmDownload = .failed(error.localizedDescription)
            }
        }
    }

    func deleteLLM() {
        llmEnabled = false
        (Self.sharedMT as? LiveTranslatorChain)?.llm = nil
        LiveLLMModel.delete()
        if let chain = Self.sharedMT as? LiveTranslatorChain { translatorName = chain.name }
        llmStatus = ""
        objectWillChange.send()
    }

    /// Guard for the LLM (checked with the recognizer guard): hot / Low Power / battery < 20 % → Apple/NLLB;
    /// back on after 60 s of good conditions.
    private func checkLLMGuard() {
        guard let chain = Self.sharedMT as? LiveTranslatorChain, chain.llm != nil else { return }
        let d = UIDevice.current
        let battery = d.batteryLevel < 0 ? 1 : d.batteryLevel
        let charging = d.batteryState == .charging || d.batteryState == .full || d.batteryState == .unknown
        let v = LiveSubtitleGuard.llmAllowed(thermal: thermalLevel, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                                             battery: battery, charging: charging)
        if !v.ok { llmGuardBadSince = Date(); chain.setLLMAllowed(false, why: v.why) }
        else if let bad = llmGuardBadSince, Date().timeIntervalSince(bad) < 60 { /* hysteresis */ }
        else { llmGuardBadSince = nil; chain.setLLMAllowed(true, why: "") }
        let st = chain.llmStatus
        if st != llmStatus, !(llmLoadTask != nil) { llmStatus = st }
    }

    /// iOS 18+: present Apple's language-pack download sheet via the hidden `.translationTask` host.
    func requestApplePackDownload() {
        #if canImport(Translation)
        if #available(iOS 18.0, *), let bridge = appleBridgeBox as? AppleTranslationBridge { bridge.activate() }
        #endif
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            appleStatus = await AppleTranslation.status()
            if appleStatus == .installed { Self.sharedMT = nil; mt = nil; await ensureTranslator() }
        }
    }

    private func beginRunning(store: LiveSegmentStore?) {
        guard let source, let clock, let asr else { return }
        let now = clock()
        pipeline = LivePipeline(store: store ?? LiveSegmentStore())
        pipeline.mode = mode
        pipeline.glossary = glossary
        shared.set(pipeline: pipeline)
        lastSavedCount = pipeline.snapshotStore.segments.count
        pipeline.setPlayhead(now.time)
        setPace(now.time, now.rate)
        // 291: open 1.5 s before the playhead so the sentence already in progress is captured whole.
        let from = max(0, now.time - 1.5)
        let start = pipeline.resumePoint(after: from) ?? from
        pipeline.reset(at: start)
        pipeline.setPlayhead(now.time)
        reader.start(source, at: start, generation: pipeline.currentGeneration)
        phase = .running
        if !hitches.running { hitches.start() }
        startWorker()
        refreshCaption()
    }

    /// Single serial worker (concurrency cap = 1 ASR or MT call at a time): ASR and MT run in playhead order at
    /// utility QoS so AVPlayer decoding, audio and the UI always win the CPU; never on the main thread.
    private func startWorker() {
        guard let asr else { return }
        worker?.cancel()
        let pipeline = self.pipeline
        let mt = self.mt
        worker = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                if await !pipeline.work(asr: asr, mt: mt) { try? await Task.sleep(nanoseconds: 40_000_000) }
            }
        }
    }

    /// 291: recognizer change while running (heat step-down, compute-bound fallback, memory warning): the reader,
    /// VAD, queued utterances and lines on screen stay; only the worker restarts with the new recognizer. Before,
    /// every change went through start(): stop reader → reload → reopen the HLS stream, dropping the queue.
    private func hotSwap(to t: LiveASRTier, why: String, after: (() -> Void)? = nil) {
        guard phase == .running, asr != nil else { start(reason: why); return }
        guard activeTier != t else { return }
        guard LiveModels.available(t), t != .apple || appleASRStatus == .installed else {
            LiveDiagnostics.shared.log("热切换跳过 \(t.rawValue)（不可用）· \(why)"); return
        }
        swapTask?.cancel()
        let from = activeTier?.rawValue ?? "-"
        swapTask = Task { [weak self] in
            guard let self else { return }
            do {
                let next = try await self.loader.get(t, timeout: Self.timeout(t))
                guard !Task.isCancelled, self.phase == .running else { return }
                self.asr = next
                self.activeTier = next.tier
                self.hotSwaps += 1
                self.startWorker()
                after?()
                LiveDiagnostics.shared.log("热切换 \(from) → \(next.tier.rawValue)（不重启读取/队列）· \(why)")
            } catch {
                LiveDiagnostics.shared.log("热切换失败 \(t.rawValue) \(error.localizedDescription)，保持 \(from)")
            }
        }
    }

    private func stopRunning() {
        loadTask?.cancel(); loadTask = nil
        swapTask?.cancel(); swapTask = nil
        worker?.cancel(); worker = nil
        reader.stop()
        ticker?.cancel(); ticker = nil
        lastTick = nil
    }

    private func restartReader(at t: Double) {
        guard source != nil else { return }
        let from = max(0, t - 0.5)
        let start = pipeline.resumePoint(after: from) ?? from
        pipeline.reset(at: start)
        pipeline.setPlayhead(t)
        setPace(t, shared.pace.rate)
        reader.seek(to: start, generation: pipeline.currentGeneration)
        lastTick = (Date().timeIntervalSinceReferenceDate, t, shared.pace.rate)
        refreshCaption()
    }

    // MARK: reader wiring (reader thread)

    private func setPace(_ t: Double, _ r: Double, playing: Bool? = nil) { shared.set(playhead: t, rate: r, lead: effectiveLead, playing: playing) }

    private var thermalLevel: Int {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: 0
        case .fair: 1
        case .serious: 2
        case .critical: 3
        @unknown default: 0
        }
    }
    /// Read-ahead after thermal throttling (fair ×0.75, serious/critical ≤ 8 s).
    var effectiveLead: Double { LiveSubtitleGuard.throttledLead(lead, thermal: thermalLevel) }

    private func wireReader() {
        let shared = self.shared
        reader.onPCM = { pcm, start, g in shared.pipeline.feed(pcm, start: start, generation: g) }
        reader.onEnd = { g in shared.pipeline.finishStream(generation: g) }
        reader.onInfo = { LiveDiagnostics.shared.log($0) }
        reader.onError = { [weak self] msg in
            Task { @MainActor in self?.notice = "字幕音频读取失败（\(msg)），拖动进度可重试" }
        }
        reader.shouldRun = {
            let p = shared.pace
            return LiveScheduler.readerShouldRun(decodedEnd: shared.pipeline.snapshotStats.decodedEnd, playhead: p.playhead, lead: p.lead, rate: p.rate)
        }
        reader.skipTarget = { t in shared.pipeline.resumePoint(after: t) }
    }

    // MARK: clock

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            var guardCounter = 0
            while !Task.isCancelled {
                self?.tick()
                guardCounter += 1
                if guardCounter % 50 == 0 { self?.checkGuard() }        // every 5 s
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func tick() {
        updateModelStatus()
        if case .loading = phase {
            let el = Int(Date().timeIntervalSince(loadingSince))
            var label = "\(loadingLabel)… \(el / 60):\(String(format: "%02d", el % 60))"
            if el >= 15, loadingLabel.contains("Whisper") { label += " · 首次需编译模型，请保持前台" }
            if phase != .loading(label) { phase = .loading(label) }
        }
        guard let clock, phase == .running else { refreshCaption(); return }
        let c = clock()
        guard c.time.isFinite else { return }
        let wall = Date().timeIntervalSinceReferenceDate
        // Seek / jump detection: any discontinuity of > 1.5 s vs the extrapolated clock.
        if let last = lastTick {
            let expected = last.media + (wall - last.wall) * (c.playing ? max(0.25, c.rate) : 0)
            if abs(c.time - expected) > 1.5 { restartReader(at: c.time) }
        }
        lastTick = (wall, c.time, c.rate)
        pipeline.setPlayhead(c.time)
        setPace(c.time, c.playing ? max(1, c.rate) : 1, playing: c.playing)
        // 291: reader behind the playhead (stalled connection, slow 2nd HLS session): jump to now instead of
        // transcribing a backlog nobody will see live (≤ once per 10 s; the skipped span stays uncovered).
        let decoded = pipeline.snapshotStats.decodedEnd
        if c.playing, decoded < c.time - 6, Date().timeIntervalSince(lastCatchUp) > 10 {
            lastCatchUp = Date(); readerCatchUps += 1
            LiveDiagnostics.shared.log(String(format: "读取落后 %.1fs → 跳到播放点 %.1fs", c.time - decoded, c.time))
            restartReader(at: c.time)
        }
        reader.poke()
        refreshCaption()
        saveCache(force: false)
        updateLatencyText()
    }

    private var statusCounter = 0
    private func updateModelStatus() {
        statusCounter += 1
        guard statusCounter % 5 == 1 else { return }
        var out: [String] = []
        for t in LiveASRTier.allCases {
            let name = t.title
            switch loader.state(t) {
            case .idle:
                switch t {
                case .senseVoice: out.append(LiveModels.senseVoiceAvailable ? "\(name)：已打包（默认）" : "\(name)：未打包")
                case .apple: out.append("\(name)：\(appleASRStatus.title)")
                case .small: out.append(LiveModels.whisperAvailable(.small) ? "\(name)：已打包（手动选择时才加载）" : "\(name)：未打包")
                case .turbo:
                    switch turboDownload {
                    case .downloading(let f): out.append(String(format: "%@：下载中 %.0f%%", name, f * 100))
                    case .failed(let why): out.append("\(name)：下载失败 — \(why)")
                    case .idle: out.append(LiveModels.whisperAvailable(.turbo) ? "\(name)：已下载（手动选择时才加载）" : "\(name)：未下载（按需下载约 632 MB）")
                    }
                }
            case .loading(let since):
                let el = Int(Date().timeIntervalSince(since))
                let first = t == .turbo && UserDefaults.standard.object(forKey: "live.load.turbo") == nil
                out.append("\(name)：\(first ? "编译中（首次）" : "加载中") \(el / 60):\(String(format: "%02d", el % 60))")
            case .ready(let s): out.append(String(format: "%@：就绪（加载 %.1fs）%@", name, s, activeTier == t ? " · 使用中" : ""))
            case .failed(let why): out.append("\(name)：失败 — \(why)")
            }
        }
        hitchText = hitches.summary
        if !hitchText.isEmpty { out.append(hitchText) }
        if !translatorStatus.isEmpty { out.append(translatorStatus) }
        if !llmStatus.isEmpty { out.append(llmStatus) }
        if out != modelStatus { modelStatus = out }
    }

    private func refreshCaption() {
        guard mode != .off, let clock else {
            if !caption.isEmpty { caption = .init(ja: nil, zh: nil, partial: false, pendingChinese: false) }
            return
        }
        let c = pipeline.caption(at: clock().time)
        if c != caption { caption = c }
    }

    private func updateLatencyText() {
        let recs = pipeline.latency.filter { $0.segment >= 0 }.suffix(20)
        let rtf = pipeline.snapshotStats.rtfAvg
        guard !recs.isEmpty else { latencyText = ""; return }
        let sync = recs.filter(\.inSync).count
        let zh = recs.compactMap(\.zhLatency)
        let avg = zh.isEmpty ? 0 : zh.reduce(0, +) / Double(zh.count)
        let asrMs = recs.map(\.asrMs).reduce(0, +) / Double(recs.count)
        latencyText = String(format: "同步 %d/%d · 平均滞后 %.2fs · ASR %.0fms (%.2f× 实时)", sync, recs.count, avg, asrMs, rtf)
    }

    // MARK: guard

    private func currentVerdict() -> LiveSubtitleGuard.Verdict {
        let d = UIDevice.current
        let battery = d.batteryLevel < 0 ? 1 : d.batteryLevel
        let charging = d.batteryState == .charging || d.batteryState == .full || d.batteryState == .unknown
        return LiveSubtitleGuard.verdict(preferred: sessionOverride ?? preferredTier, thermal: thermalLevel,
                                         lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, battery: battery, charging: charging)
    }

    private func checkGuard() {
        guard mode != .off, source != nil else { return }
        if appleASRStatus == .unknown { Task { appleASRStatus = await AppleSpeechRecognizer.status() } }
        setPace(shared.pace.playhead, shared.pace.rate)          // re-apply the thermal read-ahead throttle
        switch currentVerdict() {
        case .pause(let why):
            if case .paused = phase { return }
            saveCache(force: true)
            stopRunning()
            phase = .paused(why)
            toast(why)
            startTicker()
        case .degrade(let t, let why):
            if case .paused = phase { start(reason: "恢复（\(why)）"); return }
            degradedAt = Date()
            if guardTier != t {
                guardTier = t
                toast(why)
                hotSwap(to: t, why: why)
            }
        case .run(let t):
            if case .paused = phase { start(reason: "恢复"); return }
            guard guardTier != t, phase == .running else { break }
            // Hysteresis: stay stepped-down until the device has been cool for `recoverSeconds`.
            if let d = degradedAt, Date().timeIntervalSince(d) < LiveSubtitleGuard.recoverSeconds { break }
            guardTier = t
            hotSwap(to: t, why: "温度恢复")
        }
        checkPerformance()
        checkLLMGuard()
    }

    /// Realtime first: only when the active recognizer is compute-bound (RTF > 0.7, or ≥ 3 of the last 5 lines
    /// waited > 2 s in queue + recognition with a backlog ≥ 3) hand over to Apple for this session. 291: lines that
    /// were late because the AUDIO arrived late (reader behind playback, restarts, main-thread stalls) no longer
    /// count — 290 switched SenseVoice at RTF 0.05 with "late 5/5" for exactly that reason.
    private func checkPerformance() {
        guard phase == .running, let t = activeTier, t != .apple, sessionOverride == nil, !preferredTier.isWhisper,
              appleASRStatus == .installed else { return }
        let v = pipeline.computeBound()
        guard v.bound else { return }
        sessionOverride = .apple
        toast(String(format: "%@ 跟不上播放（%.2f× 实时），已切换苹果系统识别", t.title, pipeline.snapshotStats.rtfAvg))
        LiveDiagnostics.shared.log("\(t.rawValue) \(v.why) → apple")
        hotSwap(to: .apple, why: "计算跟不上")
    }

    // MARK: cache

    private func saveCache(force: Bool) {
        guard !videoKey.isEmpty, activeTier != nil else { return }
        let store = pipeline.snapshotStore
        guard force || store.segments.count >= lastSavedCount + 8 else { return }
        guard !store.segments.isEmpty else { return }
        lastSavedCount = store.segments.count
        let key = cacheKey
        let cache = self.cache
        Task.detached(priority: .utility) { cache.save(store, key: key) }
    }

    /// Tier-independent since 288: small lines are kept when turbo takes over mid-video.
    private var cacheKey: String { LiveSubtitleCache.key(video: videoKey, tier: .small) }

    func clearCache() { cache.clear() }
    var cacheBytes: Int { cache.totalBytes() }
    func dismissNotice() { toastTask?.cancel(); notice = nil }
}

/// Main-thread hitch counter while live subtitles run: CADisplayLink frame gaps > 50 ms (≥ 3 frames at 60 Hz).
/// Measures UI/main-thread stalls only (AVPlayer decodes off the main thread). 291: gaps while the app is not
/// active (lock screen, Control Center, app switcher, PiP) are not hitches — 290 counted them (the "8351 ms"
/// worst case is consistent with a screen lock / notification shade, not compute); big hitches are logged with
/// their wall time and the live pipeline state so a report can be matched to what ran.
@MainActor
final class LiveHitchMonitor: NSObject {
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var started: CFTimeInterval = 0
    private(set) var hitches = 0
    private(set) var worstMs = 0.0
    private(set) var worst: [String] = []
    private var observers: [NSObjectProtocol] = []
    var running: Bool { link != nil }
    var context: (() -> String)?

    func start() {
        stop()
        hitches = 0; worstMs = 0; last = 0; worst = []; started = CACurrentMediaTime()
        let l = CADisplayLink(target: self, selector: #selector(frame(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        let nc = NotificationCenter.default
        for name in [UIApplication.willResignActiveNotification, UIApplication.didBecomeActiveNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.last = 0 }       // restart the gap measurement
            })
        }
    }
    func stop() {
        link?.invalidate(); link = nil
        observers.forEach(NotificationCenter.default.removeObserver); observers = []
    }

    @objc private func frame(_ l: CADisplayLink) {
        defer { last = l.timestamp }
        guard last > 0, UIApplication.shared.applicationState == .active else { last = 0; return }
        let gap = (l.timestamp - last) * 1000
        guard gap > 50 else { return }
        hitches += 1; worstMs = max(worstMs, gap)
        if gap > 400 {
            let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
            let line = String(format: "%@ %.0f ms %@", f.string(from: Date()), gap, context?() ?? "")
            worst.append(line); if worst.count > 5 { worst.removeFirst() }
            LiveDiagnostics.shared.log("主线程卡顿 " + line)
        }
    }

    var summary: String {
        guard link != nil, started > 0 else { return "" }
        let minutes = max(1.0 / 60, (CACurrentMediaTime() - started) / 60)
        return String(format: "主线程卡顿 %d 次（%.1f/分钟，最长 %.0f ms）", hitches, Double(hitches) / minutes, worstMs)
    }
}
