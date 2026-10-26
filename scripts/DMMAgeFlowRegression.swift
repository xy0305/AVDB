import Foundation

final class DMMAgeMock: URLProtocol, @unchecked Sendable {
    static var mode = "ok"
    static var paths: [String] = []
    static var cookiesSeen = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let url = request.url!
        let path = URLComponents(url: url, resolvingAgainstBaseURL: false)!.path
        Self.paths.append(path)
        precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
        precondition(request.value(forHTTPHeaderField: "X-115-Token") == nil)
        let returnURL = "https%3A%2F%2Fvideo.dmm.co.jp%2Fav%2Franking%2F%3Fterm%3Dweekly"
        let age = "https://www.dmm.co.jp/age_check/=/?rurl=" + returnURL
        let yes = "https://www.dmm.co.jp/age_check/=/declared=yes/?rurl=" + returnURL
        var status = 200, headers: [String: String] = [:], body = ""
        if Self.mode == "cross" { status = 302; headers["Location"] = "https://accounts.dmm.co.jp/login/" }
        else if Self.mode == "loop" { status = 302; headers["Location"] = url.absoluteString }
        else if path == "/age_check/=/declared=yes/" {
            status = 302; headers = ["Location": "https://video.dmm.co.jp/av/ranking/?term=weekly", "Set-Cookie": "age_checked=yes; Domain=.dmm.co.jp; Path=/; Secure; HttpOnly; Max-Age=60"]
        } else if url.host == "www.dmm.co.jp" {
            body = "18歳以上<script id=\"__NEXT_DATA__\" type=\"application/json\">{\"props\":{\"pageProps\":{\"yesButtonLink\":\"\(yes)\"}}}</script>"
        } else if request.value(forHTTPHeaderField: "Cookie")?.contains("age_checked=yes") == true {
            Self.cookiesSeen = true; body = "weekly-document"
        } else { status = 302; headers["Location"] = age }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
}
@main struct DMMAgeFlowRegression {
    static func main() async throws {
        let weekly = URL(string: "https://video.dmm.co.jp/av/ranking/?term=weekly")!
        let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [DMMAgeMock.self]
        let transport = DMMTransport(session: URLSession(configuration: c))
        do { _ = try await transport.document(weekly, authorizeAdultDeclaration: false); preconditionFailure() } catch {}
        precondition(!DMMAgeMock.paths.contains("/age_check/=/declared=yes/"))
        DMMAgeMock.paths = []
        let result = try await transport.document(weekly, authorizeAdultDeclaration: true)
        precondition(result.0 == "weekly-document" && DMMAgeMock.cookiesSeen)
        precondition(DMMAgeMock.paths.count == 4)
        DMMAgeMock.paths = []
        _ = try await transport.document(weekly, authorizeAdultDeclaration: true)
        precondition(DMMAgeMock.paths.count == 1)
        await transport.clear(); DMMAgeMock.paths = []
        do { _ = try await transport.document(weekly, authorizeAdultDeclaration: false); preconditionFailure() } catch {}
        precondition(!DMMAgeMock.paths.contains("/age_check/=/declared=yes/"))
        for mode in ["cross", "loop"] {
            DMMAgeMock.mode = mode; DMMAgeMock.paths = []
            do { _ = try await transport.document(weekly, authorizeAdultDeclaration: true); preconditionFailure() } catch {}
            precondition(DMMAgeMock.paths.count <= 8)
            precondition(!DMMAgeMock.paths.contains("/login/"))
        }
        print("PASS official GET self-declaration runtime: consent, Set-Cookie, reuse, revocation, bounded redirects, cross-host rejection, no credentials")
    }
}
