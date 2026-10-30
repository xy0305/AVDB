// Build 289 — default and fallback live recognizers.
//  • SenseVoiceRecognizer — FunAudioLLM SenseVoice-Small (non-autoregressive CTC; zh/en/ja/ko/yue), int8 ONNX
//    (sherpa-onnx export 2024-07-17) run by sherpa-onnx 2.0.1 / onnxruntime on the CPU, language fixed to "ja",
//    inverse text normalisation on. One encoder pass per VAD chunk — no autoregressive decoding loop.
//    Model license: FunASR Model Open Source License v1.1 (attribution + keep model name); sherpa-onnx Apache-2.0;
//    onnxruntime MIT.
//  • AppleSpeechRecognizer — iOS 26+: SpeechAnalyzer + SpeechTranscriber (on-device system model);
//    iOS 17–25: SFSpeechRecognizer(ja-JP) with requiresOnDeviceRecognition. Used when the device is hot / in Low
//    Power, or when SenseVoice falls behind the playhead.
//  • LiveRecognizerFactory — one entry point for the engine, the CI bench and the simulator host.
import AVFoundation
import Foundation
import Speech

// MARK: - Apple on-device recognition

final class AppleSpeechRecognizer: LiveSpeechRecognizer, @unchecked Sendable {
    let tier: LiveASRTier = .apple
    private(set) var loadSeconds: Double = 0
    static let locale = Locale(identifier: "ja-JP")
    private let legacy: SFSpeechRecognizer?
    private let lock = NSLock()
    var engineName: String { legacy == nil ? "SpeechAnalyzer/SpeechTranscriber" : "SFSpeechRecognizer（本机）" }

    private init(legacy: SFSpeechRecognizer?) { self.legacy = legacy }

    static func status() async -> AppleASRStatus {
        if #available(iOS 26.0, macOS 26.0, *) {
            guard let loc = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else { return .unsupported }
            let installed = await SpeechTranscriber.installedLocales
            if installed.contains(where: { $0.identifier(.bcp47) == loc.identifier(.bcp47) }) { return .installed }
            return .needsDownload
        }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .denied, .restricted: return .denied
        default: break
        }
        guard let r = SFSpeechRecognizer(locale: locale) else { return .unsupported }
        return r.supportsOnDeviceRecognition ? .installed : .unsupported
    }

    /// iOS 26+: asks the system to download the Japanese on-device model (user-initiated from settings, or when
    /// the fallback is first needed). No-op when installed.
    static func installAssets() async throws {
        if #available(iOS 26.0, macOS 26.0, *) {
            guard let loc = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else { throw LiveEngineError.unavailable("系统不支持日语识别") }
            let t = SpeechTranscriber(locale: loc, preset: .transcription)
            if let req = try await AssetInventory.assetInstallationRequest(supporting: [t]) { try await req.downloadAndInstall() }
        }
    }

    static func make(installIfNeeded: Bool) async throws -> AppleSpeechRecognizer {
        let t0 = Date()
        if #available(iOS 26.0, macOS 26.0, *) {
            var st = await status()
            if st == .needsDownload, installIfNeeded { try await installAssets(); st = await status() }
            guard st == .installed else { throw LiveEngineError.unavailable("苹果日语识别：\(st.title)") }
            let r = AppleSpeechRecognizer(legacy: nil); r.loadSeconds = Date().timeIntervalSince(t0); return r
        }
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            _ = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
                SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
            }
        }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { throw LiveEngineError.unavailable("苹果语音识别未授权") }
        guard let rec = SFSpeechRecognizer(locale: locale), rec.supportsOnDeviceRecognition else {
            throw LiveEngineError.unavailable("本机不支持离线日语识别")
        }
        let r = AppleSpeechRecognizer(legacy: rec); r.loadSeconds = Date().timeIntervalSince(t0); return r
    }

    static func buffer(_ samples: [Float], format: AVAudioFormat? = nil) -> AVAudioPCMBuffer? {
        guard let src = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let b = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        b.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { p in b.floatChannelData![0].update(from: p.baseAddress!, count: samples.count) }
        guard let format, format != src else { return b }
        guard let conv = AVAudioConverter(from: src, to: format),
              let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(samples.count) * format.sampleRate / 16000) + 1024) else { return nil }
        var fed = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true; status.pointee = .haveData; return b
        }
        return err == nil ? out : nil
    }

    func transcribe(_ samples: [Float], prompt: String?) async throws -> String {
        guard !samples.isEmpty else { return "" }
        if #available(iOS 26.0, macOS 26.0, *), legacy == nil { return try await analyze(samples) }
        guard let legacy, let buf = Self.buffer(samples) else { return "" }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = false
        req.taskHint = .dictation
        req.append(buf)
        req.endAudio()
        final class Once: @unchecked Sendable { var done = false; let lock = NSLock()
            func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true } }
        let once = Once()
        return try await withCheckedThrowingContinuation { c in
            _ = legacy.recognitionTask(with: req) { result, error in
                if let result, result.isFinal { if once.claim() { c.resume(returning: result.bestTranscription.formattedString) } }
                else if let error { if once.claim() { c.resume(throwing: error) } }
            }
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func analyze(_ samples: [Float]) async throws -> String {
        guard let loc = await SpeechTranscriber.supportedLocale(equivalentTo: Self.locale) else { return "" }
        let transcriber = SpeechTranscriber(locale: loc, preset: .transcription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        guard let buf = Self.buffer(samples, format: format) else { return "" }
        let (inputs, builder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        async let text: String = transcriber.results.reduce(into: "") { acc, r in acc += String(r.text.characters) }
        builder.yield(AnalyzerInput(buffer: buf))
        builder.finish()
        if let last = try await analyzer.analyzeSequence(inputs) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            try? await analyzer.cancelAndFinishNow()
        }
        return try await text
    }
}

// MARK: - Factory

enum LiveRecognizerFactory {
    /// Loads `tier`. Whisper goes through LiveWhisperRecognizer (bundled small / downloaded turbo, never compiled
    /// unless selected); SenseVoice loads in ~1 s; Apple is a system service.
    static func load(_ tier: LiveASRTier, installApple: Bool = true,
                     log: @escaping @Sendable (String) -> Void = { _ in }) async throws -> LiveSpeechRecognizer {
        switch tier {
        case .senseVoice:
            guard let folder = LiveModels.senseVoiceFolder, LiveModels.senseVoiceAvailable else {
                throw LiveEngineError.modelMissing(LiveASRTier.senseVoice.folder)
            }
            let r = try SenseVoiceRecognizer(folder: folder)
            log(String(format: "sensevoice: 就绪 %.2fs（sherpa-onnx %@ · %@ · %d 线程）", r.loadSeconds, SenseVoiceRecognizer.version, r.provider, r.threads))
            return r
        case .apple:
            let r = try await AppleSpeechRecognizer.make(installIfNeeded: installApple)
            log(String(format: "apple: 就绪 %.2fs（%@）", r.loadSeconds, r.engineName))
            return r
        case .small, .turbo:
            return try await LiveWhisperRecognizer.load(tier, log: log)
        }
    }

    static func loadSeconds(_ r: LiveSpeechRecognizer) -> Double {
        (r as? LiveWhisperRecognizer)?.loadSeconds ?? (r as? SenseVoiceRecognizer)?.loadSeconds ?? (r as? AppleSpeechRecognizer)?.loadSeconds ?? 0
    }
}
