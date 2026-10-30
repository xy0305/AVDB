// Build 287 — live subtitle engine: look-ahead reader → VAD → Whisper → (Apple Translation | NLLB) → overlay.
// Nothing is generated ahead of playback beyond the ~lead window the reader keeps in front of the playhead;
// segments are cached per video and reused on rewatch.
import Combine
import Foundation
import SwiftUI
import UIKit

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
    private var asr: LiveSpeechRecognizer?
    private var mt: LiveTranslating?
    private var lastTick: (wall: Double, media: Double, rate: Double)?
    private var lastSavedCount = 0
    private var guardTier: LiveASRTier?
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

    /// Recognizers are expensive to load (ANE compile): keep the last one alive across player sessions.
    private static var sharedASR: LiveSpeechRecognizer?
    private static var sharedMT: LiveTranslating?

    init() {
        mode = LiveSubtitleMode(rawValue: UserDefaults.standard.string(forKey: LiveSubtitleMode.defaultsKey) ?? "") ?? .off
        tierPreference = LiveTierPreference(rawValue: UserDefaults.standard.string(forKey: LiveTierPreference.defaultsKey) ?? "") ?? .automatic
        pipeline.mode = mode
        UIDevice.current.isBatteryMonitoringEnabled = true
        wireReader()
        Task { appleStatus = await AppleTranslation.status() }
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
        if mode.needsChinese, mt == nil { Task { await ensureTranslator() } }
        refreshCaption()
    }

    private func restartForTier() {
        guard mode != .off, source != nil else { return }
        saveCache(force: true)
        stopRunning()
        Self.sharedASR = nil
        start()
    }

    private func start() {
        guard source != nil, clock != nil, mode != .off else { return }
        stopRunning()
        let verdict = currentVerdict()
        if case .pause(let why) = verdict { phase = .paused(why); notice = why; startTicker(); return }
        var tier = preferredTier
        if case .degrade(let t, let why) = verdict { tier = t; notice = why }
        guardTier = tier
        phase = .loading(LiveModels.whisperAvailable(tier) ? "正在加载语音模型 \(tier.title)…" : "模型未打包")
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let asr = try await self.recognizer(for: tier)
                guard !Task.isCancelled else { return }
                self.asr = asr
                self.activeTier = asr.tier
                await self.ensureTranslator()
                guard !Task.isCancelled, self.mode != .off else { return }
                self.beginRunning()
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
        startTicker()
    }

    private func recognizer(for tier: LiveASRTier) async throws -> LiveSpeechRecognizer {
        if let s = Self.sharedASR, s.tier == tier { return s }
        Self.sharedASR = nil
        if !LiveModels.whisperAvailable(tier), tier == .turbo, LiveModels.whisperAvailable(.small) {
            notice = "turbo 模型未打包，改用 small"
            return try await recognizer(for: .small)
        }
        let r = try await LiveWhisperRecognizer.load(tier)
        Self.sharedASR = r
        return r
    }

    private func ensureTranslator() async {
        if let mt = Self.sharedMT { self.mt = mt; translatorName = mt.name; return }
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
            fallback = await Task.detached(priority: .userInitiated) { try? NLLBCoreMLTranslator(root: root) }.value
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
        pipeline = LivePipeline(store: cache.load(LiveSubtitleCache.key(video: videoKey, tier: asr.tier)) ?? LiveSegmentStore())
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
        guard !recs.isEmpty else { latencyText = ""; return }
        let sync = recs.filter(\.inSync).count
        let zh = recs.compactMap(\.zhLatency)
        let avg = zh.isEmpty ? 0 : zh.reduce(0, +) / Double(zh.count)
        let asrMs = recs.map(\.asrMs).reduce(0, +) / Double(recs.count)
        latencyText = String(format: "同步 %d/%d · 平均滞后 %.2fs · ASR %.0fms", sync, recs.count, avg, asrMs)
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
            if guardTier != t { notice = why; Self.sharedASR = nil; start() }
        case .run(let t):
            if case .paused = phase { notice = nil; start(); return }
            if guardTier != t, phase == .running { notice = nil; Self.sharedASR = nil; start() }
        }
    }

    // MARK: cache

    private func saveCache(force: Bool) {
        guard !videoKey.isEmpty, let tier = activeTier else { return }
        let store = pipeline.snapshotStore
        guard force || store.segments.count >= lastSavedCount + 8 else { return }
        guard !store.segments.isEmpty else { return }
        lastSavedCount = store.segments.count
        let key = LiveSubtitleCache.key(video: videoKey, tier: tier)
        let cache = self.cache
        Task.detached(priority: .utility) { cache.save(store, key: key) }
    }

    func clearCache() { cache.clear() }
    var cacheBytes: Int { cache.totalBytes() }
    func dismissNotice() { notice = nil }
}
