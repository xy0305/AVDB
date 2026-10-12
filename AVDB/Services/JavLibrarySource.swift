import Foundation
import Combine

// Isolated ephemeral transport: no shared JavDB/115 cookie store or authorization.
final class JLRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let host: String
    init(host: String) { self.host = host }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" && request.url?.host == host ? request : nil)
    }
}
@MainActor final class JavLibrarySource: ObservableObject {
    @Published private(set) var base: URL
    @Published private(set) var generation = 0
    private var session: URLSession
    private var guardDelegate: JLRedirectGuard
    private var cookies: [HTTPCookie] = [] // memory only, discarded on domain change/app termination
    init() {
        let base = (try? JLPolicy.domain(UserDefaults.standard.string(forKey: "javlibrary.domain") ?? "")) ?? JLPolicy.canonical
        self.base = base
        let delegate = JLRedirectGuard(host: base.host!)
        guardDelegate = delegate
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 35
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }
    func configure(_ raw: String) throws {
        let domain = try JLPolicy.domain(raw)
        session.invalidateAndCancel()
        base = domain; cookies = []; generation += 1
        UserDefaults.standard.set(domain.absoluteString, forKey: "javlibrary.domain")
        guardDelegate = JLRedirectGuard(host: domain.host!)
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 25; config.timeoutIntervalForResource = 35
        session = URLSession(configuration: config, delegate: guardDelegate, delegateQueue: nil)
    }
    func acceptVerifiedCookies(_ input: [HTTPCookie], host: String) {
        guard host == base.host else { return }
        cookies = input.filter { $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased() == host.lowercased() && $0.isSecure && ($0.expiresDate ?? .distantFuture) > Date() }
    }
    func load(_ url: URL) async throws -> JLPage {
        guard url.host == base.host, url.scheme == "https", url.path.hasPrefix("/cn/") else { throw JLError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let validCookies = cookies.filter { ($0.expiresDate ?? .distantFuture) > Date() && url.path.hasPrefix($0.path) }
        for (key, value) in HTTPCookie.requestHeaderFields(with: validCookies) { request.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, response.url?.host == base.host else { throw JLError.invalidURL }
        let html = try JLPolicy.validate(data, response: http)
        return try JLHTML.parse(html, pageURL: url)
    }
}
