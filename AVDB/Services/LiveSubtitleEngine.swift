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
            task = Task.detached(priority: .userInitiated) {
                try await LiveWhisperRecognizer.load(tier, log: { LiveDiagnostics.shared.log($0) })
            }
            tasks[tier] = task
            Task { [weak self] in
                do {
                    let r = try await task.value
                    self?.ready[tier] = r
                    self?.states[tier] = .ready(seconds: (r as? LiveWhisperRecognizer)?.loadSeconds ?? 0)
                    UserDefaults.standard.set((r as? LiveWhisperRecognizer)?.loadSeconds ?? 0, forKey: "live.load.\(tier.rawValue)")
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
    private var upgradeTask: Task<Void, Never>?
    private var mtTask: Task<Void, Never>?
    private var loadingLabel = ""
    private var loadingSince = Date()
    private var memoryObserver: NSObjectProtocol?
    private var upgradeNoticeShown = false
    private var upgradeNoticeDismissed = false
    static let smallTimeout: Double = 120
    static let turboTimeout: Double = 900
    private var asr: LiveSpeechRecognizer?
    private var mt: LiveTranslating?
    private var lastTick: (wall: Double, media: Double, rate: Double)?
    private var lastSavedCount = 0
    private var guardTier: LiveASRTier?
    /// Set when the measured real-time factor shows turbo cannot keep up on this device (session-wide).
    private var perfDegraded = false
    /// State the reader thread reads without hopping to the main actor.
    private final class Shared: @unchecked Sendable {
        private let lock = NSLock()
        private var _pipeline = LivePipeline(), _playhead = 0.0, _rate = 1.0, _lead = 20.0
        func set(pipeline: LivePipeline? = nil, playhead: Double? = nil, rate: Double? = nil, lead: Double? = nil) {
            lock.lock(); defer { lock.unlock() }
            if let pipeline { _pipeline = pipeline }
            if let playhead { _playhead = playhead }
            if let rate { _rate = rate }
            if let lead { _lead = lead }
        }
        var pipeline: LivePipeline { lock.lock(); defer { lock.unlock() }; return _pipeline }
        var pace: (playhead: Double, rate: Double, lead: Double) { lock.lock(); defer { lock.unlock() }; return (_playhead, _rate, _lead) }
    }
    private let shared = Shared()

    /// Translators are expensive to load: keep the chain alive across player sessions (recognizers live in
    /// LiveModelLoader).
    private static var sharedMT: LiveTranslating?
    private var loader: LiveModelLoader { .shared }

    init() {
        mode = LiveSubtitleMode(rawValue: UserDefaults.standard.string(forKey: LiveSubtitleMode.defaultsKey) ?? "") ?? .off
        tierPreference = LiveTierPreference(rawValue: UserDefaults.standard.string(forKey: LiveTierPreference.defaultsKey) ?? "") ?? .automatic
        pipeline.mode = mode
        UIDevice.current.isBatteryMonitoringEnabled = true
        wireReader()
        Task { appleStatus = await AppleTranslation.status() }
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
        detach()
        source = newSource
        self.videoKey = videoKey
        self.clock = clock
        guard mode != .off else { return }
        start()
    }

    func detach() {
        saveCache(force: true)
        stopRunning()
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
        if mode == .off { saveCache(force: true); stopRunning(); phase = .off; caption = .init(ja: nil, zh: nil, partial: false, pendingChinese: false); return }
        if old == .off { start(); return }
        if mode.needsChinese, mt == nil { loadTranslatorInBackground() }
        refreshCaption()
    }

    private func restartForTier() {
        guard mode != .off, source != nil else { return }
        saveCache(force: true)
        stopRunning()
        start()
    }

    /// 重试: clears failed states (an in-flight compile is awaited again, never restarted) and starts over.
    func retry() {
        LiveDiagnostics.shared.log("用户点击重试")
        loader.resetFailures()
        if mode == .off { mode = .bilingual; return }
        start()
    }

    func diagnosticReport() -> String {
        LiveDiagnostics.shared.report(extra: ["模式 \(mode.rawValue) · 偏好 \(tierPreference.rawValue) · 当前 \(activeTier?.rawValue ?? "-") · 阶段 \(phaseText)",
                                              "可用内存 \(LiveMemory.availableMB) MB · 翻译 \(translatorName) · Apple \(appleStatus)"] + modelStatus)
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
        if activeTier == .turbo, LiveModels.whisperAvailable(.small), tierPreference == .automatic {
            perfDegraded = true
            notice = "内存不足，已切换 small 模型"
            saveCache(force: true)
            loader.release(.turbo)
            start()
        } else if activeTier != .turbo {
            upgradeTask?.cancel(); upgradeTask = nil
        }
    }

    private func start() {
        guard source != nil, clock != nil, mode != .off else { return }
        stopRunning()
        let verdict = currentVerdict()
        if case .pause(let why) = verdict { phase = .paused(why); notice = why; startTicker(); return }
        var target = perfDegraded ? .small : preferredTier
        if case .degrade(let t, let why) = verdict { target = t; notice = why }
        guardTier = target
        if !LiveModels.whisperAvailable(target), target == .turbo, LiveModels.whisperAvailable(.small) { target = .small; notice = "turbo 模型未打包，改用 small" }
        guard LiveModels.whisperAvailable(target) else {
            phase = .failed("语音模型未打包（\(target.folder)）")
            LiveDiagnostics.shared.log("模型缺失 \(target.folder)")
            return
        }
        // Stage 1: the model that starts fastest — turbo if it is already resident, otherwise small (seconds),
        // unless the user pinned turbo.
        let first: LiveASRTier = {
            if loader.cached(target) != nil { return target }
            if target == .turbo, tierPreference == .automatic, LiveModels.whisperAvailable(.small) { return .small }
            return target
        }()
        let timeout = first == .turbo ? Self.turboTimeout : Self.smallTimeout
        setLoading(first == .turbo && UserDefaults.standard.object(forKey: "live.load.turbo") == nil
                   ? "正在编译 \(first.title)（首次较慢）" : "正在加载 \(first.title)")
        LiveDiagnostics.shared.log("start target=\(target.rawValue) first=\(first.rawValue) timeout=\(Int(timeout))s")
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let asr = try await self.loader.get(first, timeout: timeout)
                guard !Task.isCancelled, self.mode != .off else { return }
                self.asr = asr
                self.activeTier = asr.tier
                LiveDiagnostics.shared.log("运行 \(asr.tier.rawValue)")
                self.beginRunning()
                self.loadTranslatorInBackground()
                if target == .turbo, first != .turbo { self.scheduleUpgrade() }
            } catch {
                guard !Task.isCancelled else { return }
                self.phase = .failed(error.localizedDescription)
                LiveDiagnostics.shared.log("启动失败 \(error.localizedDescription)")
            }
        }
        startTicker()
    }

    private func setLoading(_ label: String) {
        loadingLabel = label
        loadingSince = Date()
        phase = .loading(label + "…")
    }

    /// Stage 2: compile/load turbo in the background while small is already producing subtitles, then swap.
    private func scheduleUpgrade() {
        upgradeTask?.cancel()
        let avail = LiveMemory.availableMB
        guard avail == 0 || avail > 1800 else {
            notice = "可用内存不足（\(avail) MB），本次使用 small"
            LiveDiagnostics.shared.log("跳过 turbo：可用内存 \(avail) MB")
            return
        }
        upgradeNoticeShown = true
        upgradeTask = Task { [weak self] in
            guard let self else { return }
            defer { self.upgradeNoticeShown = false }
            do {
                let r = try await self.loader.get(.turbo, timeout: Self.turboTimeout)
                guard !Task.isCancelled, self.phase == .running, !self.perfDegraded, self.guardTier == .turbo else { return }
                self.asr = r
                self.activeTier = .turbo
                self.startWorker()
                self.loader.release(.small)
                self.notice = "已切换 large-v3-turbo 高精度模型"
                LiveDiagnostics.shared.log("已切换 turbo")
            } catch {
                guard !Task.isCancelled else { return }
                self.notice = "turbo 未就绪（\(error.localizedDescription)），继续使用 small"
            }
        }
    }

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
                fallback = try await Task.detached(priority: .userInitiated) { try NLLBCoreMLTranslator(root: root) }.value
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

    private func beginRunning() {
        guard let source, let clock, let asr else { return }
        let now = clock()
        pipeline = LivePipeline(store: cache.load(cacheKey) ?? LiveSegmentStore())
        pipeline.mode = mode
        shared.set(pipeline: pipeline)
        lastSavedCount = pipeline.snapshotStore.segments.count
        pipeline.setPlayhead(now.time)
        setPace(now.time, now.rate)
        let start = pipeline.resumePoint(after: now.time) ?? now.time
        pipeline.reset(at: start)
        pipeline.setPlayhead(now.time)
        reader.start(source, at: start, generation: pipeline.currentGeneration)
        phase = .running
        startWorker()
        refreshCaption()
    }

    /// Single serial worker: ASR and MT run in playhead order (finals first, then streaming partials).
    private func startWorker() {
        guard let asr else { return }
        worker?.cancel()
        let pipeline = self.pipeline
        let mt = self.mt
        worker = Task.detached(priority: .userInitiated) {
            while !Task.isCancelled {
                if await !pipeline.work(asr: asr, mt: mt) { try? await Task.sleep(nanoseconds: 40_000_000) }
            }
        }
    }

    private func stopRunning() {
        loadTask?.cancel(); loadTask = nil
        upgradeTask?.cancel(); upgradeTask = nil
        worker?.cancel(); worker = nil
        reader.stop()
        ticker?.cancel(); ticker = nil
        lastTick = nil
    }

    private func restartReader(at t: Double) {
        guard source != nil else { return }
        let start = pipeline.resumePoint(after: t) ?? t
        pipeline.reset(at: start)
        pipeline.setPlayhead(t)
        setPace(t, shared.pace.rate)
        reader.seek(to: start, generation: pipeline.currentGeneration)
        lastTick = (Date().timeIntervalSinceReferenceDate, t, shared.pace.rate)
        refreshCaption()
    }

    // MARK: reader wiring (reader thread)

    private func setPace(_ t: Double, _ r: Double) { shared.set(playhead: t, rate: r, lead: lead) }

    private func wireReader() {
        let shared = self.shared
        reader.onPCM = { pcm, start, g in shared.pipeline.feed(pcm, start: start, generation: g) }
        reader.onEnd = { g in shared.pipeline.finishStream(generation: g) }
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
            if el >= 15 { label += " · 首次需编译模型，请保持前台" }
            phase = .loading(label)
        }
        if upgradeNoticeShown, !upgradeNoticeDismissed, phase == .running, case .loading(let since) = loader.state(.turbo) {
            let el = Int(Date().timeIntervalSince(since))
            let first = UserDefaults.standard.object(forKey: "live.load.turbo") == nil
            notice = "large-v3-turbo 后台\(first ? "编译中（首次）" : "加载中")\(el / 60):\(String(format: "%02d", el % 60)) · 先用 small"
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
        setPace(c.time, c.playing ? max(1, c.rate) : 1)
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
                if !LiveModels.whisperAvailable(t) { out.append("\(name)：未打包") }
            case .loading(let since):
                let el = Int(Date().timeIntervalSince(since))
                let first = t == .turbo && UserDefaults.standard.object(forKey: "live.load.turbo") == nil
                out.append("\(name)：\(first ? "编译中（首次）" : "加载中") \(el / 60):\(String(format: "%02d", el % 60))")
            case .ready(let s): out.append(String(format: "%@：就绪（加载 %.1fs）%@", name, s, activeTier == t ? " · 使用中" : ""))
            case .failed(let why): out.append("\(name)：失败 — \(why)")
            }
        }
        if !translatorStatus.isEmpty { out.append(translatorStatus) }
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
        let thermal: Int = {
            switch ProcessInfo.processInfo.thermalState {
            case .nominal: 0
            case .fair: 1
            case .serious: 2
            case .critical: 3
            @unknown default: 0
            }
        }()
        let battery = d.batteryLevel < 0 ? 1 : d.batteryLevel
        let charging = d.batteryState == .charging || d.batteryState == .full || d.batteryState == .unknown
        return LiveSubtitleGuard.verdict(preferred: preferredTier, thermal: thermal,
                                         lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, battery: battery, charging: charging)
    }

    private func checkGuard() {
        guard mode != .off, source != nil else { return }
        switch currentVerdict() {
        case .pause(let why):
            if case .paused = phase { return }
            saveCache(force: true)
            stopRunning()
            phase = .paused(why)
            notice = why
            startTicker()
        case .degrade(let t, let why):
            if case .paused = phase { notice = why; start(); return }
            if guardTier != t { notice = why; if t == .small { loader.release(.turbo) }; start() }
        case .run(let t):
            if case .paused = phase { notice = nil; start(); return }
            let want = perfDegraded ? .small : t
            if guardTier != want, phase == .running { notice = nil; start() }
        }
        checkPerformance()
    }

    /// Realtime first: if turbo's measured compute time exceeds 0.8 s per second of speech (it would fall
    /// behind the look-ahead window), drop to small for this session — unless the user pinned turbo.
    private func checkPerformance() {
        guard phase == .running, activeTier == .turbo, !perfDegraded, tierPreference == .automatic,
              LiveModels.whisperAvailable(.small) else { return }
        let st = pipeline.snapshotStats
        guard st.finalsMeasured >= 3, st.rtfAvg > 0.8 else { return }
        perfDegraded = true
        notice = String(format: "turbo 在本机无法实时（%.1f× 实时），已切换 small 模型", st.rtfAvg)
        saveCache(force: true)
        loader.release(.turbo)
        LiveDiagnostics.shared.log(String(format: "turbo RTF %.2f → small", st.rtfAvg))
        start()
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
    func dismissNotice() { if upgradeNoticeShown { upgradeNoticeDismissed = true }; notice = nil }
}
