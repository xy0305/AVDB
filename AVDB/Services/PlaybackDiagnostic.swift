import Foundation

/// Diagnostic data only. Never retain Error.userInfo, response bodies or request URLs.
struct PlaybackDiagnostic: Error, LocalizedError, Equatable, Sendable {
    enum Stage: String, Sendable {
        case discovery = "查询", document = "详情", embed = "嵌入", manifest = "清单"
        case segment = "分片", decode = "播放", dns = "DNS", unknown = "未知阶段"
    }
    enum Category: String, Sendable {
        case http = "HTTP", tls = "TLS 错误（未降低证书验证）", timeout = "请求超时"
        case cancelled = "已取消", unsupported = "暂不支持（适配或协议未完成）"
        case invalidManifest = "清单无效", dns = "域名解析失败", connection = "连接失败"
        case unsafe = "安全策略拒绝", noMatch = "未匹配", tooLarge = "响应超出大小限制"
        case blocked = "来源拒绝访问或要求验证（未绕过限制）", unknown = "失败（原因未确定）"
    }
    let stage: Stage
    let category: Category
    let httpCode: Int?
    let systemCode: Int?
    let host: String?
    let dnsContext: Bool
    init(stage: Stage, category: Category, httpCode: Int? = nil, systemCode: Int? = nil,
         host: String? = nil, dnsContext: Bool = false) {
        self.stage = stage; self.category = category
        self.httpCode = httpCode.flatMap { (100...599).contains($0) ? $0 : nil }
        self.systemCode = systemCode; self.host = host.flatMap(Self.safeHost)
        self.dnsContext = dnsContext
    }
    static func safeHost(_ value: String) -> String? {
        guard value.utf8.count <= 253, value.range(of: #"^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$"#, options: .regularExpression) != nil,
              !value.contains("..") else { return nil }
        return value.lowercased()
    }
    static func resourceHost(_ url: URL?) -> String? {
        guard let url, ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil else { return nil }
        return url.host.flatMap(safeHost)
    }
    var errorDescription: String? { display }
    var display: String {
        let place = stage.rawValue + (dnsContext && stage != .dns ? "/DNS" : "")
        let status = httpCode.map { " \($0)" } ?? ""
        let code = systemCode.map { "（系统码 \($0)）" } ?? ""
        return (host.map { $0 + " · " } ?? "") + place + "：" + category.rawValue + status + code
    }
    static func system(_ error: Error, stage: Stage, url: URL? = nil) -> Self {
        if let typed = error as? Self { return typed }
        if error is CancellationError { return .init(stage: stage, category: .cancelled) }
        let e = error as NSError
        // The same integer in another domain does not mean a URL-loading error.
        guard e.domain == NSURLErrorDomain else { return .init(stage: stage, category: .unknown, host: resourceHost(url)) }
        let category: Category
        switch e.code {
        case NSURLErrorCancelled: category = .cancelled
        case NSURLErrorTimedOut: category = .timeout
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: category = .dns
        case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet: category = .connection
        case -1206 ... -1200: category = .tls
        case NSURLErrorUnsupportedURL: category = .unsupported
        default: category = .unknown
        }
        return .init(stage: stage, category: category, systemCode: e.code, host: resourceHost(url))
    }
}

/// Only trusted layer context determines stage. Legacy free text is never rendered.
extension OnlineFailure {
    func presentation(at context: PlaybackDiagnostic.Stage) -> PlaybackDiagnostic {
        typealias D = PlaybackDiagnostic
        var category: D.Category
        switch self {
        case .safe(let value):
            guard value.stage == .unknown else { return value }
            return D(stage: context, category: value.category, httpCode: value.httpCode,
                     systemCode: value.systemCode, host: value.host, dnsContext: value.dnsContext)
        case .diagnostic(let stage, let host, let reason):
            let known: [String:D.Stage] = ["查询":.discovery, "详情":.document, "清单":.manifest,
                "清单解析":.manifest, "分片":.segment, "DNS":.dns]
            let parts = stage.split(separator: "/").map(String.init)
            let actual = parts.first.flatMap { known[$0] } ?? context
            // Existing diagnostic producers provide bounded fixed reasons. Classify
            // only explicit known wording, never print or retain that free text.
            if reason.contains("HTTP "), let code = reason.split(separator: " ").compactMap({ Int($0.trimmingCharacters(in: .punctuationCharacters)) }).first(where: { (100...599).contains($0) }) {
                return D(stage: actual, category: .http, httpCode: code, host: host, dnsContext: parts.contains("DNS"))
            }
            if reason == OnlineFailure.incomplete.localizedDescription || reason == OnlineFailure.unsupported.localizedDescription { category = .unsupported }
            else if reason == OnlineFailure.timeout.localizedDescription { category = .timeout }
            else if reason == OnlineFailure.cancelled.localizedDescription { category = .cancelled }
            else if reason == OnlineFailure.tls.localizedDescription { category = .tls }
            else if reason == OnlineFailure.parse.localizedDescription { category = actual == .manifest ? .invalidManifest : .unknown }
            else { category = .unknown }
            return D(stage: actual, category: category, host: host, dnsContext: parts.contains("DNS"))
        case .noMatch: category = .noMatch
        case .blocked: category = .blocked
        case .tls: category = .tls
        case .parse: category = context == .manifest ? .invalidManifest : .unknown
        case .timeout: category = .timeout
        case .unsafe: category = .unsafe
        case .resolver: category = .dns
        case .tooLarge: category = .tooLarge
        case .cancelled: category = .cancelled
        case .unsupported, .incomplete, .drm, .keyUnavailable: category = .unsupported
        case .http(let code): return D(stage: context, category: .http, httpCode: code)
        }
        return D(stage: context, category: category)
    }
    static func httpResponse(_ code: Int, at url: URL) -> OnlineFailure {
        .safe(PlaybackDiagnostic(stage: .unknown, category: .http, httpCode: code,
                                 host: PlaybackDiagnostic.resourceHost(url)))
    }
    static func captured(_ error: Error, at stage: PlaybackDiagnostic.Stage) -> OnlineFailure {
        if let legacy = error as? OnlineFailure { return legacy }
        return .safe(PlaybackDiagnostic.system(error, stage: stage))
    }
}

/// A real deadline must not wait for an uncooperative child of a task group.
/// Terminal result is set once under a lock; cancellation/timeout resume the caller
/// immediately and cancel workers. Late work may finish but cannot publish a value.
final class PlaybackDeadline<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private let started = DispatchTime.now().uptimeNanoseconds
    private let limit: UInt64
    private init(limit: UInt64) { self.limit = limit }
    private var result: Result<Value, Error>?
    private var continuation: CheckedContinuation<Value, Error>?
    private var workers: [Task<Void, Never>] = []
    private func install(_ continuation: CheckedContinuation<Value, Error>) -> Bool {
        lock.lock()
        if let result { lock.unlock(); continuation.resume(with: result); return false }
        else { self.continuation = continuation; lock.unlock(); return true }
    }
    private func retain(_ tasks: [Task<Void, Never>]) {
        lock.lock()
        if result != nil { lock.unlock(); tasks.forEach { $0.cancel() } }
        else { workers = tasks; lock.unlock() }
    }
    private func finish(_ value: Result<Value, Error>) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        let terminal: Result<Value, Error> = DispatchTime.now().uptimeNanoseconds - started >= limit ? .failure(OnlineFailure.timeout) : value
        result = terminal
        let continuation = self.continuation; self.continuation = nil
        let workers = self.workers; self.workers = []
        lock.unlock()
        workers.forEach { $0.cancel() }
        continuation?.resume(with: terminal)
    }
    static func run(nanoseconds: UInt64, work: @escaping @Sendable () async throws -> Value) async throws -> Value {
        let gate = PlaybackDeadline<Value>(limit: nanoseconds)
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                guard gate.install(continuation) else { return }
                let workTask = Task {
                    do { try Task.checkCancellation(); gate.finish(.success(try await work())) }
                    catch { gate.finish(.failure(error)) }
                }
                let timeoutTask = Task {
                    do {
                        try await Task.sleep(nanoseconds: nanoseconds)
                        gate.finish(.failure(OnlineFailure.timeout))
                    } catch { /* cancelled timer cannot change a terminal outcome */ }
                }
                gate.retain([workTask, timeoutTask])
            }
        }, onCancel: { gate.finish(.failure(OnlineFailure.cancelled)) })
    }
}
