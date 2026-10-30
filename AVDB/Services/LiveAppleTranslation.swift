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
/// stalling the subtitle queue.
final class LiveTranslatorChain: LiveTranslating, @unchecked Sendable {
    let primary: LiveTranslating?
    let fallback: LiveTranslating?
    private let lock = NSLock()
    private var primaryFailures = 0
    var name: String { [primary?.name, fallback?.name].compactMap { $0 }.joined(separator: " → ") }
    private(set) var lastEngine = ""

    init(primary: LiveTranslating?, fallback: LiveTranslating?) { self.primary = primary; self.fallback = fallback }
    private func locked<T>(_ f: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return f() }

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
