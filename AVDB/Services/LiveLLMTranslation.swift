// Build 292 — optional on-device LLM translator for live subtitles: Sakura-1.5B-Qwen2.5-v1.0 (SakuraLLM, CC BY-NC-SA 4.0,
// GGUF Q5_K_S by shing3232) on llama.cpp (MIT, b12018 xcframework, Metal). Downloaded only on explicit user request
// (≈ 1.26 GB, sha256-pinned) — never bundled. Output is machine translation and is labelled 机翻.
// Uses the previous ≤ 3 lines (ja + its own zh) as chat history and the title's actress names as a glossary
// (Sakura v1.0 术语表 prompt). Falls back to Apple Translation / NLLB when hot / Low Power / low battery, when the line
// is due sooner than the LLM can answer, or after repeated failures (LiveTranslatorChain).
import Foundation
import CryptoKit
#if canImport(llama)
import llama
#endif

enum LiveLLMModel {
    static let fileName = "sakura-1.5b-qwen2.5-v1.0-Q5KS.gguf"
    static let repoPath = "shing3232/Sakura-1.5B-Qwen2.5-v1.0-GGUF-IMX/resolve/main/sakura-1.5b-qwen2.5-v1.0-Q5KS.gguf"
    static let bytes: Int64 = 1_259_173_504
    static let sha256 = "6722487146c594984e4d222cae0b926c9715ffff712afb5f348b603417c01680"
    static let displayName = "Sakura-1.5B（机翻）"
    static let license = "Sakura-1.5B-Qwen2.5-v1.0 © SakuraLLM，CC BY-NC-SA 4.0（仅限非商业使用）；GGUF 量化 shing3232；推理 llama.cpp（MIT）。译文为机器翻译（机翻）。"
    static let enabledKey = "live.translator.llm292"
    static var folder: URL { LiveModels.downloadRoot.appendingPathComponent("llm292", isDirectory: true) }
    static var fileURL: URL { folder.appendingPathComponent(fileName) }
    static var downloaded: Bool {
        ((try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? 0) == bytes
            && UserDefaults.standard.bool(forKey: "live.llm292.verified")
    }
    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
    static var linked: Bool {
        #if canImport(llama)
        true
        #else
        false
        #endif
    }

    /// huggingface.co first, then hf-mirror.com; resumable is not needed (single 1.26 GB file, retry restarts).
    static func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var dir = LiveModels.downloadRoot; try? dir.setResourceValues(values)
        UserDefaults.standard.set(false, forKey: "live.llm292.verified")
        var lastError: Error = LiveEngineError.modelMissing(fileName)
        for host in ["https://huggingface.co/", "https://hf-mirror.com/"] {
            do {
                LiveDiagnostics.shared.log("LLM 下载开始 \(host)")
                let tmp = try await LiveFileDownloader.fetch(URL(string: host + repoPath)!, expected: bytes, progress: progress)
                try verify(tmp)
                try? FileManager.default.removeItem(at: fileURL)
                try FileManager.default.moveItem(at: tmp, to: fileURL)
                UserDefaults.standard.set(true, forKey: "live.llm292.verified")
                LiveDiagnostics.shared.log("LLM 下载完成并校验 sha256")
                return
            } catch {
                lastError = error
                LiveDiagnostics.shared.log("LLM 下载失败 \(host): \(error.localizedDescription)")
            }
        }
        throw lastError
    }
    static func verify(_ url: URL) throws {
        let h = try FileHandle(forReadingFrom: url); defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try h.read(upToCount: 8 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard hex == sha256 else { throw LiveEngineError.unavailable("模型校验失败（sha256 不符）") }
    }
    static func delete() {
        try? FileManager.default.removeItem(at: folder)
        UserDefaults.standard.set(false, forKey: "live.llm292.verified")
    }

    // MARK: prompt (Sakura v1.0 ChatML; identical to scripts/live292/eval/llm_tr.py)

    static let system = "你是一个轻小说翻译模型，可以流畅通顺地以日本轻小说的风格将日文翻译成简体中文，并联系上下文正确使用人称代词，不擅自添加原文中没有的代词。"
    static func relevantGlossary(_ g: [LiveGlossaryEntry], for ja: String) -> [LiveGlossaryEntry] {
        g.filter { ja.contains($0.ja) }
    }
    static func prompt(_ ja: String, context: LiveMTContext) -> String {
        var p = "<|im_start|>system\n\(system)<|im_end|>\n"
        for h in context.history.suffix(3) {
            p += "<|im_start|>user\n将下面的日文文本翻译成中文：\(h.ja)<|im_end|>\n<|im_start|>assistant\n\(h.zh)<|im_end|>\n"
        }
        let g = relevantGlossary(context.glossary, for: ja)
        if g.isEmpty {
            p += "<|im_start|>user\n将下面的日文文本翻译成中文：\(ja)<|im_end|>\n"
        } else {
            let dict = g.map { "\($0.ja)->\($0.zh) #人名" }.joined(separator: "\n")
            p += "<|im_start|>user\n根据以下术语表（可以为空）：\n\(dict)\n将下面的日文文本根据对应关系和备注翻译成中文：\(ja)<|im_end|>\n"
        }
        return p + "<|im_start|>assistant\n"
    }
}

/// URLSession download with byte progress (delegate-based; the async API has no progress on iOS 17).
final class LiveFileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var cont: CheckedContinuation<URL, Error>?
    private let progress: @Sendable (Double) -> Void
    private let expected: Int64
    private init(expected: Int64, progress: @escaping @Sendable (Double) -> Void) { self.expected = expected; self.progress = progress }

    static func fetch(_ url: URL, expected: Int64, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let d = LiveFileDownloader(expected: expected, progress: progress)
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60; cfg.timeoutIntervalForResource = 3 * 3600
        let session = URLSession(configuration: cfg, delegate: d, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { c in
            d.cont = c
            session.downloadTask(with: url).resume()
        }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expected
        progress(min(1, Double(totalBytesWritten) / Double(max(1, total))))
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // move out of the temporary location before returning (the system deletes it)
        let dst = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gguf")
        do {
            if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
                throw LiveEngineError.unavailable("HTTP \(http.statusCode)")
            }
            try FileManager.default.moveItem(at: location, to: dst)
            let size = ((try? FileManager.default.attributesOfItem(atPath: dst.path)[.size] as? NSNumber)?.int64Value) ?? 0
            guard size == expected else { try? FileManager.default.removeItem(at: dst); throw LiveEngineError.unavailable("大小不符 \(size)") }
            cont?.resume(returning: dst)
        } catch { cont?.resume(throwing: error) }
        cont = nil
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { cont?.resume(throwing: error); cont = nil }
    }
}

#if canImport(llama)
/// One llama.cpp context on a private serial queue. KV cache reuse: the longest common token prefix with the
/// previous prompt is kept (system prompt + shared history), only the tail is decoded.
final class LiveLLMTranslator: LiveContextTranslating, @unchecked Sendable {
    let name = LiveLLMModel.displayName
    private let model: OpaquePointer
    private let ctx: OpaquePointer
    private let vocab: OpaquePointer
    private let sampler: UnsafeMutablePointer<llama_sampler>
    private var kv: [llama_token] = []
    private let queue = DispatchQueue(label: "avdb.live.llm292", qos: .utility)
    private(set) var loadSeconds = 0.0
    static let maxNew = 48

    private init(model: OpaquePointer, ctx: OpaquePointer, sampler: UnsafeMutablePointer<llama_sampler>) {
        self.model = model; self.ctx = ctx; self.sampler = sampler
        vocab = llama_model_get_vocab(model)
    }
    deinit { llama_sampler_free(sampler); llama_free(ctx); llama_model_free(model) }

    static func load(path: String = LiveLLMModel.fileURL.path) throws -> LiveLLMTranslator {
        let t0 = Date()
        llama_backend_init()
        var mp = llama_model_default_params()
        mp.n_gpu_layers = 99                       // Metal: all layers
        guard let m = llama_model_load_from_file(path, mp) else { throw LiveEngineError.unavailable("LLM 模型加载失败") }
        var cp = llama_context_default_params()
        cp.n_ctx = 1024; cp.n_batch = 512; cp.n_ubatch = 512
        cp.n_threads = 2; cp.n_threads_batch = 2
        guard let c = llama_init_from_model(m, cp) else { llama_model_free(m); throw LiveEngineError.unavailable("LLM 上下文创建失败") }
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        llama_sampler_chain_add(chain, llama_sampler_init_penalties(llama_vocab_n_tokens(llama_model_get_vocab(m)), 64, 1.0, 0.1, 0.0))
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(0.3, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(0.1))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(7))
        let t = LiveLLMTranslator(model: m, ctx: c, sampler: chain)
        t.loadSeconds = Date().timeIntervalSince(t0)
        return t
    }

    func translate(_ japanese: String) async throws -> String { try await translate(japanese, context: LiveMTContext()) }
    func contextTranslate(_ japanese: String, context: LiveMTContext) async throws -> String? {
        try await translate(japanese, context: context)
    }
    func translate(_ japanese: String, context: LiveMTContext) async throws -> String {
        let prompt = LiveLLMModel.prompt(japanese, context: context)
        let deadline = Date().addingTimeInterval(max(0.5, context.budget))
        return try await withCheckedThrowingContinuation { c in
            queue.async { [self] in
                do { c.resume(returning: try generate(prompt, deadline: deadline)) } catch { c.resume(throwing: error) }
            }
        }
    }

    private func tokenize(_ s: String) -> [llama_token] {
        let utf8 = Array(s.utf8CString)
        var out = [llama_token](repeating: 0, count: utf8.count + 8)
        let n = utf8.withUnsafeBufferPointer { b in
            llama_tokenize(vocab, b.baseAddress, Int32(utf8.count - 1), &out, Int32(out.count), false, true)
        }
        return n >= 0 ? Array(out.prefix(Int(n))) : []
    }
    private func piece(_ t: llama_token) -> [UInt8] {
        var buf = [CChar](repeating: 0, count: 64)
        let n = llama_token_to_piece(vocab, t, &buf, Int32(buf.count), 0, false)
        return n > 0 ? buf.prefix(Int(n)).map { UInt8(bitPattern: $0) } : []
    }
    private func decode(_ tokens: [llama_token]) throws {
        var toks = tokens
        var i = 0
        while i < toks.count {
            let n = min(512, toks.count - i)
            let r = toks.withUnsafeMutableBufferPointer { b in llama_decode(ctx, llama_batch_get_one(b.baseAddress! + i, Int32(n))) }
            if r != 0 { throw LiveEngineError.unavailable("llama_decode \(r)") }
            i += n
        }
    }

    private func generate(_ prompt: String, deadline: Date) throws -> String {
        let toks = tokenize(prompt)
        guard !toks.isEmpty else { return "" }
        let mem = llama_get_memory(ctx)
        if toks.count + Self.maxNew + 8 > Int(llama_n_ctx(ctx)) { llama_memory_clear(mem, true); kv = [] }
        var keep = 0
        while keep < min(kv.count, toks.count), kv[keep] == toks[keep] { keep += 1 }
        if keep == toks.count { keep -= 1 }                       // always decode ≥ 1 token for fresh logits
        if keep < kv.count { _ = llama_memory_seq_rm(mem, 0, Int32(keep), -1); kv.removeSubrange(keep...) }
        try decode(Array(toks[keep...])); kv += toks[keep...]
        llama_sampler_reset(sampler)
        var bytes: [UInt8] = []
        for _ in 0 ..< Self.maxNew {
            if Date() > deadline { throw LiveEngineError.unavailable("LLM 超时") }
            let t = llama_sampler_sample(sampler, ctx, -1)
            if llama_vocab_is_eog(vocab, t) { break }
            let p = piece(t)
            if p.contains(10) { bytes += p.prefix { $0 != 10 }; break }     // one subtitle line
            bytes += p
            try decode([t]); kv.append(t)
        }
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
