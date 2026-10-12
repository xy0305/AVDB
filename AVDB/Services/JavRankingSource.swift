import Foundation
import Combine

final class JRRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let base: URL
    init(base: URL) { self.base = base }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map { JRPolicy.sameHost($0, base: base) } == true ? request : nil)
    }
}

@MainActor final class JavRankingSource: ObservableObject {
    static let shared = JavRankingSource()
    @Published private(set) var generation = 0
    @Published private(set) var base: URL
    private var session: URLSession
    private var pages: [String: JRPage] = [:]
    private var indexes: [String: JRIndex] = [:]
    init(defaults: UserDefaults = .standard) {
        let base = (try? JRPolicy.domain(defaults.string(forKey: "javranking.baseDomain") ?? JRPolicy.defaultDomain)) ?? URL(string: JRPolicy.defaultDomain)!
        self.base = base; session = Self.makeSession(base)
    }
    private static func makeSession(_ base: URL) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25; config.timeoutIntervalForResource = 45
        config.httpMaximumConnectionsPerHost = 3
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil; config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: JRRedirectPolicy(base: base), delegateQueue: nil)
    }
    func configure(_ input: String, defaults: UserDefaults = .standard) throws {
        let next = try JRPolicy.domain(input)
        guard next != base else { return }
        // Synchronous main-actor transaction. Old tasks are cancelled, caches and UI
        // identities are replaced before a new request can publish anything.
        session.invalidateAndCancel(); pages.removeAll(); indexes.removeAll()
        base = next; session = Self.makeSession(next)
        defaults.set(next.absoluteString, forKey: "javranking.baseDomain")
        generation += 1
    }
    func resetCache() {
        session.invalidateAndCancel(); session = Self.makeSession(base)
        pages.removeAll(); indexes.removeAll(); generation += 1
    }
    private func data(_ path: String) async throws -> Data {
        let epoch = generation
        guard let url = URL(string: path, relativeTo: base)?.absoluteURL, JRPolicy.sameHost(url, base: base) else { throw JRError.message("不安全的来源地址") }
        var request = URLRequest(url: url)
        request.setValue("text/html,application/json", forHTTPHeaderField: "Accept")
        request.setValue("AVDB-readonly", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let final = response.url, JRPolicy.sameHost(final, base: base) else {
            throw JRError.message("站点访问受限或请求失败（HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)），请稍后手动重试。")
        }
        guard response.expectedContentLength <= 12 * 1024 * 1024 else { throw JRError.message("公开页面超出安全大小限制") }
        var result = Data(); result.reserveCapacity(max(0, min(Int(response.expectedContentLength), 12 * 1024 * 1024)))
        for try await byte in bytes {
            result.append(byte)
            if result.count > 12 * 1024 * 1024 { throw JRError.message("公开页面超出安全大小限制") }
            if result.count % 16384 == 0 { try Task.checkCancellation(); guard epoch == generation else { throw CancellationError() } }
        }
        try Task.checkCancellation(); guard epoch == generation else { throw CancellationError() }; return result
    }
    func page(_ path: String) async throws -> JRPage {
        if let cached = pages[path] { return cached }
        let epoch = generation, origin = base
        if let route = URLComponents(string: path), route.path == "/zh-hans/explore/",
           (route.queryItems ?? []).allSatisfy({ $0.name == "page" }) {
            let number = route.queryItems?.first(where: { $0.name == "page" })?.value.flatMap(Int.init) ?? 1
            let catalog = try await index(search: false)
            let parsed = try catalog.explorePage(number: number)
            try Task.checkCancellation(); guard epoch == generation else { throw CancellationError() }
            if pages.count >= 16 { pages.removeAll() }
            pages[path] = parsed; return parsed
        }
        let data = try await data(path)
        guard let html = String(data: data, encoding: .utf8) else { throw JRError.message("无法解码公开页面") }
        let parsed = try await Task.detached(priority: .userInitiated) { try JRHTML.parse(html, path: path, base: origin) }.value
        try Task.checkCancellation(); guard epoch == generation else { throw CancellationError() }
        if pages.count >= 16 { pages.removeAll() }
        pages[path] = parsed; return parsed
    }
    func index(search: Bool) async throws -> JRIndex {
        let path = search ? "/zh-hans/search-index.json" : "/zh-hans/filter-index.json"
        if let cached = indexes[path] { return cached }
        let epoch = generation, origin = base, data = try await data(path)
        let parsed = try await Task.detached(priority: .userInitiated) { try JRIndex.parse(data, base: origin) }.value
        try Task.checkCancellation(); guard epoch == generation else { throw CancellationError() }
        indexes[path] = parsed; return parsed
    }
}
