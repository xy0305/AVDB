import Foundation

@main struct DMMRankingRegression {
    static func main() throws {
        let base = URL(fileURLWithPath: CommandLine.arguments[1])
        func read(_ name: String) throws -> String { try String(contentsOf: base.appendingPathComponent(name), encoding: .utf8) }
        func fails(_ expected: DMMRankingError, _ action: () throws -> Void) {
            do { try action(); preconditionFailure("Expected rejection") }
            catch { precondition(error as? DMMRankingError == expected, "got \(error)") }
        }

        // Content: daily 20 / weekly 100 / monthly 100
        for (file, kind) in [("daily-neutral.html", DMMRankingKind.daily), ("weekly-neutral.html", .weekly), ("monthly-neutral.html", .monthly)] {
            let url = kind.sourceURL
            let html = try read(file)
            let board = try DMMRankingCore.board(html: html, responseURL: url, observedAt: Date(timeIntervalSince1970: 0))
            precondition(board.kind == kind)
            precondition(board.contentRows.count == kind.expectedCount)
            precondition(board.contentRows.map(\.rank) == Array(1...kind.expectedCount))
            precondition(board.actressRows.isEmpty)
            precondition(board.periodStart == nil && board.periodEnd == nil)
            fails(.incomplete) {
                let broken = html.replacingOccurrences(of: "\(kind.expectedCount)位", with: "\(kind.expectedCount - 1)位")
                _ = try DMMRankingCore.board(html: broken, responseURL: url, observedAt: Date())
            }
            fails(.unsupportedURL) {
                _ = try DMMRankingCore.board(html: html, responseURL: URL(string: url.absoluteString + "&page=2")!, observedAt: Date())
            }
        }

        // Actress monthly-only board: 100 numeric actress ids + names; no invented AVDB ids.
        let actressURL = DMMRankingKind.actress.sourceURL
        let actressHTML = try read("actress-monthly-neutral.html")
        let actress = try DMMRankingCore.board(html: actressHTML, responseURL: actressURL, observedAt: Date(timeIntervalSince1970: 0))
        precondition(actress.kind == .actress)
        precondition(actress.actressRows.count == 100 && actress.contentRows.isEmpty)
        precondition(actress.actressRows.first?.actressID == "900001")
        precondition(actress.actressRows.first?.name == "Neutral Actress 1")
        precondition(actress.actressRows.last?.rank == 100)
        fails(.incomplete) {
            // Real DOM is "100</span>位"; drop the last card entirely to violate 1...100 continuum.
            let truncated = actressHTML.replacingOccurrences(of: "Neutral Actress 100", with: "")
                .replacingOccurrences(of: "actress=900100", with: "actress=900099")
            _ = try DMMRankingCore.board(html: truncated, responseURL: actressURL, observedAt: Date())
        }
        fails(.unsupportedURL) {
            // Actress boards are monthly-only in official routing.
            _ = try DMMRankingCore.board(html: actressHTML, responseURL: URL(string: "https://video.dmm.co.jp/av/ranking/?term=weekly&type=actress")!, observedAt: Date())
        }
        fails(.accessGate) { _ = try DMMRankingCore.board(html: "", responseURL: URL(string: "https://www.dmm.co.jp/age_check/=/")!, observedAt: Date()) }

        let weeklyURL = DMMRankingKind.weekly.sourceURL
        let weeklyHTML = try read("weekly-neutral.html")
        for (cid, code) in [("ssis00760", "SSIS-760"), ("1sdnm00554", "SDNM-554"), ("h_1758jjgg00009", "JJGG-009"), ("snos00489", "SNOS-489")] {
            let source = URL(string: "https://video.dmm.co.jp/av/content/?id=\(cid)")!
            let detail = try read("detail-\(cid).html")
            let evidence = try DMMRankingCore.manufacturer(html: detail, responseURL: source, expectedCID: cid)
            precondition(evidence.code == code)
            fails(.conflictingIdentity) { _ = try DMMRankingCore.manufacturer(html: detail.replacingOccurrences(of: "配信品番", with: "other"), responseURL: source, expectedCID: cid) }
            fails(.conflictingIdentity) { _ = try DMMRankingCore.manufacturer(html: detail + "<tr><th>メーカー品番</th><td>OTHER-999</td></tr>", responseURL: source, expectedCID: cid) }
        }
        // Same CID at another real rank must remain a separate source row; no dedup by work/version.
        let duplicates = weeklyHTML.replacingOccurrences(of: "sone00269", with: "mfyd00204")
        let duplicateBoard = try DMMRankingCore.board(html: duplicates, responseURL: weeklyURL, observedAt: Date())
        precondition(duplicateBoard.contentRows.count == 100)

        // Kind URL recognition
        precondition(DMMRankingKind.from(url: DMMRankingKind.daily.sourceURL) == .daily)
        precondition(DMMRankingKind.from(url: DMMRankingKind.actress.sourceURL) == .actress)
        precondition(DMMRankingKind.from(url: URL(string: "https://video.dmm.co.jp/av/ranking/?term=realtime")!) == nil)

        print("PASS: daily20/weekly100/monthly100 content, actress100 monthly-only, period unknown, gates, unsupported paging/terms, manufacturer examples, conflicts, duplicate source rows")
    }
}
