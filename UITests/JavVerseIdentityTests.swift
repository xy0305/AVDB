import XCTest
@testable import AVDB

final class JavVerseIdentityTests: XCTestCase {
    func testFullNumberNeverDropsZeroOrSuffix() {
        XCTAssertEqual(JavVerseIdentity.code(" test-001v \n"), "TEST-001V")
        XCTAssertNotEqual(JavVerseIdentity.code("TEST-001"), JavVerseIdentity.code("TEST-1"))
        XCTAssertNotEqual(JavVerseIdentity.code("TEST-001V"), JavVerseIdentity.code("TEST-001"))
        XCTAssertNil(JavVerseIdentity.code("3248"))
        XCTAssertNil(JavVerseIdentity.code("TEST 001"))
        XCTAssertNil(JavVerseIdentity.code("TEßT-001"))
        XCTAssertNil(JavVerseIdentity.code("ＴＥＳＴ-001"))
    }
    func testNeutralSourceIDIsNotAnAVDBID() throws {
        let json = #"{"rank":8,"kind":"movie","label":"TEST-001V","sourceURL":"https://javverse.com/work/3248","code":"TEST-001V"}"#
        let row = try JSONDecoder().decode(JavVerseEntry.self, from: Data(json.utf8))
        XCTAssertEqual(row.rank, 8)
        XCTAssertNotEqual(row.id, "3248")
        XCTAssertEqual(row.code, "TEST-001V")
    }
    func testNeutralSnapshotTimestampAndUnknownPeriod() throws {
        let json = #"{"id":"neutral","title":"中性名单","period":"原站未公布年份","capturedAt":"2026-10-23T17:29:00Z","sourceURL":"https://javverse.com/rankings","coverage":"complete","entries":[]}"#
        let board = try JSONDecoder().decode(JavVerseBoard.self, from: Data(json.utf8))
        XCTAssertEqual(board.period, "原站未公布年份")
        XCTAssertEqual(board.capturedAt, "2026-10-23T17:29:00Z")
    }
}
