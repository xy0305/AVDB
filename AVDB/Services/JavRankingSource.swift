import Foundation
import Combine

final class JRRedirectPolicy: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct Transfer {
        var data = Data()
        let continuation: CheckedContinuation<Data, Error>
    }
    private let lock = NSLock()
    private var transfers: [Int: Transfer] = [:]
    private let maximum = 12 * 1024 * 1024
    let base: URL
    init(base: URL) { self.base = base }
    func download(_ request: URLRequest, session: URLSession) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request)
            lock.lock()
            transfers[task.taskIdentifier] = Transfer(continuation: continuation)
            lock.unlock()
            task.resume()
        }
    }
    private func finish(_ task: URLSessionTask, error: Error?) {
        lock.lock()
        let transfer = transfers.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        guard let transfer else { return }
        if let error { transfer.continuation.resume(throwing: error) }
        else { transfer.continuation.resume(returning: transfer.data) }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let url = response.url, JRPolicy.sameHost(url, base: base), response.expectedContentLength <= maximum else {
            finish(dataTask, error: JRError.message("来源请求失败或超过安全大小限制（HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)）"))
            completionHandler(.cancel); return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let oversized = (transfers[dataTask.taskIdentifier]?.data.count ?? 0) + data.count > maximum
        if !oversized { transfers[dataTask.taskIdentifier]?.data.append(data) }
        lock.unlock()
        if oversized {
            finish(dataTask, error: JRError.message("公开页面超出安全大小限制"))
            dataTask.cancel()
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(task, error: error)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map { JRPolicy.sameHost($0, base: base) } == true ? request : nil)
    }
}

@MainActor final class JavRankingSource: ObservableObject {
    static let shared = JavRankingSource()
    @Published private(set) var generation = 0
    @Published private(set) var base: URL
    private var session: URLSession
    private let protocolClasses: [AnyClass]?
    private var pages: [String: JRPage] = [:]
    private var indexes: [String: JRIndex] = [:]
    private struct Match { let movie: Movie?; let date: Date }
    private var matches: [String: Match] = [:]
    private var matchFlights: [String: Task<Movie?, Error>] = [:]
    private var matchTokens: [String: UUID] = [:]
    private var activeMatches = 0
    func cancelMappings() {
        matchFlights.values.forEach { $0.cancel() }; matchFlights.removeAll(); matchTokens.removeAll()
    }
    func matchedMovie(code: String) async throws -> Movie? {
        guard let key = JRPolicy.exactCode(code) else { return nil }
        if let cached = matches[key], Date().timeIntervalSince(cached.date) < (cached.movie == nil ? 60 : 21600) { return cached.movie }
        if let flight = matchFlights[key] { return try await flight.value }
        let epoch = generation, token = UUID()
        let flight = Task<Movie?, Error> {
            while self.activeMatches >= 3 { try await Task.sleep(nanoseconds: 50_000_000) }
            try Task.checkCancellation()
            self.activeMatches += 1
            defer { self.activeMatches -= 1 }
            let results = try await JavDBSDK.shared.search(keyword: code, type: "code", limit: 20)
            try Task.checkCancellation(); guard epoch == self.generation else { throw CancellationError() }
            let exact = results.filter { JRPolicy.exactCode($0.number ?? "") == key }
            let unique = Dictionary(exact.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let movie = unique.count == 1 ? unique.values.first : nil
            if self.matches.count >= 256, let oldest = self.matches.min(by: { $0.value.date < $1.value.date })?.key { self.matches[oldest] = nil }
            self.matches[key] = Match(movie: movie, date: Date())
            return movie
        }
        matchFlights[key] = flight; matchTokens[key] = token
        defer { if epoch == generation, matchTokens[key] == token { matchFlights[key] = nil; matchTokens[key] = nil } }
        return try await flight.value
    }
    private var pageDates: [String: Date] = [:]
    private var indexDates: [String: Date] = [:]
    private var pageFlights: [String: Task<JRPage, Error>] = [:]
    private var indexFlights: [String: Task<JRIndex, Error>] = [:]
    private func clear() {
        cancelMappings(); matches.removeAll()
        pageFlights.values.forEach { $0.cancel() }; indexFlights.values.forEach { $0.cancel() }
        pageFlights.removeAll(); indexFlights.removeAll()
        pages.removeAll(); indexes.removeAll(); pageDates.removeAll(); indexDates.removeAll()
    }
    func cachedPage(_ path: String) -> JRPage? { pages[path] }
    func cachedIndex(search: Bool) -> JRIndex? { indexes[search ? "/zh-hans/search-index.json" : "/zh-hans/filter-index.json"] }
    init(defaults: UserDefaults = .standard, protocolClasses: [AnyClass]? = nil) {
        let base = (try? JRPolicy.domain(defaults.string(forKey: "javranking.baseDomain") ?? JRPolicy.defaultDomain)) ?? URL(string: JRPolicy.defaultDomain)!
        self.base = base; self.protocolClasses = protocolClasses; session = Self.makeSession(base, protocols: protocolClasses)
    }
    private static func makeSession(_ base: URL, protocols: [AnyClass]?) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = protocols
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
        session.invalidateAndCancel(); clear()
        base = next; session = Self.makeSession(next, protocols: protocolClasses)
        defaults.set(next.absoluteString, forKey: "javranking.baseDomain")
        generation += 1
    }
    func resetCache() {
        session.invalidateAndCancel(); session = Self.makeSession(base, protocols: protocolClasses)
        clear(); generation += 1
    }
    private func data(_ path: String) async throws -> Data {
        let epoch = generation
        guard let url = URL(string: path, relativeTo: base)?.absoluteURL, JRPolicy.sameHost(url, base: base) else { throw JRError.message("不安全的来源地址") }
        var request = URLRequest(url: url)
        request.setValue("text/html,application/json", forHTTPHeaderField: "Accept")
        request.setValue("AVDB-readonly", forHTTPHeaderField: "User-Agent")
        // URLSession negotiates gzip/br automatically. Delegate callbacks append
        // bounded chunks on its background queue, never one MainActor hop/byte.
        let result = try await (session.delegate as! JRRedirectPolicy).download(request, session: session)
        try Task.checkCancellation(); guard epoch == generation else { throw CancellationError() }; return result
    }
    func page(_ path: String, refresh: Bool = false) async throws -> JRPage {
        if !refresh, let cached = pages[path], Date().timeIntervalSince(pageDates[path] ?? .distantPast) < 300 { return cached }
        if let flight = pageFlights[path] { return try await flight.value }
        let epoch = generation
        let flight = Task { try await self.fetchPage(path) }
        pageFlights[path] = flight
        defer { if epoch == generation { pageFlights[path] = nil } }
        return try await flight.value
    }
    private func fetchPage(_ path: String) async throws -> JRPage {
        let epoch = generation, origin = base
        // Page one is real HTML: no multi-megabyte index on the first display.
        // The site ignores page=N in its static shell, so only later pages use
        // the published catalog for correct native pagination.
        if let route = URLComponents(string: path), route.path == "/zh-hans/explore/",
           (route.queryItems ?? []).allSatisfy({ $0.name == "page" }),
           let number = route.queryItems?.first(where: { $0.name == "page" })?.value.flatMap(Int.init), number > 1 {
            let catalog = try await index(search: false)
            let parsed = try catalog.explorePage(number: number)
            try Task.checkCancellation(); guard epoch == generation else { throw CancellationError() }
            store(parsed, path: path); return parsed
        }
        let data = try await data(path)
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard let html = String(data: data, encoding: .utf8) else { throw JRError.message("无法解码公开页面") }
            return try JRHTML.parse(html, path: path, base: origin)
        }
        let parsed = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
        try Task.checkCancellation(); guard epoch == generation else { throw CancellationError() }
        store(parsed, path: path); return parsed
    }
    private func store(_ page: JRPage, path: String) {
        if pages[path] == nil, pages.count >= 16, let oldest = pageDates.min(by: { $0.value < $1.value })?.key {
            pages[oldest] = nil; pageDates[oldest] = nil
        }
        pages[path] = page; pageDates[path] = Date()
    }
    func index(search: Bool, refresh: Bool = false) async throws -> JRIndex {
        let path = search ? "/zh-hans/search-index.json" : "/zh-hans/filter-index.json"
        if !refresh, let cached = indexes[path], Date().timeIntervalSince(indexDates[path] ?? .distantPast) < 1800 { return cached }
        if let flight = indexFlights[path] { return try await flight.value }
        let epoch = generation, origin = base
        let flight = Task {
            let data = try await self.data(path)
            let parsed = try await Task.detached(priority: .userInitiated) { try JRIndex.parse(data, base: origin) }.value
            try Task.checkCancellation(); guard epoch == self.generation else { throw CancellationError() }
            self.indexes[path] = parsed; self.indexDates[path] = Date(); return parsed
        }
        indexFlights[path] = flight
        defer { if epoch == generation { indexFlights[path] = nil } }
        return try await flight.value
    }
}
