import Foundation

/// Follows only the official self-declaration link read from the site's age page.
/// Cookies originate exclusively in Set-Cookie, remain in memory, and never enter AVDB/115.
actor DMMTransport {
    private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    private let session: URLSession
    private let delegate = NoRedirect()
    private var cookies: [HTTPCookie] = []
    private var generation = UUID()
    init(session supplied: URLSession? = nil) {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil; c.httpShouldSetCookies = false
        c.timeoutIntervalForRequest = 20
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = supplied ?? URLSession(configuration: c)
    }
    static func allowed(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        if url.host == "video.dmm.co.jp" {
            if c.path == "/av/ranking/" { return c.queryItems == [URLQueryItem(name: "term", value: "weekly")] }
            if c.path == "/av/content/", let q = c.queryItems, q.count == 1, q[0].name == "id", let id = q[0].value {
                return id.count <= 100 && id.range(of: "^[a-z0-9_]+$", options: .regularExpression) != nil
            }
        }
        if url.host == "www.dmm.co.jp", ["/age_check/=/", "/age_check/=/declared=yes/"].contains(c.path),
           let q = c.queryItems, q.count == 1, q[0].name == "rurl", let raw = q[0].value, let target = URL(string: raw), target.host == "video.dmm.co.jp" {
            return allowed(target)
        }
        return false
    }
    static func declaration(html: String, ageURL: URL) throws -> URL {
        guard ageURL.host == "www.dmm.co.jp", allowed(ageURL), html.contains("18歳以上") else { throw DMMRankingError.accessGate }
        let re = try NSRegularExpression(pattern: "<script id=\"__NEXT_DATA__\" type=\"application/json\">(.*?)</script>", options: [.dotMatchesLineSeparators])
        let ns = html as NSString
        guard let m = re.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
              let data = ns.substring(with: m.range(at: 1)).data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let props = object["props"] as? [String: Any], let page = props["pageProps"] as? [String: Any],
              let link = page["yesButtonLink"] as? String, let url = URL(string: link), allowed(url),
              URLComponents(url: url, resolvingAgainstBaseURL: false)?.path == "/age_check/=/declared=yes/",
              URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == URLComponents(url: ageURL, resolvingAgainstBaseURL: false)?.queryItems else { throw DMMRankingError.accessGate }
        return url
    }
    func clear() { generation = UUID(); cookies.removeAll() }
    func document(_ source: URL, authorizeAdultDeclaration: Bool) async throws -> (String, URL) {
        let epoch = generation
        var url = source, declared = false
        for _ in 0..<8 {
            try Task.checkCancellation()
            guard Self.allowed(url) else { throw DMMRankingError.accessGate }
            var request = URLRequest(url: url)
            let now = Date()
            cookies.removeAll { ($0.expiresDate ?? .distantFuture) < now }
            let applicable = cookies.filter {
                let domain = $0.domain.hasPrefix(".") ? String($0.domain.dropFirst()) : $0.domain
                return (url.host == domain || ($0.domain.hasPrefix(".") && url.host?.hasSuffix("." + domain) == true)) && url.path.hasPrefix($0.path) && (!$0.isSecure || url.scheme == "https")
            }
            if !applicable.isEmpty { request.allHTTPHeaderFields = HTTPCookie.requestHeaderFields(with: applicable) }
            let (data, response) = try await session.data(for: request, delegate: delegate)
            try Task.checkCancellation()
            guard epoch == generation else { throw CancellationError() }
            guard let http = response as? HTTPURLResponse, data.count <= 8_000_000 else { throw DMMRankingError.malformed }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields { if let key = key as? String, let value = value as? String { headers[key] = value } }
            for item in HTTPCookie.cookies(withResponseHeaderFields: headers, for: url) {
                let domain = item.domain.hasPrefix(".") ? String(item.domain.dropFirst()) : item.domain
                guard ["dmm.co.jp", "www.dmm.co.jp", "video.dmm.co.jp"].contains(domain), url.host == domain || url.host?.hasSuffix("." + domain) == true else { continue }
                cookies.removeAll { $0.name == item.name && $0.domain == item.domain && $0.path == item.path }; cookies.append(item)
            }
            if (300..<400).contains(http.statusCode), let location = http.value(forHTTPHeaderField: "Location"), let next = URL(string: location, relativeTo: url)?.absoluteURL {
                guard Self.allowed(next) else { throw DMMRankingError.accessGate }
                url = next; continue
            }
            guard http.statusCode == 200, let html = String(data: data, encoding: .utf8) else { throw DMMRankingError.accessGate }
            if url.host == "www.dmm.co.jp" {
                guard authorizeAdultDeclaration, !declared else { throw DMMRankingError.accessGate }
                url = try Self.declaration(html: html, ageURL: url); declared = true; continue
            }
            return (html, url)
        }
        throw DMMRankingError.accessGate
    }
}
