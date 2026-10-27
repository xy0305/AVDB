import Foundation
@main struct DMMLiveProbe {
    static func main() async {
        // Explicitly authorized adult self-declaration; isolated anonymous source session.
        let transport = DMMTransport()
        var anyVerified = false
        for kind in DMMRankingKind.allCases {
            do {
                let (html, finalURL) = try await transport.document(kind.sourceURL, authorizeAdultDeclaration: true)
                let board = try DMMRankingCore.board(html: html, responseURL: finalURL, observedAt: Date())
                print("LIVE_\(kind.rawValue.uppercased())_VERIFIED rows=\(board.count)")
                anyVerified = true
                if let row = board.contentRows.first {
                    let (detail, responseURL) = try await transport.document(row.sourceURL, authorizeAdultDeclaration: true)
                    let evidence = try DMMRankingCore.manufacturer(html: detail, responseURL: responseURL, expectedCID: row.cid)
                    print("LIVE_MANUFACTURER_VERIFIED cid=\(evidence.cid) code=\(evidence.code)")
                }
            } catch {
                print("LIVE_\(kind.rawValue.uppercased())_BLOCKED: official flow or ranking/detail integrity unavailable; keep HTML preview.")
            }
        }
        if !anyVerified {
            print("LIVE_BLOCKED: official flow or ranking/detail integrity unavailable; keep HTML preview. No credentials, browser session, KYC or region bypass attempted.")
        }
        await transport.clear()
    }
}
