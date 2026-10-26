import Foundation

final class DMMMockProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    static var active = 0, peak = 0, calls = 0
    private var ended = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.active += 1; Self.calls += 1; Self.peak = max(Self.peak, Self.active); Self.lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.03) { [self] in
            Self.lock.lock()
            guard !ended else { Self.lock.unlock(); return }
            ended = true; Self.active -= 1; Self.lock.unlock()
            let url = request.url!
            let cid = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first!.value!
            let body = "<tr><th>配信品番</th><td>\(cid)</td></tr><tr><th>メーカー品番</th><td>TEST-001</td></tr>"
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [:])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {
        Self.lock.lock(); if !ended { ended = true; Self.active -= 1 }; Self.lock.unlock()
    }
}
@main struct DMMStoreRegression {
    @MainActor static func main() async throws {
        let base = URL(fileURLWithPath: CommandLine.arguments[1])
        let weekly = try Data(contentsOf: base.appendingPathComponent("weekly-neutral.html"))
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [DMMMockProtocol.self]
        let transport = DMMTransport(session: URLSession(configuration: config))
        let store = DMMRankingStore(transport: transport)
        try store.importHTML(weekly)
        precondition(store.imported && store.board?.rows.count == 100)
        let rows = store.board!.rows
        for row in rows.prefix(12) { store.request(row); store.request(row) }
        for _ in 0..<100 where store.evidence.count < 12 { try await Task.sleep(nanoseconds: 20_000_000) }
        precondition(store.evidence.count == 12)
        precondition(DMMMockProtocol.peak <= 2 && DMMMockProtocol.calls == 12)
        // Imported new snapshot resets UI evidence, but public successful CID metadata cache is reusable.
        try store.importHTML(weekly); store.request(rows[0]); precondition(store.evidence[rows[0].cid] != nil)
        precondition(DMMMockProtocol.calls == 12)
        // Cancel generation: no late evidence may reappear.
        try store.importHTML(weekly); store.request(rows[20]); store.request(rows[21]); store.cancel()
        try await Task.sleep(nanoseconds: 150_000_000)
        precondition(store.evidence.isEmpty)
        let cid = "snos00489"
        let detail = try String(contentsOf: base.appendingPathComponent("detail-\(cid).html"), encoding: .utf8)
        let canonical = "<link rel=\"canonical\" href=\"https://video.dmm.co.jp/av/content/?id=\(cid)\">"
        if rows.contains(where: { $0.cid == cid }) {
            try store.importHTML(Data((canonical + detail).utf8)); precondition(store.evidence[cid]?.code == "SNOS-489")
            do { try store.importHTML(Data((canonical + detail + "<tr><th>メーカー品番</th><td>NO-001</td></tr>").utf8)); preconditionFailure() } catch { }
            precondition(store.evidence[cid]?.code == "SNOS-489")
        }
        for bad in ["http://video.dmm.co.jp/av/ranking/?term=weekly", "https://evil.example/", "https://video.dmm.co.jp.evil.example/av/ranking/?term=weekly", "https://accounts.dmm.co.jp/", "https://www.dmm.co.jp/age_check/=/declared=yes/?rurl=https%3A%2F%2Fevil.example"] {
            precondition(!DMMTransport.allowed(URL(string: bad)!))
        }
        let returnURL = "https%3A%2F%2Fvideo.dmm.co.jp%2Fav%2Franking%2F%3Fterm%3Dweekly"
        let ageURL = URL(string: "https://www.dmm.co.jp/age_check/=/?rurl=" + returnURL)!
        let yes = "https://www.dmm.co.jp/age_check/=/declared=yes/?rurl=" + returnURL
        let object: [String: Any] = ["props": ["pageProps": ["yesButtonLink": yes]]]
        let json = String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
        let age = "18歳以上<script id=\"__NEXT_DATA__\" type=\"application/json\">" + json + "</script>"
        let confirmed = try DMMTransport.declaration(html: age, ageURL: ageURL)
        precondition(confirmed.absoluteString == yes)
        do { _ = try DMMTransport.declaration(html: age.replacingOccurrences(of: "www.dmm.co.jp", with: "evil.example"), ageURL: ageURL); preconditionFailure() } catch { }
        print("PASS: production import100, bounded2, CID inflight dedup, cache, cancellation generation, manufacturer identity, official declaration link and cross-domain allowlist")
    }
}
