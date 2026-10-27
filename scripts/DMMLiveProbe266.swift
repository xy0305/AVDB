import Foundation
@main struct DMMLiveProbe {
    static func main() async {
        // Explicitly authorized adult self-declaration; isolated anonymous source session.
        let transport = DMMTransport()
        var anyVerified = false
        for kind in DMMRankingKind.allCases {
            // Secondary path first in CI (no WKWebView): verified GraphQL.
            do {
                let board = try await DMMRankingGraphQL.fetch(kind)
                print("LIVE_GRAPHQL_\(kind.rawValue.uppercased())_VERIFIED rows=\(board.count)")
                anyVerified = true
            } catch {
                print("LIVE_GRAPHQL_\(kind.rawValue.uppercased())_BLOCKED: verified query unavailable or incomplete; keep fail-closed.")
            }
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
                print("LIVE_\(kind.rawValue.uppercased())_BLOCKED: official URLSession document is shell/incomplete; WebView hydrate is the primary in-app path.")
            }
        }
        if !anyVerified {
            print("LIVE_BLOCKED: GraphQL and URLSession document unavailable; keep HTML preview. No credentials, Safari session, KYC or region bypass attempted.")
        }
        await transport.clear()
    }
}
