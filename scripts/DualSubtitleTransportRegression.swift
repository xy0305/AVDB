import Foundation

enum DualSubtitleTransportRegression {
    static func rejects(_ work: () async throws -> Data) async {
        do { _ = try await work(); fatalError("Expected transport rejection") } catch {}
    }
    static func run() async throws {
        let search = try SubtitleCatProvider.searchURL("neutral fixture")
        let detail = URL(string: "https://www.subtitlecat.com/subs/1706/fixture.html")!
        let srt = URL(string: "https://www.subtitlecat.com/subs/1721/fixture-zh-CN.srt")!
        func request(_ kind: OnlineSubtitleRequestKind) -> OnlineSubtitleRequest {
            OnlineSubtitleRequest(kind: kind, boundDownloadURL: kind == .download ? srt : nil, protocolClasses: [FixtureProtocol.self])
        }
        FixtureProtocol.payload = Data("<table class='sub-table'></table>".utf8); FixtureProtocol.mime = "text/html"
        let html = try await request(.catSearch).run(search)
        precondition(html == FixtureProtocol.payload)
        for status in [403, 429, 500] {
            FixtureProtocol.status = status
            await rejects { try await request(.catSearch).run(search) }
        }
        FixtureProtocol.status = 200
        FixtureProtocol.payload = Data(repeating: 32, count: OnlineSubtitlePolicy.searchLimit + 1)
        await rejects { try await request(.catSearch).run(search) }
        await rejects { try await request(.catDetail).run(detail) }
        FixtureProtocol.payload = Data("<html>not subtitle</html>".utf8)
        await rejects { try await request(.download).run(srt) }
        FixtureProtocol.mime = "application/octet-stream"
        await rejects { try await request(.download).run(srt) }
        FixtureProtocol.payload = Data([0x50, 0x4b, 0x03, 0x04, 1, 2, 3])
        await rejects { try await request(.download).run(srt) }
        FixtureProtocol.mime = "application/zip"
        await rejects { try await request(.download).run(srt) }
        FixtureProtocol.mime = "application/octet-stream"
        FixtureProtocol.payload = Data(repeating: 32, count: OnlineSubtitlePolicy.downloadLimit + 1)
        await rejects { try await request(.download).run(srt) }
        // URLSession delivers decompressed bytes; Content-Length can describe compressed bytes.
        // A mismatch is not truncation by itself. The decoded streaming cap still applies.
        FixtureProtocol.extraHeaders = ["Content-Encoding": "gzip", "Content-Length": "10"]
        FixtureProtocol.payload = Data("1\n00:00:01,000 --> 00:00:03,000\nSelf-authored valid text\n".utf8)
        let decoded = try await request(.download).run(srt)
        precondition(decoded == FixtureProtocol.payload)
        FixtureProtocol.payload = Data(repeating: 32, count: OnlineSubtitlePolicy.downloadLimit + 1)
        await rejects { try await request(.download).run(srt) }
        FixtureProtocol.extraHeaders = [:]
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: detail)
        let response = HTTPURLResponse(url: detail, statusCode: 302, httpVersion: nil, headerFields: nil)!
        for target in [srt, URL(string: "https://evil.test/subs/1/fixture.html")!, URL(string: "https://127.0.0.1/subs/1/fixture.html")!] {
            var followed = true
            request(.catDetail).urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: target)) { followed = $0 != nil }
            precondition(!followed)
        }
        let capped = request(.catDetail)
        for index in 1...6 {
            var followed = false
            capped.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: detail)) { followed = $0 != nil }
            precondition(followed == (index <= 5))
        }
        var followedOtherSRT = true
        request(.download).urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: URL(string: "https://www.subtitlecat.com/subs/1/unbound.srt")!)) { followedOtherSRT = $0 != nil }
        precondition(!followedOtherSRT)
        print("PASS production typed HTML/SRT transport, 403/429, HTML/ZIP masquerades, decoded gzip caps, redirect category/binding/hop limit")
    }
}
