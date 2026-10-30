// Build 287 — on-device engines behind LiveSubtitleCore's protocols.
//  • LiveWhisperRecognizer — WhisperKit (Core ML), Japanese, encoder + decoder on the Neural Engine.
//  • NLLBCoreMLTranslator  — bundled NLLB-200-distilled-600M (int8, trimmed vocab) ja → zh-Hans, Core ML.
//  • AppleTranslator       — Apple Translation (iOS 18+), preferred when the ja→zh-Hans packs are installed.
import CoreML
import Foundation
import WhisperKit

enum LiveModels {
    /// Folder reference `LiveModels` in the app bundle (populated by CI; see scripts/live287).
    static var root: URL? {
        if let override = ProcessInfo.processInfo.environment["AVDB_LIVE_MODELS"] { return URL(fileURLWithPath: override) }
        return Bundle.main.url(forResource: "LiveModels", withExtension: nil)
    }
    static func whisperAvailable(_ tier: LiveASRTier) -> Bool {
        guard let root else { return false }
        let fm = FileManager.default
        return fm.fileExists(atPath: root.appendingPathComponent(tier.folder).appendingPathComponent("AudioEncoder.mlmodelc").path)
            && fm.fileExists(atPath: root.appendingPathComponent(tier.tokenizer).appendingPathComponent("tokenizer.json").path)
    }
    static var nllbAvailable: Bool {
        guard let root else { return false }
        return FileManager.default.fileExists(atPath: root.appendingPathComponent("nllb/NLLBDecoder.mlmodelc").path)
    }
}

// MARK: - Whisper

final class LiveWhisperRecognizer: LiveSpeechRecognizer, @unchecked Sendable {
    let tier: LiveASRTier
    private let kit: WhisperKit
    private(set) var loadSeconds: Double = 0

    private init(tier: LiveASRTier, kit: WhisperKit) { self.tier = tier; self.kit = kit }

    static func load(_ tier: LiveASRTier, root: URL? = LiveModels.root,
                     encoder: MLComputeUnits = .cpuAndNeuralEngine, decoder: MLComputeUnits = .cpuAndNeuralEngine) async throws -> LiveWhisperRecognizer {
        guard let root, LiveModels.whisperAvailable(tier) || ProcessInfo.processInfo.environment["AVDB_LIVE_MODELS"] != nil else {
            throw LiveEngineError.modelMissing(tier.folder)
        }
        let t0 = Date()
        let config = WhisperKitConfig(
            model: tier.folder,
            modelFolder: root.appendingPathComponent(tier.folder).path,
            tokenizerFolder: root.appendingPathComponent(tier.tokenizer),
            computeOptions: ModelComputeOptions(melCompute: .cpuAndGPU, audioEncoderCompute: encoder, textDecoderCompute: decoder),
            verbose: false, logLevel: .error, prewarm: true, load: true, download: false)
        let kit = try await WhisperKit(config)
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

// MARK: - NLLB (bundled fallback)

final class NLLBCoreMLTranslator: LiveTranslating, @unchecked Sendable {
    let name = "NLLB-200 600M (本地)"
    let tokenizer: NLLBTokenizer
    private let encoder: MLModel
    private let decoder: MLModel
    private let lock = NSLock()

    init(root: URL, units: MLComputeUnits = .cpuAndNeuralEngine) throws {
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

