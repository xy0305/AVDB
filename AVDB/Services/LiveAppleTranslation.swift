// Build 287 — Apple Translation (iOS 18+) for live subtitles + the translator chain (Apple → NLLB fallback).
// Kept free of WhisperKit / Core ML so the UI host can compile it alone.
import Foundation
#if canImport(Translation)
import Translation
#endif

enum LiveEngineError: LocalizedError {
    case modelMissing(String), notReady, unavailable(String)
    var errorDescription: String? {
        switch self {
        case .modelMissing(let m): "模型未打包：\(m)"
        case .notReady: "模型未就绪"
        case .unavailable(let m): m
        }
    }
}

// MARK: - Apple Translation

enum AppleTranslationStatus: String, Sendable {
    case unknown, unsupportedOS, unsupported, needsDownload, installed
    var title: String {
        switch self {
        case .unknown: "检测中"
        case .unsupportedOS: "需要 iOS 18"
        case .unsupported: "此设备不支持"
        case .needsDownload: "需下载离线语言包（日语 → 简体中文）"
        case .installed: "已安装（离线）"
        }
    }
}

enum AppleTranslation {
    static func status() async -> AppleTranslationStatus {
        #if canImport(Translation)
        if #available(iOS 18.0, macOS 15.0, *) {
            let s = await LanguageAvailability().status(from: Locale.Language(identifier: "ja"), to: Locale.Language(identifier: "zh-Hans"))
            switch s {
            case .installed: return .installed
            case .supported: return .needsDownload
            case .unsupported: return .unsupported
            @unknown default: return .unknown
            }
        }
        #endif
        return .unsupportedOS
    }
}

#if canImport(Translation)
/// Direct, UI-less session (iOS 26+) once the packs are installed.
@available(iOS 26.0, macOS 26.0, *)
final class AppleDirectTranslator: LiveTranslating, @unchecked Sendable {
    let name = "Apple 翻译"
    private let session = TranslationSession(installedSource: Locale.Language(identifier: "ja"), target: Locale.Language(identifier: "zh-Hans"))
    func translate(_ japanese: String) async throws -> String {
        LiveText.chinesePunctuation(try await session.translate(japanese).targetText)
    }
}

/// iOS 18–25: sessions only exist inside SwiftUI's `.translationTask`, so a hidden host view owns the
/// session and serves requests from an AsyncStream. The same host can ask the user to download the packs.
@available(iOS 18.0, macOS 15.0, *)
final class AppleTranslationBridge: LiveTranslating, ObservableObject, @unchecked Sendable {
    let name = "Apple 翻译"
    struct Request { let text: String; let reply: CheckedContinuation<String, Error> }
    private let lock = NSLock()
    private var continuation: AsyncStream<Request>.Continuation?
    private var stream: AsyncStream<Request>?
    @MainActor @Published var configuration: TranslationSession.Configuration?
    @MainActor @Published var attached = false

    init() { makeStream() }

    private func makeStream() {
        lock.lock(); defer { lock.unlock() }
        let (s, c) = AsyncStream<Request>.makeStream()
        stream = s; continuation = c
    }

    @MainActor func activate() {
        if configuration == nil {
            configuration = TranslationSession.Configuration(source: Locale.Language(identifier: "ja"), target: Locale.Language(identifier: "zh-Hans"))
        } else {
            shutdown()              // one consumer per stream: the re-run task gets a fresh one
            configuration?.invalidate()
        }
    }

    /// Runs inside `.translationTask`: first prepare (prompts a pack download if needed), then serve requests.
    func serve(_ session: TranslationSession) async {
        try? await session.prepareTranslation()
        let s: AsyncStream<Request>? = { lock.lock(); defer { lock.unlock() }; return stream }()
        guard let s else { return }
        await MainActor.run { attached = true }
        for await req in s {
            do { req.reply.resume(returning: LiveText.chinesePunctuation(try await session.translate(req.text).targetText)) }
            catch { req.reply.resume(throwing: error) }
        }
        await MainActor.run { attached = false }
    }

    func translate(_ japanese: String) async throws -> String {
        try await withCheckedThrowingContinuation { c in
            lock.lock(); let cont = continuation; lock.unlock()
            guard let cont else { c.resume(throwing: LiveEngineError.notReady); return }
            if case .terminated = cont.yield(Request(text: japanese, reply: c)) { c.resume(throwing: LiveEngineError.notReady) }
        }
    }

    func shutdown() {
        lock.lock(); continuation?.finish(); continuation = nil; lock.unlock()
        makeStream()
    }
}
#endif

/// Apple first (when installed / reachable), NLLB on any Apple failure. Timeouts keep a hung session from
/// stalling the subtitle queue. 292: optional on-device LLM in front for whole lines with context — only when the
/// guard allows it (cool, not Low Power, battery ≥ 20 %), the line is due later than the LLM's recent latency,
/// and it has not failed 3× in a row (then 120 s cool-down); otherwise the classic per-piece path runs.
final class LiveTranslatorChain: LiveContextTranslating, @unchecked Sendable {
    let primary: LiveTranslating?
    let fallback: LiveTranslating?
    private let lock = NSLock()
    private var primaryFailures = 0
    private var _llm: LiveContextTranslating?
    private var llmAllowed = true
    private var llmWhy = ""
    private var llmMsAvg = 0.0, llmCount = 0, llmFailures = 0
    private var llmPausedUntil = Date.distantPast
    private(set) var llmLines = 0, llmSkippedLate = 0, llmSkippedGuard = 0
    private var llmLastError = ""
    var name: String { [locked { _llm }?.name, primary?.name, fallback?.name].compactMap { $0 }.joined(separator: " → ") }
    private(set) var lastEngine = ""

    init(primary: LiveTranslating?, fallback: LiveTranslating?, llm: LiveContextTranslating? = nil) {
        self.primary = primary; self.fallback = fallback; _llm = llm
    }
    private func locked<T>(_ f: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return f() }

    var llm: LiveContextTranslating? { get { locked { _llm } } set { locked { _llm = newValue; llmCount = 0; llmMsAvg = 0; llmFailures = 0 } } }
    func setLLMAllowed(_ ok: Bool, why: String) { locked { llmAllowed = ok; llmWhy = why } }
    var llmStatus: String {
        locked {
            guard _llm != nil else { return "" }
            let state = !llmAllowed ? "暂停（\(llmWhy)）" : Date() < llmPausedUntil ? "冷却中（连续失败）" : "启用"
            return String(format: "LLM %@ · %d 行 · 平均 %.0fms · 来不及→常规 %d · 守护→常规 %d", state, llmLines, llmMsAvg, llmSkippedLate, llmSkippedGuard)
                + (llmLastError.isEmpty ? "" : " · 上次错误 \(llmLastError)")
        }
    }

    func contextTranslate(_ japanese: String, context: LiveMTContext) async throws -> String? {
        let gate: (llm: LiveContextTranslating?, budget: Double) = locked {
            guard let l = _llm else { return (nil, 0) }
            guard llmAllowed, Date() >= llmPausedUntil else { llmSkippedGuard += 1; return (nil, 0) }
            let expect = llmCount == 0 ? 1.2 : llmMsAvg / 1000
            guard context.budget >= expect + 0.3 else { llmSkippedLate += 1; return (nil, 0) }
            return (l, min(context.budget, 4.0))
        }
        guard let llm = gate.llm else { return nil }
        let ctx: LiveMTContext = { var c = context; c.budget = gate.budget; return c }()
        let t0 = Date()
        do {
            let r = try await Self.withTimeout(gate.budget + 0.5) { try await llm.contextTranslate(japanese, context: ctx) }
            let ms = Date().timeIntervalSince(t0) * 1000
            locked {
                llmMsAvg += (llmCount == 0 ? 1.0 : 0.25) * (ms - llmMsAvg); llmCount += 1
                llmFailures = 0; llmLines += 1; lastEngine = llm.name
            }
            return r
        } catch {
            locked {
                llmFailures += 1
                if llmFailures >= 3 { llmFailures = 0; llmPausedUntil = Date().addingTimeInterval(120) }
            }
            locked { llmLastError = error.localizedDescription }
            return nil
        }
    }

    func translate(_ japanese: String) async throws -> String {
        let usePrimary = locked { primaryFailures < 3 }
        if let primary, usePrimary {
            do {
                let r = try await Self.withTimeout(2.0) { try await primary.translate(japanese) }
                locked { primaryFailures = 0; lastEngine = primary.name }
                return r
            } catch {
                locked { primaryFailures += 1 }
            }
        }
        guard let fallback else { throw LiveEngineError.unavailable("没有可用的翻译引擎") }
        let r = try await fallback.translate(japanese)
        locked { lastEngine = fallback.name }
        return r
    }

    static func withTimeout<T: Sendable>(_ seconds: Double, _ op: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { g in
            g.addTask { try await op() }
            g.addTask { try await Task.sleep(nanoseconds: UInt64(seconds * 1e9)); throw LiveEngineError.unavailable("翻译超时") }
            let r = try await g.next()!
            g.cancelAll()
            return r
        }
    }
}
