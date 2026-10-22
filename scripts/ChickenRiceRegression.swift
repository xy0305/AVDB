import Foundation
import CryptoKit

actor ChickenFixtureTransport {
    var counts: [String: Int] = [:]
    var failure: OnlineSubtitleRequestKind?
    var chickenDelay: UInt64 = 10_000_000
    static let srt = Data("1\n00:00:01,000 --> 00:00:03,000\nSelf authored neutral fixture\n".utf8)
    func count(_ kind: String) -> Int { counts[kind, default: 0] }
    func configure(failure: OnlineSubtitleRequestKind? = nil, delay: UInt64 = 10_000_000) { self.failure = failure; chickenDelay = delay }
    func fetch(_ url: URL, _ kind: OnlineSubtitleRequestKind) async throws -> Data {
        let key = String(describing: kind); counts[key, default: 0] += 1
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value ?? "TEST-001"
        try? await Task.sleep(nanoseconds: kind == .chickenSearch ? chickenDelay : 30_000_000)
        if kind == failure { throw OnlineSubtitleError.invalid("fixture HTTP 403") }
        switch kind {
        case .chickenSearch: return try ChickenRiceRegression.json(["id":"neutral \u{4e2d}","code":q,"format":"srt","sha256":ChickenRiceRegression.hash(Self.srt),"duration_seconds":3,"size_bytes":Self.srt.count])
        case .xunleiSearch: return try JSONSerialization.data(withJSONObject: ["code":0,"data":[["name":q,"ext":"srt","url":DualSourceRegression.cdn]]])
        case .catSearch: return Data("<table class='sub-table'><a href='/subs/1/fixture.html'>\(q)</a></table>".utf8)
        case .catDetail: return DualSourceRegression.detail
        case .download: return Self.srt
        }
    }
}
enum ChickenRiceRegression {
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func json(_ row: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: ["items":[row]]) }
    @MainActor static func run() async throws {
        let stored = UserDefaults.standard.object(forKey: "subtitle.chickenRice.enabled")
        defer { if let stored { UserDefaults.standard.set(stored, forKey: "subtitle.chickenRice.enabled") } else { UserDefaults.standard.removeObject(forKey: "subtitle.chickenRice.enabled") } }
        let query = "TEST-001"
        let search = try ChickenRiceProvider.searchURL(query)
        precondition(ChickenRiceProvider.allowed(search, search: true))
        let items = URLComponents(url: search, resolvingAgainstBaseURL: false)!.queryItems!
        precondition(items.count == 1 && items[0].name == "code" && items[0].value == query)
        // No substring, ambiguous digit label, title, media URL or unsupported FC2 request.
        for bad in ["TEST-001 movie", "R18292", "FC2-PPV-00123", "Oppenheimer 2023", "https://private.test/media.mp4", "", "TEST-000"] {
            SubtitleRegression.reject { _ = try ChickenRiceProvider.searchURL(bad) }
        }
        for id in ["a b中文?#:@", "opaque-id_1", "uuid.123"] {
            let u = try ChickenRiceProvider.downloadURL(id)
            precondition(ChickenRiceProvider.allowed(u, search: false) && u.query == nil && u.fragment == nil)
            precondition(u.path.split(separator: "/")[3] == Substring(id))
        }
        for id in ["", ".", "..", "../escape", "a/b", "a\\b", "%2f", "%252f", "bad\n", String(repeating: "x", count: 513)] {
            SubtitleRegression.reject { _ = try ChickenRiceProvider.downloadURL(id) }
        }
        let download = try ChickenRiceProvider.downloadURL("neutral-id")
        for raw in [download.absoluteString.replacingOccurrences(of: "https:", with: "http:"), download.absoluteString.replacingOccurrences(of: ChickenRiceProvider.host, with: "evil.test"), download.absoluteString.replacingOccurrences(of: ChickenRiceProvider.host, with: ChickenRiceProvider.host + ".evil.test"), download.absoluteString.replacingOccurrences(of: "https://", with: "https://user@"), download.absoluteString.replacingOccurrences(of: ChickenRiceProvider.host, with: ChickenRiceProvider.host + ":444"), download.absoluteString + "?token=bad", download.absoluteString + "#fragment", ChickenRiceProvider.origin + "/api/v1/subtitles/a%2fb/download"] {
            precondition(!ChickenRiceProvider.allowed(URL(string: raw)!, search: false))
        }
        let base: [String: Any] = ["id":"neutral-id", "code":query, "format":"srt", "duration_seconds":3, "size_bytes":ChickenFixtureTransport.srt.count,"sha256":hash(ChickenFixtureTransport.srt),"uploaded_at":"2026-01-01T00:00:00Z"]
        let rows = try ChickenRiceProvider.candidates(json(base), query: query)
        precondition(rows.count == 1 && rows[0].source == .chickenRice && rows[0].language == "未知")
        precondition(rows[0].durationSeconds == 3 && rows[0].sizeBytes == ChickenFixtureTransport.srt.count && rows[0].uploadedAt != nil)
        try ChickenRiceProvider.verify(ChickenFixtureTransport.srt, row: rows[0])
        SubtitleRegression.reject { try ChickenRiceProvider.verify(Data("tampered".utf8), row: rows[0]) }
        var absent = base; for key in ["duration_seconds", "size_bytes", "sha256", "uploaded_at"] { absent.removeValue(forKey: key) }
        let absentRows = try ChickenRiceProvider.candidates(json(absent), query: query)
        precondition(absentRows[0].durationSeconds == nil && absentRows[0].sizeBytes == nil && absentRows[0].uploadedAt == nil)
        for (key, value) in [("duration_seconds", -1 as Any), ("duration_seconds", true as Any), ("duration_seconds", "3" as Any), ("size_bytes", -1 as Any), ("size_bytes", 1.5 as Any), ("size_bytes", OnlineSubtitlePolicy.downloadLimit + 1 as Any), ("sha256", "not-a-hash" as Any)] {
            var bad = base; bad[key] = value
            SubtitleRegression.reject { _ = try ChickenRiceProvider.candidates(json(bad), query: query) }
        }
        for format in ["zip", "html", "exe"] {
            var bad = base; bad["format"] = format
            let parsed = try ChickenRiceProvider.candidates(json(bad), query: query); precondition(parsed.isEmpty)
        }
        for code in ["XTEST-001", "TEST-0012", "TEST-001 other", "123TEST-001"] {
            var bad = base; bad["code"] = code
            let parsed = try ChickenRiceProvider.candidates(json(bad), query: query); precondition(parsed.isEmpty)
        }
        SubtitleRegression.reject { _ = try ChickenRiceProvider.candidates(Data("{}".utf8), query: query) }
        SubtitleRegression.reject { _ = try ChickenRiceProvider.candidates(Data(repeating: 32, count: OnlineSubtitlePolicy.searchLimit + 1), query: query) }
        let ssa = Data("[Events]\nFormat: Marked, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: Marked=0,0:00:01.00,0:00:03.00,Default,,0,0,0,,Neutral SSA\n".utf8)
        let ssaCues = try OnlineSubtitleParser.parse(ssa, ext: "ssa"); precondition(ssaCues.count == 1)
        try await transport(search: search, download: download)
        try await modelTests()
        print("PASS production ChickenRice strict schema/code/opaque-ID/origin/SHA256/SSA/transport and three-source model regressions")
        if ProcessInfo.processInfo.environment["CHICKEN_LIVE_PROBE"] == "1" { await live() }
    }
    static func transport(search: URL, download: URL) async throws {
        func request(_ kind: OnlineSubtitleRequestKind) -> OnlineSubtitleRequest {
            OnlineSubtitleRequest(kind: kind, boundDownloadURL: kind == .download ? download : nil, protocolClasses: [FixtureProtocol.self])
        }
        FixtureProtocol.status = 200; FixtureProtocol.mime = "application/json"; FixtureProtocol.extraHeaders = [:]
        FixtureProtocol.payload = Data(#"{"items":[]}"#.utf8)
        let empty = try await request(.chickenSearch).run(search); precondition(!empty.isEmpty)
        for key in FixtureProtocol.seenHeaders.keys { precondition(!["cookie", "authorization", "referer", "x-115-token", "x-api-token"].contains(key.lowercased())) }
        for status in [401, 403, 404, 429, 500] {
            FixtureProtocol.status = status
            await DualSubtitleTransportRegression.rejects { try await request(.chickenSearch).run(search) }
            await DualSubtitleTransportRegression.rejects { try await request(.download).run(download) }
        }
        FixtureProtocol.status = 200
        FixtureProtocol.payload = Data(repeating: 32, count: OnlineSubtitlePolicy.searchLimit + 1)
        await DualSubtitleTransportRegression.rejects { try await request(.chickenSearch).run(search) }
        FixtureProtocol.mime = "application/octet-stream"
        FixtureProtocol.payload = Data(repeating: 32, count: OnlineSubtitlePolicy.downloadLimit + 1)
        await DualSubtitleTransportRegression.rejects { try await request(.download).run(download) }
        for payload in [Data("<html>Denied</html>".utf8), Data([0x50,0x4b,0x03,0x04])] {
            FixtureProtocol.payload = payload
            await DualSubtitleTransportRegression.rejects { try await request(.download).run(download) }
        }
        FixtureProtocol.payload = ChickenFixtureTransport.srt; FixtureProtocol.mime = "text/html"
        await DualSubtitleTransportRegression.rejects { try await request(.download).run(download) }
        FixtureProtocol.mime = "application/zip"
        await DualSubtitleTransportRegression.rejects { try await request(.download).run(download) }
        FixtureProtocol.mime = "text/plain"
        let srt = try await request(.download).run(download); precondition(srt == ChickenFixtureTransport.srt)
        precondition(!OnlineSubtitleRequest(kind: .download).allowed(download))
        precondition(!request(.download).allowed(URL(string: DualSourceRegression.cdn)!))
        let session = URLSession(configuration: .ephemeral); defer { session.invalidateAndCancel() }
        for kind in [OnlineSubtitleRequestKind.chickenSearch, .download] {
            let url = kind == .download ? download : search
            for target in [url, URL(string: "https://evil.test/")!, URL(string: DualSourceRegression.cdn)!] {
                var followed = true
                request(kind).urlSession(session, task: session.dataTask(with: url), willPerformHTTPRedirection: HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil)!, newRequest: URLRequest(url: target)) { followed = $0 != nil }
                precondition(!followed)
            }
        }
    }
    @MainActor static func modelTests() async throws {
        // All three real production aggregators, both completion orders and individual failure.
        for order in [[OnlineSubtitleSource.chickenRice, .subtitleCat, .xunlei], [.xunlei, .subtitleCat, .chickenRice]] {
            var state = OnlineSubtitleSearchState(); let token = state.begin()
            precondition(state.pending.count == 3)
            for (i, source) in order.enumerated() {
                precondition(state.receive(source, token: token, result: i == 1 ? .failure(OnlineSubtitleError.invalid("403")) : .success([])))
                precondition(state.pending.count == 2 - i)
            }
            state.invalidate(); precondition(!state.receive(.chickenRice, token: token, result: .success([])))
        }
        let transport = ChickenFixtureTransport()
        let model = OnlineSubtitleModel(fetch: { url, kind in try await transport.fetch(url, kind) })
        model.chickenRiceEnabled = true; model.query = "TEST-001"
        let before = await transport.count("chickenSearch"); precondition(before == 0)
        model.search(); try await DualSourceRegression.wait { !model.busy }
        precondition(model.results.count == 3 && Set(model.results.map(\.source)).count == 3)
        let noDownload = await transport.count("download"); precondition(noDownload == 0 && model.cues.isEmpty)
        let row = model.results.first { $0.source == .chickenRice }!
        model.choose(row); try await DualSourceRegression.wait { !model.busy }
        precondition(model.selected == row && model.cues.count == 1)
        // A corrupt digest does not replace the previously active cues.
        var corrupt = row; corrupt.expectedSHA256 = String(repeating: "0", count: 64)
        model.results = [corrupt]; model.choose(corrupt); try await DualSourceRegression.wait { !model.busy }
        precondition(model.selected == row && model.cues.count == 1 && model.status.contains("SHA-256"))
        model.search(); try await DualSourceRegression.wait { !model.busy }
        let cached = await transport.count("chickenSearch"); precondition(cached == 1)
        model.chickenRiceEnabled = false; model.search(); try await DualSourceRegression.wait { !model.busy }
        let disabled = await transport.count("chickenSearch"); precondition(disabled == cached && model.results.count == 2)
        precondition(model.sourceStates[.chickenRice] == "已关闭")
        model.chickenRiceEnabled = true
        await transport.configure(failure: .chickenSearch, delay: 70_000_000)
        model.search(); try await DualSourceRegression.wait { !model.busy }
        precondition(model.results.count == 2 && model.sourceStates[.chickenRice]!.contains("403"))
        await transport.configure(failure: .xunleiSearch)
        model.query = "TEST-002"; model.search(); try await DualSourceRegression.wait { !model.busy }
        precondition(model.results.count == 2 && model.results.contains { $0.source == .chickenRice })
        await transport.configure(failure: .catSearch, delay: 70_000_000)
        model.query = "TEST-003"; model.search(); try await DualSourceRegression.wait { !model.busy }
        precondition(model.results.count == 2 && model.results.contains { $0.source == .chickenRice })
        let chosen = model.results.first { $0.source == .chickenRice }!
        model.choose(chosen); model.query = "TEST-004"
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(model.selected == row, "Late new selection must not replace previous cues")
        await transport.configure(delay: 150_000_000)
        model.search(); await Task.yield(); model.chickenRiceEnabled = false
        try await Task.sleep(nanoseconds: 220_000_000); precondition(model.results.isEmpty)
        model.chickenRiceEnabled = true; model.query = "TEST-005"; model.search(); model.clear()
        try await Task.sleep(nanoseconds: 220_000_000); precondition(model.results.isEmpty && model.cues.isEmpty)
    }
    static func live() async {
        // One explicit public number, no filename/hash/media URL/duration. Never print subtitle text.
        do {
            let query = "IPX-001"
            let data = try await OnlineSubtitleRequest(kind: .chickenSearch).run(ChickenRiceProvider.searchURL(query))
            let rows = try ChickenRiceProvider.candidates(data, query: query)
            print("CHICKEN_LIVE search=verified items=\(rows.count) metadata_bytes=\(data.count)")
            if let row = rows.first {
                let downloaded = try await OnlineSubtitleRequest(kind: .download, boundDownloadURL: row.url).run(row.url)
                try ChickenRiceProvider.verify(downloaded, row: row)
                let cues = try OnlineSubtitleParser.parse(downloaded, ext: row.ext)
                print("CHICKEN_LIVE download=verified bytes=\(downloaded.count) sha256_present=\(row.expectedSHA256 != nil) cues=\(cues.count) last_end=\(cues.last?.end ?? 0)")
            } else { print("CHICKEN_LIVE download=not_verified reason=no_candidates") }
        } catch {
            print("CHICKEN_LIVE not_verified domain=\((error as NSError).domain) code=\((error as NSError).code) detail=\(error.localizedDescription.prefix(200))")
        }
    }
}
