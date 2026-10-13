import Foundation
import Combine

@MainActor final class MissAVSource: ObservableObject {
    static let shared = MissAVSource()
    @Published private(set) var base: URL
    @Published private(set) var generation = 0
    @Published private(set) var routes = MissAVHTML.routes
    private var sessions: [UUID: URLSession] = [:]
    // Independent in-memory store: never URLSession.shared, HTTPCookieStorage.shared or WebKit.
    private var cookieStorage = URLSessionConfiguration.ephemeral.httpCookieStorage
    private let defaults: UserDefaults
    private let protocolClasses: [AnyClass]?
    init(defaults: UserDefaults = .standard, protocolClasses: [AnyClass]? = nil) {
        self.defaults = defaults
        self.protocolClasses = protocolClasses
        base = (try? JRPolicy.domain(defaults.string(forKey: "missav.baseDomain") ?? MissAVHTML.defaultDomain)) ?? URL(string: MissAVHTML.defaultDomain)!
    }
    func configure(_ input: String) throws {
        let next = try JRPolicy.domain(input)
        guard next != base else { return }
        reset(); cookieStorage = URLSessionConfiguration.ephemeral.httpCookieStorage; base = next
        defaults.set(next.absoluteString, forKey: "missav.baseDomain")
    }
    func reset() {
        sessions.values.forEach { $0.invalidateAndCancel() }; sessions.removeAll()
        routes = MissAVHTML.routes; generation += 1
    }
    func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = protocolClasses
        config.timeoutIntervalForRequest = 25; config.timeoutIntervalForResource = 40
        config.httpShouldSetCookies = true; config.httpCookieStorage = cookieStorage
        config.httpCookieAcceptPolicy = .onlyFromMainDocumentDomain
        config.urlCache = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return config
    }
    private func html(_ path: String) async throws -> String {
        let epoch = generation, origin = base
        guard let url = URL(string: path, relativeTo: origin)?.absoluteURL,
              MissAVHTML.route(path, page: origin, base: origin) != nil else { throw JRError.message("不安全的 MissAV 来源路径") }
        let config = configuration()
        let delegate = JRRedirectPolicy(base: origin, maximum: 4 * 1024 * 1024, responseValidator: MissAVHTML.responseError)
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        let id = UUID(); sessions[id] = session
        defer { session.invalidateAndCancel(); sessions[id] = nil }
        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("zh-TW,zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue(origin.absoluteString + "/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        let data: Data
        do {
            data = try await withTaskCancellationHandler(operation: { try await delegate.download(request, session: session) }, onCancel: { session.invalidateAndCancel() })
        } catch {
            try Task.checkCancellation()
            throw JRError.message("MissAV 原生请求未成功：\(error.localizedDescription)。如遇 HTTP 403 / Cloudflare，请稍后重试或修改来源设置；不会自动导入浏览器验证 Cookie。")
        }
        try Task.checkCancellation()
        guard epoch == generation, let text = String(data: data, encoding: .utf8) else { throw CancellationError() }
        return text
    }
    func page(_ path: String) async throws -> MissAVPage {
        let epoch = generation, origin = base
        let text = try await html(path)
        let worker = Task.detached(priority: .userInitiated) { try MissAVHTML.parse(text, path: path, base: origin) }
        let parsed = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
        try Task.checkCancellation(); guard epoch == generation else { throw CancellationError() }
        routes.merge(parsed.routes) { _, new in new }
        return parsed
    }
    func detail(_ video: JRVideo) async throws -> MissAVDetail {
        let epoch = generation, origin = base
        let text = try await html(video.path)
        let worker = Task.detached(priority: .userInitiated) { try MissAVHTML.detail(text, video: video, base: origin) }
        let parsed = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
        try Task.checkCancellation(); guard epoch == generation else { throw CancellationError() }
        return parsed
    }
}
