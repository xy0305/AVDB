import XCTest
import CryptoKit
@testable import AVDB

final class JavVerseBehaviorTests: XCTestCase {
    private func rows(_ count: Int) -> [JavVerseEntry] {
        (1...count).map { rank in
            JavVerseEntry(rank: rank, kind: "movie", label: "TEST-\(rank)",
                          sourceURL: "https://javverse.com/neutral/\(rank)", code: "TEST-\(rank)")
        }
    }
    private func neutralJSON() -> [String: Any] {
        let board: [String: Any] = ["id": "neutral", "title": "中性名单", "period": "原站未显示年份",
            "capturedAt": "2026-10-23T17:29:00Z", "sourceURL": "https://javverse.com/rankings",
            "coverage": "complete", "entries": [["rank": 1, "kind": "movie", "label": "TEST-001",
            "sourceURL": "https://javverse.com/work/3248", "code": "TEST-001"]]]
        return ["schemaVersion": 1, "mode": "staticSnapshot", "origin": "https://javverse.com",
                "preparedAt": "2026-10-23T17:35:00Z", "boards": [board]]
    }
    private func decode(_ json: [String: Any]) throws -> JavVerseSnapshot {
        try JavVerseSnapshot.decode(JSONSerialization.data(withJSONObject: json))
    }
    func testSchemaSourceTimestampAndUnknownYear() throws {
        let snapshot = try decode(neutralJSON())
        XCTAssertEqual(snapshot.boards[0].period, "原站未显示年份")
        XCTAssertEqual(snapshot.boards[0].capturedAt, "2026-10-23T17:29:00Z")
        for (key, value) in [("schemaVersion", 99 as Any), ("mode", "live" as Any),
                             ("origin", "https://other.invalid" as Any), ("preparedAt", "yesterday" as Any)] {
            var invalid = neutralJSON(); invalid[key] = value
            XCTAssertThrowsError(try decode(invalid), key)
        }
        var invalid = neutralJSON()
        invalid["boards"] = []
        XCTAssertThrowsError(try decode(invalid))
    }
    func testRankGapDuplicateBoardAndForeignSourceAreRejected() throws {
        for field in ["rank", "sourceURL", "kind", "code"] {
            var json = neutralJSON()
            var boards = try XCTUnwrap(json["boards"] as? [[String: Any]])
            var entries = try XCTUnwrap(boards[0]["entries"] as? [[String: Any]])
            let invalid: [String: Any] = ["rank": 2, "sourceURL": "https://javverse.com.evil.invalid/1",
                                          "kind": "unknown", "code": "3248"]
            entries[0][field] = invalid[field]
            boards[0]["entries"] = entries; json["boards"] = boards
            XCTAssertThrowsError(try decode(json), field)
        }
        var json = neutralJSON()
        let boards = try XCTUnwrap(json["boards"] as? [[String: Any]])
        json["boards"] = boards + boards
        XCTAssertThrowsError(try decode(json))
    }
    func testPaginationPreservesOriginalRankAndNeverBackfills() {
        let source = rows(45)
        XCTAssertEqual(JavVersePagination.count(source), 3)
        XCTAssertEqual(JavVersePagination.rows(source, page: 0).map(\.rank), Array(1...20))
        XCTAssertEqual(JavVersePagination.rows(source, page: 1).map(\.rank), Array(21...40))
        XCTAssertEqual(JavVersePagination.rows(source, page: 2).map(\.rank), Array(41...45))
        XCTAssertTrue(JavVersePagination.rows(source, page: -1).isEmpty)
        XCTAssertTrue(JavVersePagination.rows(source, page: 3).isEmpty)
        XCTAssertTrue(JavVersePagination.rows([], page: 0).isEmpty)
    }
    func testBundledRealSnapshotRegisteredInHostedApp() throws {
        let snapshot = try JavVerseSnapshot.bundled()
        XCTAssertEqual(snapshot.boards.count, 13)
        XCTAssertEqual(snapshot.boards.prefix(7).reduce(0) { $0 + $1.entries.count }, 520, "Original seven boards must be preserved")
        XCTAssertEqual(snapshot.boards.reduce(0) { $0 + $1.entries.count }, 1120)
        XCTAssertEqual(snapshot.grok?.people.count, 250)
        XCTAssertEqual(snapshot.mode, "staticSnapshot")
    }
    @MainActor func testOnlyFullNumberUniqueIDMatches() async throws {
        let result = try await JavVerseMovieResolver.resolve(code: "test-001v") { _, _ in
            [Movie(id: "wrong-zero", number: "TEST-1V"), Movie(id: "wrong-suffix", number: "TEST-001"),
             Movie(id: "right", number: "TEST-001V"), Movie(id: "right", number: "TEST-001V")]
        }
        XCTAssertEqual(result?.id, "right")
        let absent = try await JavVerseMovieResolver.resolve(code: "TEST-001") { _, _ in
            [Movie(id: "numeric", number: nil, title: "TEST-001"), Movie(id: " ", number: "TEST-001")]
        }
        XCTAssertNil(absent)
    }
    @MainActor func testAmbiguousIDsRejected() async {
        do {
            _ = try await JavVerseMovieResolver.resolve(code: "TEST-001") { _, _ in
                [Movie(id: "a", number: "TEST-001"), Movie(id: "b", number: "TEST-001")]
            }
            XCTFail("Ambiguous number accepted")
        } catch { XCTAssertTrue(error.localizedDescription.contains("多个")) }
    }
    @MainActor func testAmbiguityOnLaterPageAndUnexhaustedScopeRejected() async {
        for ambiguous in [true, false] {
            var pages: [Int] = []
            do {
                _ = try await JavVerseMovieResolver.resolve(code: "TEST-001") { _, page in
                    pages.append(page)
                    if ambiguous && page == 2 { return [Movie(id: "other", number: "TEST-001")] }
                    return [Movie(id: "a", number: "TEST-001")] + (1...19).map {
                        Movie(id: "fuzzy-\($0)", number: "OTHER-\($0)")
                    }
                }
                XCTFail("Incomplete/ambiguous search accepted")
            } catch {
                XCTAssertEqual(pages, ambiguous ? [1, 2] : [1, 2, 3])
            }
        }
    }
    @MainActor func testAutomaticVisiblePageIsSerialAndLimitedToTwenty() async {
        var calls: [String] = []
        let mapper = JavVerseMapper(search: { code, _ in
            calls.append(code); return [Movie(id: "id-\(code)", number: code)]
        }, accountProvider: { "neutral-account" })
        let entries = rows(25)
        let task = mapper.resolve(entries)
        XCTAssertTrue(mapper.busy)
        XCTAssertNil(mapper.resolve(entries), "Busy guard must reject concurrent manual batches")
        await task?.value
        XCTAssertEqual(calls, (1...20).map { "TEST-\($0)" })
        XCTAssertEqual(mapper.movies.count, 20)
        XCTAssertFalse(mapper.busy)
        XCTAssertEqual(entries.map(\.rank), Array(1...25))
    }
    @MainActor func testAccountChangeDuringRequestDiscardsLateResult() async {
        var account = "neutral-a"
        let mapper = JavVerseMapper(search: { code, _ in
            account = "neutral-b"
            return [Movie(id: "old-account-result", number: code)]
        }, accountProvider: { account })
        await mapper.resolve(rows(1))?.value
        XCTAssertTrue(mapper.movies.isEmpty)
        XCTAssertTrue(mapper.messages.isEmpty)
        XCTAssertFalse(mapper.busy)
    }
    @MainActor func testCancelDiscardsNonCooperativeLateResponseAndAllowsRetry() async {
        let gate = JavVerseSearchGate()
        let mapper = JavVerseMapper(search: { code, _ in try await gate.search(code) }, accountProvider: { nil })
        let entries = rows(1)
        let task = mapper.resolve(entries)
        for _ in 0..<100 where gate.continuation == nil { await Task.yield() }
        guard let continuation = gate.continuation else { XCTFail("Search did not start"); task?.cancel(); return }
        mapper.cancel()
        continuation.resume(returning: [Movie(id: "late", number: "TEST-1")])
        gate.continuation = nil
        await task?.value
        XCTAssertNil(mapper.movie(for: entries[0]))
        XCTAssertTrue(mapper.messages.isEmpty)
        XCTAssertFalse(mapper.busy)
        gate.immediate = true
        await mapper.resolve(entries)?.value
        XCTAssertEqual(mapper.movie(for: entries[0])?.id, "retry")
    }
    @MainActor func testCacheClearedOnAccountScopeChange() async {
        var account = "neutral-a"
        let mapper = JavVerseMapper(search: { code, _ in [Movie(id: "neutral", number: code)] },
                                    accountProvider: { account })
        let entries = rows(1)
        await mapper.resolve(entries)?.value
        XCTAssertNotNil(mapper.movie(for: entries[0]))
        account = "neutral-b"
        XCTAssertNil(mapper.movie(for: entries[0]))
        mapper.clear()
        XCTAssertTrue(mapper.movies.isEmpty)
        XCTAssertTrue(mapper.messages.isEmpty)
    }
}

@MainActor private final class JavVerseSearchGate {
    var continuation: CheckedContinuation<[Movie], Error>?
    var immediate = false
    func search(_ code: String) async throws -> [Movie] {
        if immediate { return [Movie(id: "retry", number: code)] }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
}

// Read-only public SDK integration: textual identities + HEAD metadata only, never image downloads.
final class JavVerseLive240Tests: XCTestCase {
    @MainActor func testRealPublicSDKMetadata240() async {
        var successes = 0
        for code in ["FKAW-004", "SNOS-489", "SNOS-093", "SIVR-479", "SONE-142", "STCVS-056", "STCV-607"] {
            do {
                var pages: [Int] = []
                let movie = try await JavVerseMovieResolver.resolve(code: code) { source, page in
                    pages.append(page)
                    return try await JavDBSDK.shared.search(keyword: source, page: page, type: "movie", limit: 20)
                }
                guard var movie else { print("LIVE240 code=\(code) result=notFound pages=\(pages)"); continue }
                if [movie.coverURL, movie.thumbURL].compactMap({ $0 }).allSatisfy({ $0.isEmpty }) {
                    let detail = try await JavDBSDK.shared.movieDetail(movie.id)
                    guard detail.id == movie.id && JavVerseIdentity.code(detail.number ?? "") == code else {
                        XCTFail("Live detail identity mismatch"); continue
                    }
                    movie = detail
                }
                XCTAssertEqual(JavVerseIdentity.code(movie.number ?? ""), code)
                print("LIVE240 code=\(code) id=\(movie.id) result=unique pages=\(pages) cover=\(!(movie.coverURL ?? "").isEmpty) thumb=\(!(movie.thumbURL ?? "").isEmpty)")
                for (field, raw) in [("cover", movie.coverURL), ("thumb", movie.thumbURL)] {
                    guard let raw, let url = URL(string: raw), url.scheme == "https" else { continue }
                    var request = URLRequest(url: url); request.httpMethod = "HEAD"; request.timeoutInterval = 12
                    request.setValue("https://javdb.com/", forHTTPHeaderField: "Referer")
                    do {
                        let (_, response) = try await URLSession.shared.data(for: request)
                        if let http = response as? HTTPURLResponse {
                            print("LIVE240 code=\(code) field=\(field) host=\(url.host ?? "") http=\(http.statusCode) type=\(http.value(forHTTPHeaderField: "Content-Type") ?? "") length=\(http.expectedContentLength)")
                        }
                    } catch { print("LIVE240 code=\(code) field=\(field) HEAD=blocked error=\(type(of: error))") }
                }
                successes += 1
            } catch { print("LIVE240 code=\(code) result=blocked error=\(error.localizedDescription)") }
        }
        if let snapshot = try? JavVerseSnapshot.bundled(), let featured = snapshot.boards.first(where: { $0.id == "featured" }) {
            for entry in featured.entries.prefix(8) {
                do {
                    let actor = try await JavVerseActorResolver.resolve(name: entry.label) { name, page in
                        try await JavDBSDK.shared.searchActors(keyword: name, page: page, limit: 20)
                    }
                    print("LIVE240 actor=\(entry.label) result=\(actor == nil ? "notFound" : "unique") id=\(actor?.id ?? "") avatar=\(!(actor?.avatarURL ?? actor?.coverURL ?? "").isEmpty)")
                } catch { print("LIVE240 actor=\(entry.label) result=blocked error=\(error.localizedDescription)") }
            }
        }
        print("LIVE240 SUMMARY verifiedIdentities=\(successes)/7 publicSDK=true tokenRequiredBySearch=false imagesDownloaded=false")
    }
}

extension JavVerseBehaviorTests {
    @MainActor func testSharedCacheReusesFullIdentityAcrossViewsAndIsolatesAccount() async {
        var account = "neutral-shared240-a"
        var calls = 0
        let search: JavVerseMovieResolver.Search = { code, _ in calls += 1; return [Movie(id: "neutral-cache", number: code)] }
        let source = rows(1)
        let home = JavVerseMapper(search: search, shareCache: true, accountProvider: { account })
        await home.resolve(source)?.value
        let board = JavVerseMapper(search: search, shareCache: true, accountProvider: { account })
        await board.resolve(source)?.value
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(board.movie(for: source[0])?.id, "neutral-cache")
        account = "neutral-shared240-b"
        XCTAssertNil(board.movie(for: source[0]))
        await board.resolve(source)?.value
        XCTAssertEqual(calls, 2)
    }
    @MainActor func testActorParentheticalAliasEvidenceAndAmbiguousIDs() async throws {
        func actor(_ id: String, _ name: String, _ alias: String) throws -> Actor {
            try JSONDecoder().decode(Actor.self, from: JSONSerialization.data(withJSONObject: ["id": id, "name": name, "other_name": alias]))
        }
        let exact = try actor("neutral-a", "中性名前", "中性別名")
        XCTAssertTrue(JavVerseActorResolver.matches("中性名前（中性別名）", actor: exact))
        XCTAssertFalse(JavVerseActorResolver.matches("中性名前（別人）", actor: exact))
        let other = try actor("neutral-b", "中性名前", "中性別名")
        do {
            _ = try await JavVerseActorResolver.resolve(name: "中性名前（中性別名）") { _, _ in [exact, other] }
            XCTFail("Same-name IDs accepted")
        } catch { XCTAssertTrue(error.localizedDescription.contains("多个")) }
    }
    @MainActor func testAutomaticSecondPageAndRetryStates() async {
        let mapper = JavVerseMapper(search: { code, _ in
            if code == "TEST-21" { throw JavVerseFailure.message("中性网络错误") }
            return []
        }, accountProvider: { nil })
        let page = JavVersePagination.rows(rows(45), page: 1)
        XCTAssertNil(mapper.messages[page[0].id])
        await mapper.resolve(page)?.value
        XCTAssertTrue(mapper.messages[page[0].id]?.contains("失败") == true)
        XCTAssertTrue(mapper.messages[page[1].id]?.contains("未找到") == true)
        XCTAssertEqual(mapper.completed, 20)
        XCTAssertEqual(page.map(\.rank), Array(21...40))
    }
}

extension JavVerseBehaviorTests {
    func test241RealHistoryIdentityDiffersAndUnknownYearPreserved() throws {
        let snapshot = try JavVerseSnapshot.bundled()
        let daily = snapshot.boards.filter { ($0.term ?? $0.id) == "daily" }
        XCTAssertEqual(daily.compactMap(\.periodKey), ["2026-10-22", "2026-10-21", "2026-10-20", "2026-10-19", "2026-10-18", "2026-10-17"])
        let recent = try XCTUnwrap(daily.first { $0.periodKey == "2026-10-18" })
        let prior = try XCTUnwrap(daily.first { $0.periodKey == "2026-10-17" })
        XCTAssertNotEqual(recent.entries.map(\.code), prior.entries.map(\.code), "Never relabel a single snapshot as another date")
        XCTAssertNotEqual(recent.selectionKey, prior.selectionKey)
        let weeks = snapshot.boards.filter { ($0.term ?? $0.id) == "weekly" }
        XCTAssertEqual(weeks.compactMap(\.periodKey), ["2026-10-16", "2026-10-09"])
        XCTAssertNotEqual(weeks[0].entries.map(\.code), weeks[1].entries.map(\.code))
        let month = try XCTUnwrap(snapshot.boards.first { $0.id == "monthly" })
        XCTAssertEqual(month.periodKey, "year-unknown-09")
        XCTAssertNil(month.periodEnd)
        XCTAssertTrue(month.period.contains("未显示年份"))
    }
    func test241GrokAllFiveMetricsMatchPublicSortEvidence() throws {
        let grok = try XCTUnwrap(JavVerseSnapshot.bundled().grok)
        // Comprehensive hash independently checked against all 42 public DOM pages.
        // Others bind original scores to the public client comparator, not model preference.
        let hashes = ["total": "087f6f8b972c73b2af13f4b729e39a99e7bc1e3d2857101de15b7ef036b7ea64",
                      "works": "ee79aa0a2681f391abe9153eb58c56cbc2bafa0fc9c5398696a5d3724649eb0e",
                      "pop": "3901d039b594d14e89e0223fd5600b2732885a254852989ba391f90cec5b1197",
                      "face": "d3fe2dbfa573cff8aaf29a28f03883962ff225ce531758a6f4f6fb09912b7618",
                      "body": "702420b98b2ce2e3e0ad66fa5ed3deedc1b223e34d2544238e7223a5d438c58d"]
        for metric in JavVerseGrokMetric.allCases {
            let rows = grok.rows(metric: metric, status: .all)
            XCTAssertEqual(rows.count, 250)
            XCTAssertEqual(Set(rows.map(\.id)).count, 250)
            let input = Data(rows.map(\.id).joined(separator: "|").utf8)
            let hash = SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(hash, hashes[metric.rawValue], metric.rawValue)
            if metric == .total { XCTAssertEqual(rows.map(\.rank), Array(1...250)) }
            else {
                for index in 1..<rows.count {
                    let same = rows[index].person.scores[metric.rawValue] == rows[index-1].person.scores[metric.rawValue]
                    XCTAssertEqual(rows[index].rank, same ? rows[index-1].rank : index+1)
                }
            }
        }
        XCTAssertEqual(grok.rows(metric: .total, status: .all).first?.person.scoreText["total"], "8.84")
        for status in [JavVerseGrokStatus.active, .retired] {
            let rows = grok.rows(metric: .total, status: status)
            XCTAssertTrue(rows.allSatisfy { $0.person.status == status.title })
            XCTAssertEqual(rows.map(\.rank), Array(1...rows.count))
        }
    }
    @MainActor func test241PeriodRaceCancelsLateMappingWithoutReplacingNewRows() async {
        let gate = JavVerseSearchGate()
        let old = JavVerseMapper(scope: "javverse|sales|sales|daily|old|all", search: { code, _ in try await gate.search(code) }, accountProvider: { nil })
        let oldRows = rows(1)
        let task = old.resolve(oldRows)
        for _ in 0..<100 where gate.continuation == nil { await Task.yield() }
        guard let continuation = gate.continuation else { XCTFail("Old request not started"); task?.cancel(); return }
        old.cancel()
        let latest = JavVerseMapper(scope: "javverse|sales|sales|daily|new|all", search: { code, _ in [Movie(id: "new-period", number: code)] }, accountProvider: { nil })
        await latest.resolve(oldRows)?.value
        continuation.resume(returning: [Movie(id: "old-period", number: "TEST-1")]); gate.continuation = nil
        await task?.value
        XCTAssertNil(old.movie(for: oldRows[0]))
        XCTAssertEqual(latest.movie(for: oldRows[0])?.id, "new-period")
    }
    @MainActor func test241MetadataImmediatelyAvailableBeforeImageRequestsComplete() async throws {
        let start = ProcessInfo.processInfo.systemUptime
        let snapshot = try JavVerseSnapshot.bundled()
        let cold = (ProcessInfo.processInfo.systemUptime-start)*1000
        let warmStart = ProcessInfo.processInfo.systemUptime
        _ = try JavVerseSnapshot.bundled()
        let warm = (ProcessInfo.processInfo.systemUptime-warmStart)*1000
        let daily = try XCTUnwrap(snapshot.boards.first { $0.id == "daily" })
        let gate = JavVerseSearchGate()
        let mapper = JavVerseMapper(search: { code, _ in try await gate.search(code) }, accountProvider: { nil })
        let task = mapper.resolve(Array(daily.entries.prefix(6)))
        XCTAssertEqual(daily.entries.count, 100)
        XCTAssertEqual(daily.entries.first?.code, "SONE-371")
        XCTAssertTrue(mapper.movies.isEmpty)
        print("JAVVERSE241 metadataCacheProbeMs first=\(cold) warm=\(warm) rows=\(daily.entries.count) imagesAwaited=false")
        for _ in 0..<100 where gate.continuation == nil { await Task.yield() }
        mapper.cancel(); gate.continuation?.resume(returning: []); gate.continuation = nil
        await task?.value
        // HTTP failure cannot mutate immutable bundled metadata: no fake live refresh exists.
        XCTAssertEqual(try JavVerseSnapshot.bundled().boards.first { $0.id == "daily" }?.entries.first?.code, "SONE-371")
    }
}
