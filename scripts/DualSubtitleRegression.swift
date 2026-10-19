import Foundation

actor DualFixtureTransport {
    var counts: [OnlineSubtitleRequestKindKey: Int] = [:]
    var catDelay: UInt64 = 20_000_000
    var xunleiDelay: UInt64 = 80_000_000
    var failXunlei = false
    enum OnlineSubtitleRequestKindKey: Hashable { case xunlei, cat, detail, download }
    func configure(cat: UInt64, xunlei: UInt64, fail: Bool = false) { catDelay = cat; xunleiDelay = xunlei; failXunlei = fail }
    func count(_ key: OnlineSubtitleRequestKindKey) -> Int { counts[key] ?? 0 }
    func fetch(_ url: URL, _ kind: OnlineSubtitleRequestKind) async throws -> Data {
        let key: OnlineSubtitleRequestKindKey
        switch kind { case .xunleiSearch: key = .xunlei; case .catSearch: key = .cat; case .catDetail: key = .detail; case .download: key = .download }
        counts[key, default: 0] += 1
        let delay = kind == .xunleiSearch ? xunleiDelay : catDelay
        // Deliberately return despite cancellation: production epochs must reject late bytes.
        try? await Task.sleep(nanoseconds: delay)
        if kind == .xunleiSearch && failXunlei { throw OnlineSubtitleError.invalid("fixture HTTP 429") }
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value ?? "variant"
        switch kind {
        case .xunleiSearch:
            return try JSONSerialization.data(withJSONObject: ["code": 0, "data": [["name": q, "url": DualSourceRegression.cdn, "ext": "srt"]]])
        case .catSearch:
            return Data("<table class='sub-table'><tr><td><a href='/subs/1/fixture.html'>\(q)</a> (translated from Japanese)</td></tr></table>".utf8)
        case .catDetail: return DualSourceRegression.detail
        case .download: return Data("1\n00:00:01,000 --> 00:00:03,000\nSelf authored\n".utf8)
        }
    }
}
enum DualSourceRegression {
    static let cdn = "https://subtitle.v.geilijiasu.com/AA/BB/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.srt"
    static let detail = Data("<div class='sub-single'><a id='download_en' href='/subs/3/test-en.srt'>Download</a><a id='download_zh-TW' href='/subs/1706/中文%20test-zh-TW.srt'>Download</a><a id='download_zh-CN' href='/subs/1721/中文 test-zh-CN.srt'>Download</a><a id='download_zh-CN' href='/subs/1721/中文 test-zh-CN.srt'>Duplicate</a><a id='download_fr' href='https://evil.test/subs/1/evil.srt'>Bad</a><button>Translate</button></div>".utf8)
    @MainActor static func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<300 { if predicate() { return }; try await Task.sleep(nanoseconds: 5_000_000) }
        fatalError("Model failed to reach terminal state")
    }
    @MainActor static func run() async throws {
        let page = try SubtitleCatProvider.searchURL("TEST & 中文")
        precondition(URLComponents(url: page, resolvingAgainstBaseURL: false)!.queryItems!.first!.value == "TEST & 中文")
        let html = Data("<table class='sub-table'><tr><td><a href='subs/1706/中文%20test.html'>Same</a> (translated from Japanese)</td><td><a href='subs/1706/中文%20test.html'>Duplicate</a><a href='subs/1707/中文 test.html'>Same</a><a href='https://evil.test/subs/1/test.html'>Bad</a></td></tr></table>".utf8)
        let rows = try SubtitleCatProvider.candidates(html, page: page)
        precondition(rows.count == 2 && rows[0].id != rows[1].id && rows[0].language == "待选语言")
        precondition(rows[0].url.absoluteString.contains("%20") && !rows[0].url.absoluteString.contains("%2520"))
        let variants = try SubtitleCatProvider.languages(detail, row: rows[0])
        precondition(variants.count == 3 && variants[0].language == "简体中文 (zh-CN)" && variants[1].language == "繁体中文 (zh-TW)")
        precondition(variants[0].url.path.hasPrefix("/subs/1721/") && variants[1].url.path.hasPrefix("/subs/1706/"))
        precondition(variants[0].parentID == rows[0].id)
        let empty = try SubtitleCatProvider.languages(Data("<div class='sub-single'><button id='translate_zh-CN'>Translate</button></div>".utf8), row: rows[0])
        precondition(empty.isEmpty)
        for bad in ["<html><title>Just a moment</title></html>", "<table class='sub-table'></table><script src='/cdn-cgi/challenge-platform/x'></script>", "<html>unknown markup</html>"] {
            SubtitleRegression.reject { _ = try SubtitleCatProvider.candidates(Data(bad.utf8), page: page) }
        }
        let noResults = try SubtitleCatProvider.candidates(Data("<table class='sub-table'></table>".utf8), page: page)
        precondition(noResults.isEmpty)
        for raw in ["http://www.subtitlecat.com/subs/1/a.srt", "https://www.subtitlecat.com.evil.test/subs/1/a.srt", "https://127.0.0.1/subs/1/a.srt", "https://[::1]/subs/1/a.srt", "https://u@www.subtitlecat.com/subs/1/a.srt", "https://www.subtitlecat.com:444/subs/1/a.srt", "https://www.subtitlecat.com/subs/1/a.srt?x=1", "https://www.subtitlecat.com/subs/1/a.srt#x", "https://www.subtitlecat.com/subs/1/a%2fb.srt", "https://www.subtitlecat.com/subs/1/a%2520.srt", "https://www.subtitlecat.com/subs/1/a.zip"] {
            precondition(!SubtitleCatProvider.allowed(URL(string: raw)!, kind: .download))
        }
        let srtURL = variants[0].url
        precondition(!OnlineSubtitleRequest(kind: .download).allowed(srtURL))
        precondition(OnlineSubtitleRequest(kind: .download, boundDownloadURL: srtURL).allowed(srtURL))
        precondition(!OnlineSubtitleRequest(kind: .download, boundDownloadURL: srtURL).allowed(variants[1].url))
        // Production epoch aggregation: either finish order, partial failure, duplicates and stale replies.
        for order in [[OnlineSubtitleSource.xunlei, .subtitleCat], [.subtitleCat, .xunlei]] {
            var state = OnlineSubtitleSearchState(); let token = state.begin()
            precondition(state.receive(order[0], token: token, result: .success(rows)))
            precondition(state.results.count == 2 && state.pending.count == 1)
            precondition(state.receive(order[1], token: token, result: .failure(OnlineSubtitleError.invalid("403"))))
            precondition(state.results.count == 2 && state.pending.isEmpty)
            precondition(!state.receive(order[0], token: token, result: .success([])))
            state.invalidate(); precondition(!state.receive(order[0], token: token, result: .success([])))
        }
        let transport = DualFixtureTransport()
        let model = OnlineSubtitleModel(fetch: { url, kind in try await transport.fetch(url, kind) })
        model.query = "first"; model.search()
        try await wait { model.results.count == 1 }
        precondition(model.results[0].source == .subtitleCat && model.busy)
        try await wait { !model.busy }
        precondition(model.results.count == 2 && Set(model.results.map(\.id)).count == 2)
        let initialDetailCount = await transport.count(.detail); let initialDownloads = await transport.count(.download)
        precondition(initialDetailCount == 0 && initialDownloads == 0)
        let candidate = model.results.first { $0.source == .subtitleCat }!
        model.choose(candidate); try await wait { model.languages[candidate.id] != nil }
        precondition(model.cues.isEmpty && model.selected == nil)
        let stillNoDownload = await transport.count(.download); precondition(stillNoDownload == 0)
        model.choose(model.languages[candidate.id]![0]); try await wait { model.selected != nil }
        precondition(model.cues.count == 1 && model.selected?.parentID == candidate.id)
        model.cancelPending(); precondition(model.cues.count == 1)
        let beforeCache = await transport.count(.xunlei)
        model.search(); try await wait { !model.busy }
        let afterCache = await transport.count(.xunlei); precondition(beforeCache == afterCache)
        // New query cancels old downloads. Disabling and media clear never allow a late selection.
        model.choose(model.results.first { $0.source == .xunlei }!); model.disable()
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(model.selected == nil && model.cues.isEmpty)
        model.query = "second"; model.search(); model.clear()
        try await Task.sleep(nanoseconds: 150_000_000)
        precondition(model.results.isEmpty && model.cues.isEmpty && model.query.isEmpty)
        model.query = "obsolete"; model.search(); model.query = "new query"; model.search()
        try await wait { !model.busy }
        precondition(model.results.count == 2 && model.results.allSatisfy { $0.name == "new query" })
        // Reverse completion in real parallel production search, then one provider fails.
        await transport.configure(cat: 80_000_000, xunlei: 10_000_000)
        model.query = "reverse"; model.search(); try await wait { model.results.count == 1 }
        precondition(model.results[0].source == .xunlei && model.busy)
        try await wait { !model.busy }
        await transport.configure(cat: 10_000_000, xunlei: 30_000_000, fail: true)
        model.query = "one fails"; model.search(); try await wait { !model.busy }
        precondition(model.results.count == 1 && model.results[0].source == .subtitleCat)
        precondition(model.sourceStates[.xunlei]!.contains("429"))
        model.choose(model.results[0]); model.query = "changed during detail"
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(model.languages.isEmpty)
        print("PASS production DOM/URL policies, cross-directory variants, zh-CN/TW, manual-only download, dual-source partial/reverse/error/cache/epoch cancellation")
    }
}
