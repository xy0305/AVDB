import XCTest
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
        for (key, value) in [("schemaVersion", 2 as Any), ("mode", "live" as Any),
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
        XCTAssertEqual(snapshot.boards.count, 7)
        XCTAssertEqual(snapshot.boards.reduce(0) { $0 + $1.entries.count }, 520)
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
    @MainActor func testManualBatchIsSerialAndLimitedToFour() async {
        var calls: [String] = []
        let mapper = JavVerseMapper(search: { code, _ in
            calls.append(code); return [Movie(id: "id-\(code)", number: code)]
        }, accountProvider: { "neutral-account" })
        let entries = rows(8)
        let task = mapper.resolve(entries)
        XCTAssertTrue(mapper.busy)
        XCTAssertNil(mapper.resolve(entries), "Busy guard must reject concurrent manual batches")
        await task?.value
        XCTAssertEqual(calls, ["TEST-1", "TEST-2", "TEST-3", "TEST-4"])
        XCTAssertEqual(mapper.movies.count, 4)
        XCTAssertFalse(mapper.busy)
        XCTAssertEqual(entries.map(\.rank), Array(1...8))
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
