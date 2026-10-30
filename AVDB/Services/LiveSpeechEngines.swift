// Build 287 — on-device engines behind LiveSubtitleCore's protocols.
//  • LiveWhisperRecognizer — WhisperKit (Core ML), Japanese, encoder + decoder on the Neural Engine.
//  • NLLBCoreMLTranslator  — bundled NLLB-200-distilled-600M (int8, trimmed vocab) ja → zh-Hans, Core ML.
//  • AppleTranslator       — Apple Translation (iOS 18+), preferred when the ja→zh-Hans packs are installed.
import CoreML
import Foundation
import WhisperKit

/// Build 288 — ring-buffer diagnostic log for live subtitles (device, model files, per-stage load timings, errors).
/// Persisted to Caches/LiveSubtitles/diagnostics.log; the settings sheet copies `report()` to the pasteboard.
final class LiveDiagnostics: @unchecked Sendable {
    static let shared = LiveDiagnostics()
    private let lock = NSLock()
    private var lines: [String] = []
    private let t0 = Date()
    private let fileURL: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("LiveSubtitles/diagnostics.log")

    init() {
        if let fileURL, let old = try? String(contentsOf: fileURL, encoding: .utf8) {
            lines = Array(old.split(separator: "\n").map(String.init).suffix(120))
            lines.append("—— 上次会话结束 ——")
        }
    }

    func log(_ s: String) {
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm:ss"
        let line = "\(f.string(from: Date())) +\(String(format: "%.1f", Date().timeIntervalSince(t0)))s \(s)"
        lock.lock(); lines.append(line); if lines.count > 300 { lines.removeFirst(lines.count - 300) }
        let text = lines.joined(separator: "\n"); lock.unlock()
        if let fileURL {
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    var recent: [String] { lock.lock(); defer { lock.unlock() }; return Array(lines.suffix(8)) }

    static var machine: String {
        var size = 0; sysctlbyname("hw.machine", nil, &size, nil, 0)
        var b = [CChar](repeating: 0, count: max(1, size)); sysctlbyname("hw.machine", &b, &size, nil, 0)
        return String(cString: b)
    }

    func report(extra: [String] = []) -> String {
        let pi = ProcessInfo.processInfo
        var head = ["AVDB 实时字幕诊断 build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")",
                    "设备 \(Self.machine) · \(pi.operatingSystemVersionString) · RAM \(pi.physicalMemory / 1_048_576) MB · 温度 \(pi.thermalState.rawValue) · 低电量 \(pi.isLowPowerModeEnabled)"]
        if let root = LiveModels.root {
            head.append("模型目录 \(root.path)")
            head.append("SenseVoice \(LiveModels.senseVoiceAvailable ? "✓" : "✗") · turbo 下载 \(LiveModels.modelFolder(.turbo) != nil ? "✓" : "未下载")")
            for t in LiveASRTier.allCases where t.isWhisper {
                head.append("\(t.rawValue): 编码器 \(FileManager.default.fileExists(atPath: root.appendingPathComponent(t.folder + "/AudioEncoder.mlmodelc").path) ? "✓" : "✗") 分词器 \(FileManager.default.fileExists(atPath: root.appendingPathComponent(t.tokenizer + "/tokenizer.json").path) ? "✓" : "✗")")
            }
            head.append("NLLB \(LiveModels.nllbAvailable ? "✓" : "✗")")
        } else { head.append("模型目录 未打包") }
        lock.lock(); let body = lines; lock.unlock()
        return (head + extra + ["—— 日志 ——"] + body).joined(separator: "\n")
    }
}

enum LiveModels {
    /// Folder reference `LiveModels` in the app bundle (populated by CI; see scripts/live287 + scripts/live289).
    static var root: URL? {
        if let override = ProcessInfo.processInfo.environment["AVDB_LIVE_MODELS"] { return URL(fileURLWithPath: override) }
        return Bundle.main.url(forResource: "LiveModels", withExtension: nil)
    }
    /// On-demand downloads (289: Whisper turbo is no longer bundled). Application Support, excluded from backup.
    static var downloadRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("LiveModels", isDirectory: true)
    }
    static let turboFolderKey = "live.turbo.folder289"

    private static func hasEncoder(_ u: URL) -> Bool {
        FileManager.default.fileExists(atPath: u.appendingPathComponent("AudioEncoder.mlmodelc").path)
    }
    /// Whisper model folder: bundled first, then the on-demand download.
    static func modelFolder(_ tier: LiveASRTier, root: URL? = LiveModels.root) -> URL? {
        guard tier.isWhisper else { return nil }
        if let root, hasEncoder(root.appendingPathComponent(tier.folder)) { return root.appendingPathComponent(tier.folder) }
        if tier == .turbo, let p = UserDefaults.standard.string(forKey: turboFolderKey), hasEncoder(URL(fileURLWithPath: p)) {
            return URL(fileURLWithPath: p)
        }
        return nil
    }
    static func tokenizerFolder(_ tier: LiveASRTier, root: URL? = LiveModels.root) -> URL? {
        guard tier.isWhisper else { return nil }
        for base in [root, downloadRoot].compactMap({ $0 }) {
            let u = base.appendingPathComponent(tier.tokenizer)
            if FileManager.default.fileExists(atPath: u.appendingPathComponent("tokenizer.json").path) { return u }
        }
        return nil
    }
    static func whisperAvailable(_ tier: LiveASRTier) -> Bool {
        modelFolder(tier) != nil && tokenizerFolder(tier) != nil
    }
    static var senseVoiceFolder: URL? { root?.appendingPathComponent(LiveASRTier.senseVoice.folder) }
    static var senseVoiceAvailable: Bool {
        guard let d = senseVoiceFolder else { return false }
        return FileManager.default.fileExists(atPath: d.appendingPathComponent("model.int8.onnx").path)
            && FileManager.default.fileExists(atPath: d.appendingPathComponent("tokens.txt").path)
    }
    /// Files present (Apple availability is a runtime/system check, see AppleSpeechRecognizer.status()).
    static func available(_ tier: LiveASRTier) -> Bool {
        switch tier {
        case .senseVoice: senseVoiceAvailable
        case .apple: true
        case .small, .turbo: whisperAvailable(tier)
        }
    }
    static var nllbAvailable: Bool {
        guard let root else { return false }
        return FileManager.default.fileExists(atPath: root.appendingPathComponent("nllb/NLLBDecoder.mlmodelc").path)
    }

    /// Downloads Whisper turbo (≈ 632 MB Core ML, argmaxinc/whisperkit-coreml, MIT) on explicit user request only.
    /// Tries huggingface.co, then the hf-mirror.com mirror. The tokenizer stays bundled (tokenizer-large-v3).
    static func downloadTurbo(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try FileManager.default.createDirectory(at: downloadRoot, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var dir = downloadRoot; try? dir.setResourceValues(values)
        var lastError: Error = LiveEngineError.modelMissing(LiveASRTier.turbo.folder)
        for endpoint in ["https://huggingface.co", "https://hf-mirror.com"] {
            do {
                LiveDiagnostics.shared.log("turbo 下载开始 \(endpoint)")
                let url = try await WhisperKit.download(variant: LiveASRTier.turbo.folder, downloadBase: downloadRoot,
                                                        from: "argmaxinc/whisperkit-coreml", endpoint: endpoint,
                                                        progressCallback: { progress($0.fractionCompleted) })
                guard hasEncoder(url) else { throw LiveEngineError.modelMissing(url.path) }
                UserDefaults.standard.set(url.path, forKey: turboFolderKey)
                LiveDiagnostics.shared.log("turbo 下载完成 \(url.path)")
                return url
            } catch {
                lastError = error
                LiveDiagnostics.shared.log("turbo 下载失败 \(endpoint): \(error.localizedDescription)")
            }
        }
        throw lastError
    }

    static func deleteTurboDownload() {
        if let p = UserDefaults.standard.string(forKey: turboFolderKey) { try? FileManager.default.removeItem(atPath: p) }
        UserDefaults.standard.removeObject(forKey: turboFolderKey)
    }
}

// MARK: - Whisper

final class LiveWhisperRecognizer: LiveSpeechRecognizer, @unchecked Sendable {
    let tier: LiveASRTier
    private let kit: WhisperKit
    /// Diagnostics: the tokenizer type actually in use (LiveBundledTokenizer = bundled files, no Hub).
    var tokenizerKind: String { kit.tokenizer.map { String(describing: type(of: $0)) } ?? "nil" }
    private(set) var loadSeconds: Double = 0

    private init(tier: LiveASRTier, kit: WhisperKit) { self.tier = tier; self.kit = kit }

    /// Compute units per tier (build 288): audio encoder on the Neural Engine (the expensive part), text decoder on
    /// the GPU — avoids a second, slow ANE specialisation for the decoder on first launch; mel on GPU.
    static func computeUnits(_ tier: LiveASRTier) -> (encoder: MLComputeUnits, decoder: MLComputeUnits) {
        (.cpuAndNeuralEngine, .cpuAndGPU)
    }

    /// Loads strictly from the bundle: `download: false`, no prewarm pass (it doubles first-launch compile time),
    /// and the tokenizer is built from the bundled tokenizer.json *before* `loadModels()`, so WhisperKit's Hub
    /// fallback can never run (zero network). `log` receives stage timings for the diagnostic log.
    static func load(_ tier: LiveASRTier, root: URL? = LiveModels.root,
                     units: (encoder: MLComputeUnits, decoder: MLComputeUnits)? = nil,
                     log: @escaping @Sendable (String) -> Void = { _ in }) async throws -> LiveWhisperRecognizer {
        guard let modelFolder = LiveModels.modelFolder(tier, root: root),
              let tokFolder = LiveModels.tokenizerFolder(tier, root: root) else {
            throw LiveEngineError.modelMissing(tier.folder)
        }
        let u = units ?? computeUnits(tier)
        let t0 = Date()
        log("\(tier.rawValue): 开始加载 \(modelFolder.lastPathComponent) encoder=\(u.encoder.rawValue) decoder=\(u.decoder.rawValue)")
        let config = WhisperKitConfig(
            model: tier.folder,
            modelFolder: modelFolder.path,
            tokenizerFolder: tokFolder,
            computeOptions: ModelComputeOptions(melCompute: .cpuAndGPU, audioEncoderCompute: u.encoder, textDecoderCompute: u.decoder),
            verbose: false, logLevel: .error, prewarm: false, load: false, download: false)
        let kit = try await WhisperKit(config)
        let t1 = Date()
        let tokenizer = try await LiveBundledTokenizer.load(folder: tokFolder)
        kit.tokenizer = tokenizer
        log(String(format: "%@: tokenizer（本地）%.2fs", tier.rawValue, Date().timeIntervalSince(t1)))
        try await kit.loadModels()
        kit.tokenizer = tokenizer
        kit.textDecoder.isModelMultilingual = true          // both bundled tiers are multilingual (ja)
        let tm = kit.currentTimings
        log(String(format: "%@: 模型就绪 %.1fs（encoder %.1fs · decoder %.1fs）", tier.rawValue, Date().timeIntervalSince(t0),
                   tm.encoderLoadTime, tm.decoderLoadTime))
        let r = LiveWhisperRecognizer(tier: tier, kit: kit)
        r.loadSeconds = Date().timeIntervalSince(t0)
        return r
    }

    /// Latency-tuned options: Japanese fixed (no language detection), no timestamps, greedy with at most
    /// one temperature fallback, rolling context passed as prompt tokens (previous line, ≤ 48 tokens).
    func options(prompt: String?) -> DecodingOptions {
        var o = DecodingOptions(task: .transcribe, language: "ja", temperature: 0, temperatureFallbackCount: 1,
                                sampleLength: 96, usePrefillPrompt: true, detectLanguage: false, skipSpecialTokens: true,
                                withoutTimestamps: true, suppressBlank: true,
                                compressionRatioThreshold: 2.4, logProbThreshold: -1.0, noSpeechThreshold: 0.6)
        if let prompt, !prompt.isEmpty, let tok = kit.tokenizer {
            let ids = tok.encode(text: " " + prompt).filter { $0 < tok.specialTokens.specialTokenBegin }
            if !ids.isEmpty { o.promptTokens = Array(ids.suffix(48)) }
        }
        return o
    }

    func transcribe(_ samples: [Float], prompt: String?) async throws -> String {
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options(prompt: prompt))
        return results.map(\.text).joined()
    }
}

/// WhisperTokenizer built only from the bundled tokenizer.json / tokenizer_config.json (no Hub API, no network).
final class LiveBundledTokenizer: WhisperTokenizer, @unchecked Sendable {
    let tok: TokenizerWrapper
    let specialTokens: SpecialTokens
    let allLanguageTokens: Set<Int>

    static func load(folder: URL) async throws -> LiveBundledTokenizer {
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("tokenizer.json").path) else {
            throw LiveEngineError.modelMissing(folder.lastPathComponent + "/tokenizer.json")
        }
        return LiveBundledTokenizer(try await AutoTokenizerWrapper.from(modelFolder: folder))
    }

    init(_ t: TokenizerWrapper) {
        tok = t
        func id(_ s: String, _ d: Int) -> Int { t.convertTokenToId(s) ?? d }
        let eot = id("<|endoftext|>", 50257)
        specialTokens = SpecialTokens(endToken: eot, englishToken: id("<|en|>", 50259), noSpeechToken: id("<|nospeech|>", 50363),
                                      noTimestampsToken: id("<|notimestamps|>", 50364), specialTokenBegin: eot,
                                      startOfPreviousToken: id("<|startofprev|>", 50362), startOfTranscriptToken: id("<|startoftranscript|>", 50258),
                                      timeTokenBegin: id("<|0.00|>", 50365), transcribeToken: id("<|transcribe|>", 50360),
                                      translateToken: id("<|translate|>", 50359), whitespaceToken: id(" ", 220))
        allLanguageTokens = Set(Constants.languages.compactMap { t.convertTokenToId("<|\($0.value)|>") }.filter { $0 > eot })
    }

    func encode(text: String) -> [Int] { tok.encode(text: text) }
    func decode(tokens: [Int]) -> String { tok.decode(tokens: tokens) }
    func convertTokenToId(_ token: String) -> Int? { tok.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { tok.convertIdToToken(id) }
    /// Word timestamps are never requested by live subtitles; token-level split keeps the protocol honest.
    func splitToWordTokens(tokenIds: [Int]) -> (words: [String], wordTokens: [[Int]]) {
        (tokenIds.map { tok.decode(tokens: [$0]) }, tokenIds.map { [$0] })
    }
}

// MARK: - NLLB (bundled fallback)

final class NLLBCoreMLTranslator: LiveTranslating, @unchecked Sendable {
    let name = "NLLB-200 600M (本地)"
    let tokenizer: NLLBTokenizer
    private let encoder: MLModel
    private let decoder: MLModel
    private let lock = NSLock()

    init(root: URL, units: MLComputeUnits = .cpuAndGPU) throws {
        let dir = root.appendingPathComponent("nllb")
        tokenizer = try NLLBTokenizer(json: Data(contentsOf: dir.appendingPathComponent("nllb287_vocab.json")))
        let cfg = MLModelConfiguration()
        cfg.computeUnits = units
        func open(_ name: String) throws -> MLModel {
            let compiled = dir.appendingPathComponent(name + ".mlmodelc")
            if FileManager.default.fileExists(atPath: compiled.path) { return try MLModel(contentsOf: compiled, configuration: cfg) }
            let package = dir.appendingPathComponent(name + ".mlpackage")            // bench / tooling only
            return try MLModel(contentsOf: try MLModel.compileModel(at: package), configuration: cfg)
        }
        encoder = try open("NLLBEncoder")
        decoder = try open("NLLBDecoder")
    }

    private static func ints(_ values: [Int], length: Int, pad: Int) throws -> MLMultiArray {
        let a = try MLMultiArray(shape: [1, NSNumber(value: length)], dataType: .int32)
        let p = a.dataPointer.bindMemory(to: Int32.self, capacity: length)
        for i in 0 ..< length { p[i] = Int32(i < values.count ? values[i] : pad) }
        return a
    }

    func translateSync(_ japanese: String) throws -> String {
        lock.lock(); defer { lock.unlock() }
        let v = tokenizer.vocab
        let src = tokenizer.encode(japanese)
        let ids = try Self.ints(src, length: v.srcLen, pad: v.pad)
        let mask = try Self.ints([Int](repeating: 1, count: src.count), length: v.srcLen, pad: 0)
        let encOut = try encoder.prediction(from: MLDictionaryFeatureProvider(dictionary: ["input_ids": ids, "attention_mask": mask]))
        guard let hidden = encOut.featureValue(for: "hidden")?.multiArrayValue else { throw LiveEngineError.notReady }
        let step = try MLMultiArray(shape: [1, NSNumber(value: v.tgtLen)], dataType: .float32)
        let out = try NLLBGreedy.run(vocab: v) { prefix, pos -> [Float] in
            let dec = try Self.ints(prefix, length: v.tgtLen, pad: v.pad)
            let sp = step.dataPointer.bindMemory(to: Float32.self, capacity: v.tgtLen)
            for i in 0 ..< v.tgtLen { sp[i] = i == pos ? 1 : 0 }
            let r = try decoder.prediction(from: MLDictionaryFeatureProvider(dictionary: [
                "decoder_input_ids": dec, "encoder_hidden": hidden, "encoder_mask": mask, "step": step,
            ]))
            guard let logits = r.featureValue(for: "logits")?.multiArrayValue else { throw LiveEngineError.notReady }
            return Self.floats(logits)
        }
        return LiveText.chinesePunctuation(tokenizer.decode(out))
    }

    static func floats(_ a: MLMultiArray) -> [Float] {
        let n = a.count
        switch a.dataType {
        case .float32: return Array(UnsafeBufferPointer(start: a.dataPointer.bindMemory(to: Float32.self, capacity: n), count: n))
        case .double: return (0 ..< n).map { Float(a[$0].doubleValue) }
        default:
            #if arch(arm64)
            if a.dataType == .float16 {
                return Array(UnsafeBufferPointer(start: a.dataPointer.bindMemory(to: Float16.self, capacity: n), count: n)).map(Float.init)
            }
            #endif
            return (0 ..< n).map { a[$0].floatValue }
        }
    }

    func translate(_ japanese: String) async throws -> String { try translateSync(japanese) }
}

