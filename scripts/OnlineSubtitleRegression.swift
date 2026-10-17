import Foundation
import CoreFoundation

final class FixtureProtocol: URLProtocol {
    static var payload = Data()
    static var status = 200
    static var mime = "text/plain"
    static var seenHeaders: [String: String] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.seenHeaders = request.allHTTPHeaderFields ?? [:]
        let r = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": Self.mime])!
        client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct SubtitleRegression {
    static func reject(_ body: () throws -> Void) {
        do { try body(); fatalError("Expected rejection") } catch {}
    }
    static func main() async throws {
        let cdn = "https://subtitle.v.geilijiasu.com/AB/CD/" + String(repeating: "A", count: 40) + ".srt"
        let q = "公开 A&B + ?/# 中文"
        let u = try OnlineSubtitlePolicy.searchURL(q)
        precondition(URLComponents(url: u, resolvingAgainstBaseURL: false)!.queryItems!.first!.value == q)
        reject { _ = try OnlineSubtitlePolicy.searchURL("") }
        reject { _ = try OnlineSubtitlePolicy.searchURL(String(repeating: "x", count: 201)) }
        for raw in ["http://subtitle.v.geilijiasu.com/AB/CD/a.srt", "https://127.0.0.1/a.srt", "https://[::1]/a.srt", "https://subtitle.v.geilijiasu.com.evil/a.srt", cdn + "?x=1", cdn + "#x", cdn.replacingOccurrences(of: "https://", with: "https://user:pass@"), "https://subtitle.v.geilijiasu.com/evil.html"] {
            precondition(!OnlineSubtitlePolicy.allowed(URL(string: raw)!, search: false))
        }
        precondition(OnlineSubtitlePolicy.allowed(URL(string: cdn)!, search: false))
        let row: [String: Any] = ["url": cdn, "name": "自创合法字幕", "ext": "srt", "languages": ["", " "]]
        let json = try JSONSerialization.data(withJSONObject: ["code": 0, "result": "ok", "data": Array(repeating: row, count: 100)])
        let rows = try OnlineSubtitlePolicy.candidates(json)
        precondition(rows.count == 1 && rows[0].language == "未知")
        reject { _ = try OnlineSubtitlePolicy.candidates(Data("{}".utf8)) }
        reject { _ = try OnlineSubtitlePolicy.candidates(Data(repeating: 32, count: OnlineSubtitlePolicy.searchLimit + 1)) }
        let srt = Data("1\n00:00:01,000 --> 00:00:02,500\n自创第一句\n第二行\n\n2\n00:00:03,000 --> 00:00:04,000\n结束\n".utf8)
        let cues = try OnlineSubtitleParser.parse(srt, ext: "srt")
        precondition(cues.count == 2)
        precondition(OnlineSubtitleParser.display(cues, at: 1.5, offset: 0).contains("第一句"))
        precondition(OnlineSubtitleParser.display(cues, at: 1.5, offset: 1).isEmpty)
        precondition(!OnlineSubtitleParser.display(cues, at: 0.5, offset: -1).isEmpty)
        // Seek backward/forward, paused repeated clock, and speed changes use the same media clock.
        for t in [3.5, 1.5, 1.5, 1.5, 2.5, 4.5] {
            let expected = cues.filter { $0.start <= t && t < $0.end }.map(\.text).joined(separator: "\n")
            precondition(OnlineSubtitleParser.display(cues, at: t, offset: 0) == expected)
        }
        let vtt = Data("WEBVTT\n\nNOTE ignore --> invalid\ntext\n\n00:01.000 --> 00:02.000 align:center\n<b>自创 VTT</b>\n".utf8)
        let parsedVTT = try OnlineSubtitleParser.parse(vtt, ext: "vtt")
        precondition(parsedVTT.first!.text == "自创 VTT")
        let ass = Data("[Script Info]\nTitle: Self-authored\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,{\\b1}自创, ASS\\N第二行\n".utf8)
        let parsedASS = try OnlineSubtitleParser.parse(ass, ext: "ass")
        precondition(parsedASS.first!.text == "自创, ASS\n第二行")
        for bad in [Data("<html>error</html>".utf8), Data("<?xml version='1.0'?><Error>NoSuchKey</Error>".utf8), Data([0,1,2]), Data("1\n00:00:01,000 --> 00:00:00,000\n错误\n".utf8), Data((String(repeating: "x", count: 17000)).utf8)] {
            reject { _ = try OnlineSubtitleParser.parse(bad, ext: "srt") }
        }
        #if canImport(Darwin)
        for (hint, cf) in [("gb18030", CFStringEncodings.GB_18030_2000), ("big5", CFStringEncodings.big5)] {
            let e = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cf.rawValue)))
            let text = "1\n00:00:01,000 --> 00:00:03,000\n中文測試\n"
            let encoded = text.data(using: e)!
            let parsedLegacy = try OnlineSubtitleParser.parse(encoded, ext: "srt", encodingHint: hint)
            precondition(parsedLegacy.first!.text == "中文測試")
        }
        #endif
        FixtureProtocol.payload = json; FixtureProtocol.mime = "application/json"
        let fetched = try await OnlineSubtitleRequest(search: true, protocolClasses: [FixtureProtocol.self]).run(u)
        precondition(fetched == json)
        for key in FixtureProtocol.seenHeaders.keys {
            precondition(!["cookie", "authorization", "referer", "x-115-token"].contains(key.lowercased()))
        }
        FixtureProtocol.payload = Data(repeating: 32, count: OnlineSubtitlePolicy.searchLimit + 1)
        do { _ = try await OnlineSubtitleRequest(search: true, protocolClasses: [FixtureProtocol.self]).run(u); fatalError("Oversize accepted") } catch {}
        FixtureProtocol.payload = srt; FixtureProtocol.mime = "text/html"
        do { _ = try await OnlineSubtitleRequest(search: false, protocolClasses: [FixtureProtocol.self]).run(URL(string: cdn)!); fatalError("HTML accepted") } catch {}
        let delegate = OnlineSubtitleRequest(search: false)
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URL(string: cdn)!)
        var followed = true
        delegate.urlSession(session, task: task, willPerformHTTPRedirection: HTTPURLResponse(url: URL(string: cdn)!, statusCode: 302, httpVersion: nil, headerFields: nil)!, newRequest: URLRequest(url: URL(string: "https://127.0.0.1/secret")!), completionHandler: { followed = $0 != nil })
        precondition(!followed); session.invalidateAndCancel()
        if ProcessInfo.processInfo.environment["SUBTITLE_LIVE_PROBE"] == "1" {
            let live = try await OnlineSubtitleRequest(search: true).run(OnlineSubtitlePolicy.searchURL("Oppenheimer 2023"))
            let liveRows = try OnlineSubtitlePolicy.candidates(live)
            print("LIVE system URLSession TLS verified: accepted candidates=\(liveRows.count), bytes=\(live.count)")
        }
        print("PASS production subtitle encoding, candidates, caps, SRT/ASS/VTT, offsets/media clock, anonymous transport, redirects, errors")
    }
}
