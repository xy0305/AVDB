"""Injected MissAV discovery stages and detail-scroll hot-path guards.
No network, no adult fixture, no challenge solving.
"""
import Foundation

@main struct MissAVScrollRegression262 {
    static func main() async {
        var count = 0
        func check(_ value: Bool, _ name: String) {
            count += 1
            precondition(value, name)
        }
        let search = URL(string: "https://missav.ws/en/search/ABP-123")!
        let detail = URL(string: "https://missav.ws/dm339/en/abp-123")!
        let media = URL(string: "https://surrit.neutral.example/playlist.m3u8")!
        func loader(_ status: Int, _ url: URL, _ body: String = "<html></html>") -> (@Sendable (URLRequest) async throws -> Data) {
            return { request in
                let sent = request.value(forHTTPHeaderField: "Accept")
                if url.path.hasSuffix(".m3u8") {
                    precondition(sent == nil, "media request must not inherit document Accept")
                } else {
                    precondition(sent == "text/html,application/xhtml+xml", "document request keeps browser Accept")
                    precondition(request.value(forHTTPHeaderField: "Origin") == "https://missav.ws", "approved origin retained")
                    precondition(request.value(forHTTPHeaderField: "User-Agent") == OnlinePolicy.ua, "258 user agent retained")
                }
                if status == 403 { throw OnlineFailure.httpResponse(403, at: url) }
                return Data(body.utf8)
            }
        }
        let blocked = OnlineTransport(loader: loader(403, search))
        do {
            _ = try await blocked.fetch(search, cap: 1024, headers: OnlinePolicy.documentHeaders(referrer: URL(string: "https://missav.ws/dm339")!))
            preconditionFailure("injected 403 must fail")
        } catch let error as OnlineFailure {
            let shown = error.presentation(at: .discovery)
            check(shown.stage == .discovery && shown.category == .http && shown.httpCode == 403, "query 403 stays at discovery")
            check(shown.display.contains("查询") && shown.display.contains("403"), "query display names stage and status")
            check(!shown.display.contains("清单") && !shown.display.contains("首帧"), "query 403 is not a manifest or frame failure")
        } catch { preconditionFailure("unexpected query error") }

        let foundBody = #"<a href="https://missav.ws/dm339/en/abp-123">ABP-123</a>"#
        let found = OnlineProvider(transport: OnlineTransport(loader: loader(200, search, foundBody)))
        let rows = try await found.discover(.missav, number: "ABP-123", versions: false)
        check(rows.count == 1 && rows[0].code == "ABP-123", "injected readable search is a found work, not a 403")

        let detailBlocked = OnlineProvider(transport: OnlineTransport(loader: loader(403, detail)))
        do {
            _ = try await detailBlocked.resolve(rows[0], number: "ABP-123", versions: false)
            preconditionFailure("detail 403 must fail")
        } catch let error as OnlineFailure {
            let shown = error.presentation(at: .document)
            check(shown.stage == .document && shown.httpCode == 403, "detail 403 is not reported as query or manifest")
        } catch { preconditionFailure("unexpected detail error") }

        let master = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=4500000,RESOLUTION=1920x1080\nhigh.m3u8\n"
        let leaf = "#EXTM3U\n#EXTINF:4,\nseg.ts\n"
        let mediaLoader: @Sendable (URLRequest) async throws -> Data = { request in
            precondition(request.value(forHTTPHeaderField: "Accept") == nil, "playlist keeps media headers")
            return request.url?.absoluteString.hasSuffix("high.m3u8") == true ? Data(leaf.utf8) : Data(master.utf8)
        }
        let plan = try await OnlineProvider(transport: OnlineTransport(loader: mediaLoader)).validatedPlan(
            media: media, referrer: detail, line: rows[0], number: "ABP-123", pageIssued: true)
        check(plan.ladder.first?.height == 1080, "manifest validation still exposes the highest legal rung")
        let choice = OnlineQualitySelector.select(plan.ladder, preferHighest: true)
        check(choice.mode == .highest && choice.peakBitRate == 4_500_000, "highest-quality session selection retained")
        check(choice.maximumResolution == CGSize(width: 1920, height: 1080), "session cap remains finite")

        var state = PlaybackResourceCardState()
        check(state.model == nil, "detail construction does not create an online model")
        let before = state
        state.showsOnline = true
        check(before.model == nil && state.showsOnline, "scroll input changes do not allocate a session")
        state.model = OnlinePlaybackModel(preferences: UserDefaults(suiteName: "avdb.scroll262")!)
        check(state.model?.plan == nil && state.model?.state(.missav) == .idle, "opening the sheet still does not query")
        print("PASS262", count, "injected query/detail/manifest stages and scroll allocation guards; no network or adult media")
    }
}
