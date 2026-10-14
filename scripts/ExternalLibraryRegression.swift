import Foundation

func check(_ condition: Bool) { precondition(condition) }

final class StubTokens: ExternalTokenStore {
    var value: String?
    var failure = false
    func read() throws -> String? {
        if failure { throw ExternalLibraryError.keychain(-50) }
        return value
    }
    func write(_ token: String) throws {
        if failure { throw ExternalLibraryError.keychain(-50) }
        value = token
    }
    func clear() throws {
        if failure { throw ExternalLibraryError.keychain(-50) }
        value = nil
    }
}

final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    static var requests: [URLRequest] = []
    static var status = 200
    static var body = #"{"data":[{"id":1,"download_url":"magnet:?xt=urn:btih:synthetic"}]}"#
    static var pending: FixtureProtocol?
    static var stopped = false
    static var hold = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        if Self.hold { Self.pending = self; return }
        finish()
    }
    func finish() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { Self.stopped = true }
}

@main struct Regression {
    @MainActor static func main() async throws {
        let suite = "external-regression-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = StubTokens()
        let settings = ExternalLibrarySettings(store: store, defaults: defaults)
        let client = ExternalLibraryClient {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [FixtureProtocol.self]
            return config
        }
        defer { client.cancelRequests() }
        check(!settings.enabled && !settings.hasToken)
        let initial = try await client.fetchLinks(for: "SYNTH-001", settings: settings)
        check(initial.isEmpty && FixtureProtocol.requests.isEmpty)
        try settings.save(baseURL: "https://fixture.invalid/", enabled: true, replacementToken: "")
        let missing = try await client.fetchLinks(for: "SYNTH-001", settings: settings)
        check(missing.isEmpty && FixtureProtocol.requests.isEmpty)
        try settings.save(baseURL: settings.baseURL, enabled: true, replacementToken: "synthetic-first")
        let restored = ExternalLibrarySettings(store: store, defaults: defaults)
        check(restored.hasToken && restored.enabled)
        check(try restored.token() == "synthetic-first")
        check(!String(describing: defaults.dictionaryRepresentation()).contains("synthetic-first"))
        let links = try await client.fetchLinks(for: "SYNTH-001", settings: settings)
        check(links.count == 1)
        let sent = FixtureProtocol.requests.last!
        check(sent.value(forHTTPHeaderField: "X-API-Key") == "synthetic-first")
        check(sent.url!.path == "/api/v1/articles/torrents")
        check(URLComponents(url: sent.url!, resolvingAgainstBaseURL: false)!.queryItems == [URLQueryItem(name: "keyword", value: "SYNTH-001")])
        check(!sent.url!.absoluteString.contains("synthetic-first"))
        check(sent.cachePolicy == .reloadIgnoringLocalCacheData)
        try settings.save(baseURL: settings.baseURL, enabled: true, replacementToken: "")
        check(try settings.token() == "synthetic-first")
        for invalid in ["ftp://fixture.invalid", "https://u:p@fixture.invalid", "https://fixture.invalid/path", "https://fixture.invalid?q=1", "https://fixture.invalid#fragment", "https://fixture.invalid:0"] {
            do { _ = try ExternalLibrarySettings.normalizedURL(invalid); fatalError("accepted invalid endpoint") }
            catch ExternalLibraryError.invalidURL { }
        }
        do { try settings.save(baseURL: "https://different.invalid", enabled: true, replacementToken: ""); fatalError("sent old token to new host") }
        catch ExternalLibraryError.endpointNeedsToken { }
        let revision = settings.revision
        store.failure = true
        do { try settings.save(baseURL: settings.baseURL, enabled: false, replacementToken: "synthetic-new"); fatalError("ignored Keychain failure") }
        catch ExternalLibraryError.keychain { }
        check(settings.revision == revision && settings.enabled)
        settings.refreshStatus()
        check(settings.storageError != nil)
        do { _ = try await client.fetchLinks(for: "SYNTH-001", settings: settings); fatalError("ignored read failure") }
        catch ExternalLibraryError.keychain { }
        store.failure = false
        FixtureProtocol.status = 401
        do { _ = try await client.fetchLinks(for: "SYNTH-001", settings: settings); fatalError("swallowed HTTP failure") }
        catch ExternalLibraryError.http(401) { }
        check(await client.links(for: "SYNTH-001", settings: settings).isEmpty)
        check(client.lastError != nil)
        FixtureProtocol.status = 200
        FixtureProtocol.body = #"{"data":null}"#
        do { _ = try await client.fetchLinks(for: "SYNTH-001", settings: settings); fatalError("swallowed schema failure") }
        catch ExternalLibraryError.schema { }
        FixtureProtocol.body = #"{"data":[]}"#
        check(try await client.fetchLinks(for: "SYNTH-001", settings: settings).isEmpty)
        check(await client.links(for: "SYNTH-001", settings: settings).isEmpty)
        check(client.lastError == nil)
        // A response already in flight must not publish after a configuration generation change.
        FixtureProtocol.hold = true
        let stale = Task { try await client.fetchLinks(for: "SYNTH-001", settings: settings) }
        for _ in 0..<200 where FixtureProtocol.pending == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        check(FixtureProtocol.pending != nil)
        try settings.save(baseURL: settings.baseURL, enabled: true, replacementToken: "synthetic-second")
        FixtureProtocol.pending!.finish()
        do { _ = try await stale.value; fatalError("published stale generation") }
        catch is CancellationError { }
        FixtureProtocol.pending = nil
        FixtureProtocol.stopped = false
        let cancelled = Task { try await client.fetchLinks(for: "SYNTH-001", settings: settings) }
        for _ in 0..<200 where FixtureProtocol.pending == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        check(FixtureProtocol.pending != nil)
        client.cancelRequests()
        do { _ = try await cancelled.value; fatalError("did not cancel in-flight request") }
        catch is CancellationError { }
        check(FixtureProtocol.stopped)
        FixtureProtocol.hold = false
        FixtureProtocol.pending = nil
        _ = try await client.fetchLinks(for: "SYNTH-001", settings: settings)
        check(FixtureProtocol.requests.last!.value(forHTTPHeaderField: "X-API-Key") == "synthetic-second")
        let requestCount = FixtureProtocol.requests.count
        try settings.save(baseURL: settings.baseURL, enabled: false, replacementToken: "")
        _ = try await client.fetchLinks(for: "SYNTH-001", settings: settings)
        check(FixtureProtocol.requests.count == requestCount)
        try settings.clearToken()
        check(!settings.hasToken)
        check(try settings.token() == nil)
        try settings.save(baseURL: settings.baseURL, enabled: true, replacementToken: "")
        _ = try await client.fetchLinks(for: "SYNTH-001", settings: settings)
        check(FixtureProtocol.requests.count == requestCount)
        // Execute the shipping delegate directly; neither same-origin nor cross-origin may redirect.
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "https://fixture.invalid")!)
        let response = HTTPURLResponse(url: task.originalRequest!.url!, statusCode: 302, httpVersion: nil, headerFields: nil)!
        for target in ["https://fixture.invalid/elsewhere", "https://other.invalid"] {
            var called = false
            ExternalRedirectBlocker().urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: URL(string: target)!)) { request in
                check(request == nil)
                called = true
            }
            check(called)
        }
        print("PASS external token lifecycle, stub Keychain failure, header, no-key/no-source, errors, generation isolation, cancellation, redirect rejection")
    }
}
