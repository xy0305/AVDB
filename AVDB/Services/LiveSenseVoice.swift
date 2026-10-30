// Build 289 — SenseVoice-Small live recognizer (FunAudioLLM, non-autoregressive CTC; zh/en/ja/ko/yue).
// int8 ONNX export (k2-fsa sherpa-onnx, 2024-07-17) run by sherpa-onnx 2.0.1 (onnxruntime statically linked),
// language fixed to "ja", inverse text normalisation on. One encoder pass per VAD chunk.
// Licenses: model — FunASR Model Open Source License v1.1 (attribution + keep the model name);
// sherpa-onnx — Apache-2.0; onnxruntime — MIT. Foundation + SherpaOnnxC only (also builds on macOS / Linux).
import Foundation
#if canImport(SherpaOnnxC)
import SherpaOnnxC
#endif

// MARK: - SenseVoice (sherpa-onnx)

final class SenseVoiceRecognizer: LiveSpeechRecognizer, @unchecked Sendable {
    let tier: LiveASRTier = .senseVoice
    private(set) var loadSeconds: Double = 0
    let threads: Int
    let provider: String
    #if canImport(SherpaOnnxC)
    private let recognizer: OpaquePointer
    #endif
    private let lock = NSLock()           // sherpa streams are created per call; decode itself is serialised

    /// threads: 2 keeps one big core + headroom for AVPlayer / UI; provider "cpu" (int8 ops are CPU-optimised in
    /// onnxruntime; the Core ML EP only accelerates fp32/fp16 graphs and re-compiles on first run).
    init(folder: URL, threads: Int = 2, provider: String = "cpu") throws {
        self.threads = threads
        self.provider = provider
        #if canImport(SherpaOnnxC)
        let t0 = Date()
        let model = folder.appendingPathComponent("model.int8.onnx").path
        let tokens = folder.appendingPathComponent("tokens.txt").path
        guard FileManager.default.fileExists(atPath: model), FileManager.default.fileExists(atPath: tokens) else {
            throw LiveEngineError.modelMissing(folder.lastPathComponent + "/model.int8.onnx")
        }
        var owned: [UnsafeMutablePointer<CChar>] = []
        func c(_ s: String) -> UnsafePointer<CChar> { let p = strdup(s)!; owned.append(p); return UnsafePointer(p) }
        defer { owned.forEach { free($0) } }
        var cfg = SherpaOnnxOfflineRecognizerConfig()
        cfg.feat_config.sample_rate = 16000
        cfg.feat_config.feature_dim = 80
        cfg.model_config.sense_voice.model = c(model)
        cfg.model_config.sense_voice.language = c("ja")
        cfg.model_config.sense_voice.use_itn = 1
        cfg.model_config.tokens = c(tokens)
        cfg.model_config.num_threads = Int32(threads)
        cfg.model_config.debug = 0
        cfg.model_config.provider = c(provider)
        cfg.decoding_method = c("greedy_search")
        guard let r = SherpaOnnxCreateOfflineRecognizer(&cfg) else {
            throw LiveEngineError.unavailable("SenseVoice 初始化失败（\(provider)）")
        }
        recognizer = r
        loadSeconds = Date().timeIntervalSince(t0)
        #else
        throw LiveEngineError.unavailable("SherpaOnnxC 未链接")
        #endif
    }

    deinit {
        #if canImport(SherpaOnnxC)
        SherpaOnnxDestroyOfflineRecognizer(recognizer)
        #endif
    }

    /// Synchronous decode (callers are the utility-QoS worker / bench). `prompt` is unused: CTC has no context.
    func transcribeSync(_ samples: [Float]) -> String {
        #if canImport(SherpaOnnxC)
        lock.lock(); defer { lock.unlock() }
        guard !samples.isEmpty, let stream = SherpaOnnxCreateOfflineStream(recognizer) else { return "" }
        defer { SherpaOnnxDestroyOfflineStream(stream) }
        samples.withUnsafeBufferPointer { SherpaOnnxAcceptWaveformOffline(stream, 16000, $0.baseAddress, Int32($0.count)) }
        SherpaOnnxDecodeOfflineStream(recognizer, stream)
        guard let res = SherpaOnnxGetOfflineStreamResult(stream) else { return "" }
        defer { SherpaOnnxDestroyOfflineRecognizerResult(res) }
        return res.pointee.text.map { String(cString: $0) } ?? ""
        #else
        return ""
        #endif
    }

    func transcribe(_ samples: [Float], prompt: String?) async throws -> String { transcribeSync(samples) }

    static var version: String {
        #if canImport(SherpaOnnxC)
        return SherpaOnnxGetVersionStr().map { String(cString: $0) } ?? "?"
        #else
        return "not linked"
        #endif
    }
}

