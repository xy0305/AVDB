import Foundation
import Combine

final class JRRedirectPolicy: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct Transfer {
        var data = Data()
        var response: HTTPURLResponse?
        let continuation: CheckedContinuation<Data, Error>
    }
    private let lock = NSLock()
    private var transfers: [Int: Transfer] = [:]
    private let maximum: Int
    private let responseValidator: ((HTTPURLResponse, Data) -> Error?)?
    private let rejectRedirects: Bool
    private let exactOrigin: Bool
    let base: URL
    init(base: URL, maximum: Int = 12 * 1024 * 1024, rejectRedirects: Bool = false, exactOrigin: Bool = false, responseValidator: ((HTTPURLResponse, Data) -> Error?)? = nil) {
        self.base = base; self.maximum = maximum; self.responseValidator = responseValidator; self.rejectRedirects = rejectRedirects; self.exactOrigin = exactOrigin
    }
    private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var task: URLSessionTask?
        private var cancelled = false
        func attach(_ task: URLSessionTask) {
            lock.lock(); self.task = task; let stop = cancelled; lock.unlock()
            if stop { task.cancel() }
        }
        func cancel() {
            lock.lock(); cancelled = true; let current = task; lock.unlock()
            current?.cancel()
        }
    }
    func download(_ request: URLRequest, session: URLSession) async throws -> Data {
        let cancellation = Cancellation()
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request)
                lock.lock()
                transfers[task.taskIdentifier] = Transfer(continuation: continuation)
                lock.unlock()
                cancellation.attach(task)
                task.resume()
            }
        }, onCancel: { cancellation.cancel() })
    }
    private func finish(_ task: URLSessionTask, error: Error?) {
        lock.lock()
        let transfer = transfers.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        guard let transfer else { return }
        let validation = transfer.response.flatMap { responseValidator?($0, transfer.data) }
        if let error = error ?? validation { transfer.continuation.resume(throwing: error) }
        else { transfer.continuation.resume(returning: transfer.data) }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse,
              responseValidator != nil || (200..<300).contains(http.statusCode),
              let url = response.url, (exactOrigin ? JRBackendPolicy.sameOrigin(url, base) && url == dataTask.originalRequest?.url : JRPolicy.sameHost(url, base: base)), response.expectedContentLength <= maximum else {
            finish(dataTask, error: JRError.message("来源请求失败或超过安全大小限制（HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)）"))
            completionHandler(.cancel); return
        }
        lock.lock(); transfers[dataTask.taskIdentifier]?.response = http; lock.unlock()
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
        completionHandler(!rejectRedirects && request.url.map { JRPolicy.sameHost($0, base: base) } == true ? request : nil)
    }
}

@MainActor final class JavRankingSource: ObservableObject {
    static let shared = JavRankingSource()
    @Published private(set) var generation = 0
    @Published private(set) var previews: [String: JRPage] = [:]
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
    private var matchAccount: String?
    private func updateMatchScope() {
        let account = APIClient.shared.token
        if account != matchAccount {
            cancelMappings(); matches.removeAll(); matchAccount = account
        }
    }
    func cachedMovie(code: String) -> Movie? {
        updateMatchScope()
        guard !JavDBSDK.shared.hasAmbiguousMovie(code: code) else { return nil }
        if let native = JavDBSDK.shared.cachedExactMovie(code: code) { return native }
        guard let key = JRPolicy.exactCode(code), let cached = matches[key],
              Date().timeIntervalSince(cached.date) < 21600 else { return nil }
        return cached.movie
    }
    func cancelMappings() {
        matchFlights.values.forEach { $0.cancel() }; matchFlights.removeAll(); matchTokens.removeAll()
    }
    func matchedMovie(code: String, refresh: Bool = false, interactive: Bool = false) async throws -> Movie? {
        updateMatchScope()
        guard let key = JRPolicy.exactCode(code) else { return nil }
        if JavDBSDK.shared.hasAmbiguousMovie(code: code) { throw JRError.message("同一番号对应多个有效影片 ID，请在原生搜索中核对。") }
        if !refresh, let native = JavDBSDK.shared.cachedExactMovie(code: code) { return native }
        if !refresh, let cached = matches[key], Date().timeIntervalSince(cached.date) < (cached.movie == nil ? 60 : 21600) { return cached.movie }
        if let flight = matchFlights[key] { return try await flight.value }
        let epoch = generation, token = UUID(), account = matchAccount
        let flight = Task<Movie?, Error>(priority: interactive ? .userInitiated : .utility) {
            let deadline = Date().addingTimeInterval(12)
            while !interactive && self.activeMatches >= 3 {
                guard Date() < deadline else { throw JRError.message("核验队列繁忙，请重试") }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            try Task.checkCancellation()
            self.activeMatches += 1
            defer { self.activeMatches -= 1 }
            let movie = try await withThrowingTaskGroup(of: Movie?.self) { group in
                group.addTask { try await JavDBSDK.shared.exactMovie(code: code, refresh: refresh) }
                group.addTask {
                    try await Task.sleep(nanoseconds: 12_000_000_000)
                    throw JRError.message("核验超时，请重试或使用原生搜索")
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
            try Task.checkCancellation()
            guard epoch == self.generation, account == APIClient.shared.token else { throw CancellationError() }
            if self.matches.count >= 256, let oldest = self.matches.min(by: { $0.value.date < $1.value.date })?.key { self.matches[oldest] = nil }
            // Do not retain misses: a retry must reach the native backend again.
            if let movie { self.matches[key] = Match(movie: movie, date: Date()) }
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
        cancelMappings(); matches.removeAll(); previews.removeAll()
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
        let first = Task.detached(priority: .userInitiated) { () throws -> (String, JRPage?) in
            try Task.checkCancellation()
            guard let html = String(data: data, encoding: .utf8) else { throw JRError.message("无法解码公开页面") }
            return (html, try JRHTML.firstCards(html, path: path, base: origin))
        }
        let (html, preview) = try await withTaskCancellationHandler(operation: { try await first.value }, onCancel: { first.cancel() })
        try Task.checkCancellation(); guard epoch == generation else { throw CancellationError() }
        if let preview { previews[path] = preview }
        defer { if epoch == generation { previews[path] = nil } }
        let worker = Task.detached(priority: .userInitiated) { try JRHTML.parse(html, path: path, base: origin) }
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
            let worker = Task.detached(priority: .userInitiated) { try JRIndex.parse(data, base: origin) }
            let parsed = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            try Task.checkCancellation(); guard epoch == self.generation else { throw CancellationError() }
            self.indexes[path] = parsed; self.indexDates[path] = Date(); return parsed
        }
        indexFlights[path] = flight
        defer { if epoch == generation { indexFlights[path] = nil } }
        return try await flight.value
    }
}

@MainActor final class JRBackendClient: ObservableObject {
    static let shared = JRBackendClient()
    @Published private(set) var endpoint: URL?
    @Published private(set) var generation = 0
    @Published private(set) var externalMode: Bool
    private var session: URLSession?
    private let protocolClasses: [AnyClass]?
    private let settings: ExternalLibrarySettings
    private var observation: AnyCancellable?
    private var accountObservation: AnyCancellable?
    init(defaults: UserDefaults = .standard, protocolClasses: [AnyClass]? = nil, settings: ExternalLibrarySettings? = nil) {
        self.protocolClasses = protocolClasses
        self.settings = settings ?? .shared
        externalMode = defaults.object(forKey: "javranking.externalMode") as? Bool ?? true
        endpoint = externalMode ? nil : (try? JRBackendPolicy.endpoint(defaults.string(forKey: "javranking.backendHTTPS") ?? ""))
        if externalMode { updateExternal() } else { rebuild() }
        accountObservation = NotificationCenter.default.publisher(for: Notification.Name("avdb.catalog.accountChanged")).sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.session?.invalidateAndCancel(); self.endpoint = nil; self.generation += 1
                JavRankingSource.shared.cancelMappings()
                if self.externalMode { self.updateExternal() }
                else { self.endpoint = try? JRBackendPolicy.endpoint(defaults.string(forKey: "javranking.backendHTTPS") ?? ""); self.rebuild() }
            }
        }
        observation = self.settings.$revision.dropFirst().sink { [weak self] _ in
            // @Published fires before revision assignment; defer to the completed settings transaction.
            Task { @MainActor [weak self] in self?.externalChanged() }
        }
    }
    private func externalChanged() {
        guard externalMode else { return }
        endpoint = nil; rebuild(); generation += 1
        JavRankingSource.shared.cancelMappings()
        updateExternal()
    }
    private func updateExternal() {
        endpoint = nil
        if settings.enabled, settings.hasToken,
           let root = try? ExternalLibrarySettings.normalizedURL(settings.baseURL), let origin = URL(string: root) {
            endpoint = try? JRBackendPolicy.externalEndpoint(origin)
        }
        rebuild()
    }
    private func rebuild() {
        session?.invalidateAndCancel(); session = nil
        guard let endpoint else { return }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = protocolClasses
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil; config.urlCache = nil
        config.urlCredentialStorage = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 30
        config.httpMaximumConnectionsPerHost = 3
        let policy = JRRedirectPolicy(base: endpoint, maximum: 8 * 1024 * 1024, rejectRedirects: true, exactOrigin: true) { response, _ in
            guard let url = response.url, JRBackendPolicy.sameOrigin(url, endpoint),
                  url.path.hasPrefix(JRBackendPolicy.prefix + "/") else { return JRError.message("缓存响应不属于配置的同源 API") }
            guard response.statusCode == 200 || response.statusCode == 202 else {
                return JRError.message("缓存服务 HTTP \(response.statusCode)；保留上次显示结果，可稍后重试。")
            }
            guard response.mimeType == "application/json" else { return JRError.message("缓存服务未返回 JSON") }
            return nil
        }
        session = URLSession(configuration: config, delegate: policy, delegateQueue: nil)
    }
    func useExternalLibrary(defaults: UserDefaults = .standard) {
        externalMode = true; defaults.set(true, forKey: "javranking.externalMode")
        externalChanged()
    }
    func configure(_ input: String, defaults: UserDefaults = .standard) throws {
        let next = try JRBackendPolicy.endpoint(input)
        externalMode = false; defaults.set(false, forKey: "javranking.externalMode")
        endpoint = next; rebuild(); generation += 1
        JavRankingSource.shared.cancelMappings()
        defaults.set(next?.absoluteString ?? "", forKey: "javranking.backendHTTPS")
    }
    func fetch(_ route: String, query: [URLQueryItem] = []) async throws -> JRBackendEnvelope {
        let revision = settings.revision
        // Revalidate settings and read Keychain for EVERY request. No token in stored endpoints.
        var request: URLRequest
        if externalMode {
            guard settings.enabled, let token = try settings.token(), !token.isEmpty else { throw ExternalLibraryError.rankingNotConfigured }
            let root = try ExternalLibrarySettings.normalizedURL(settings.baseURL)
            guard let origin = URL(string: root) else { throw ExternalLibraryError.invalidURL }
            let effective = try JRBackendPolicy.externalEndpoint(origin)
            if effective != endpoint { endpoint = effective; rebuild(); generation += 1 }
            request = try JRBackendPolicy.authenticatedRequest(base: effective, origin: origin, token: token, route: route, query: query)
        } else {
            guard let endpoint else { throw JRError.message("独立 HTTPS 后端尚未配置；可切换为复用外部数据库。") }
            request = URLRequest(url: try JRBackendPolicy.request(base: endpoint, route: route, query: query))
        }
        guard let session else { throw ExternalLibraryError.rankingNotConfigured }
        let epoch = generation
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AVDB-readonly", forHTTPHeaderField: "User-Agent")
        let bytes = try await (session.delegate as! JRRedirectPolicy).download(request, session: session)
        try Task.checkCancellation()
        guard epoch == generation, !externalMode || revision == settings.revision else { throw CancellationError() }
        return try JRBackendEnvelope.decode(bytes)
    }
}
