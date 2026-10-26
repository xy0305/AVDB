import Foundation
@main struct DMMLiveProbe {
    static func main() async {
        // Explicitly authorized adult self-declaration; isolated anonymous source session.
        let transport = DMMTransport()
        let url = URL(string: "https://video.dmm.co.jp/av/ranking/?term=weekly")!
        do {
            let (html, finalURL) = try await transport.document(url, authorizeAdultDeclaration: true)
            let board = try DMMRankingCore.weekly(html: html, responseURL: finalURL, observedAt: Date())
            print("LIVE_WEEKLY_VERIFIED rows=\(board.rows.count)")
            if let row = board.rows.first {
                let (detail, responseURL) = try await transport.document(row.sourceURL, authorizeAdultDeclaration: true)
                let evidence = try DMMRankingCore.manufacturer(html: detail, responseURL: responseURL, expectedCID: row.cid)
                print("LIVE_MANUFACTURER_VERIFIED cid=\(evidence.cid) code=\(evidence.code)")
            }
        } catch {
            print("LIVE_BLOCKED: official flow or ranking/detail integrity unavailable; keep HTML preview. No credentials, browser session, KYC or region bypass attempted.")
        }
        await transport.clear()
    }
}
