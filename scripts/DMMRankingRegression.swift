import Foundation

@main struct DMMRankingRegression {
    static func main() throws {
        let base = URL(fileURLWithPath: CommandLine.arguments[1])
        func read(_ name: String) throws -> String { try String(contentsOf: base.appendingPathComponent(name), encoding: .utf8) }
        let weeklyURL = URL(string: "https://video.dmm.co.jp/av/ranking/?term=weekly")!
        let html = try read("weekly-neutral.html")
        let board = try DMMRankingCore.weekly(html: html, responseURL: weeklyURL, observedAt: Date(timeIntervalSince1970: 0))
        precondition(board.rows.count == 100 && board.rows.last?.rank == 100)
        precondition(board.periodStart == nil && board.periodEnd == nil)
        func fails(_ expected: DMMRankingError, _ action: () throws -> Void) {
            do { try action(); preconditionFailure("Expected rejection") }
            catch { precondition(error as? DMMRankingError == expected) }
        }
        fails(.incomplete) { _ = try DMMRankingCore.weekly(html: html.replacingOccurrences(of: "100位", with: "99位"), responseURL: weeklyURL, observedAt: Date()) }
        fails(.unsupportedURL) { _ = try DMMRankingCore.weekly(html: html, responseURL: URL(string: "https://video.dmm.co.jp/av/ranking/?term=weekly&page=2")!, observedAt: Date()) }
        fails(.accessGate) { _ = try DMMRankingCore.weekly(html: "", responseURL: URL(string: "https://www.dmm.co.jp/age_check/=/")!, observedAt: Date()) }
        for (cid, code) in [("ssis00760", "SSIS-760"), ("1sdnm00554", "SDNM-554"), ("h_1758jjgg00009", "JJGG-009"), ("snos00489", "SNOS-489")] {
            let source = URL(string: "https://video.dmm.co.jp/av/content/?id=\(cid)")!
            let detail = try read("detail-\(cid).html")
            let evidence = try DMMRankingCore.manufacturer(html: detail, responseURL: source, expectedCID: cid)
            precondition(evidence.code == code)
            fails(.conflictingIdentity) { _ = try DMMRankingCore.manufacturer(html: detail.replacingOccurrences(of: "配信品番", with: "other"), responseURL: source, expectedCID: cid) }
            fails(.conflictingIdentity) { _ = try DMMRankingCore.manufacturer(html: detail + "<tr><th>メーカー品番</th><td>OTHER-999</td></tr>", responseURL: source, expectedCID: cid) }
        }
        // Same CID at another real rank must remain a separate source row; no dedup by work/version.
        let duplicates = html.replacingOccurrences(of: "sone00269", with: "mfyd00204")
        let duplicateBoard = try DMMRankingCore.weekly(html: duplicates, responseURL: weeklyURL, observedAt: Date())
        precondition(duplicateBoard.rows.count == 100)
        print("PASS: full ranking, period unknown, gates, unsupported paging, four authoritative manufacturer examples, conflicts, duplicate source rows")
    }
}
