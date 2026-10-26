import Foundation

// Read-only, dependency-free parser. No HTTP, account, Cookie, WebView, image or playback code.
struct DMMRankingRow: Equatable, Identifiable {
    let rank: Int
    let cid: String
    let sourceTitle: String
    let sourceURL: URL
    var id: String { "dmm|weekly|\(rank)|\(cid)" }
}
struct DMMWeeklyBoard {
    let sourceURL: URL
    let observedAt: Date
    let periodLabel = "週間"
    // The public page inspected did not expose a verified statistical date interval.
    let periodStart: Date? = nil
    let periodEnd: Date? = nil
    let rows: [DMMRankingRow]
}
struct DMMManufacturerEvidence: Equatable {
    let cid: String
    let code: String
    let sourceURL: URL
}
enum DMMRankingError: Error, Equatable {
    case unsupportedURL, accessGate, malformed, incomplete, conflictingIdentity
}
enum DMMRankingCore {
    private static func matches(_ pattern: String, _ value: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        let ns = value as NSString
        return re.matches(in: value, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
        }
    }
    private static func text(_ html: String) -> String {
        var value = html.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        // Decode only supported entities; identity fields with unknown entities fail validation.
        for (a, b) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] {
            value = value.replacingOccurrences(of: a, with: b)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func validHost(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "video.dmm.co.jp" && url.user == nil && url.password == nil && url.port == nil
    }
    private static func cid(_ value: String) -> Bool {
        value.range(of: "^[a-z0-9_]+$", options: .regularExpression) != nil && value.count <= 100
    }
    static func weekly(html: String, responseURL: URL, observedAt: Date) throws -> DMMWeeklyBoard {
        if responseURL.path.contains("age_check") || responseURL.host == "accounts.dmm.co.jp" { throw DMMRankingError.accessGate }
        guard validHost(responseURL), URLComponents(url: responseURL, resolvingAgainstBaseURL: false)?.path == "/av/ranking/",
              let parts = URLComponents(url: responseURL, resolvingAgainstBaseURL: false),
              parts.queryItems == [URLQueryItem(name: "term", value: "weekly")] else { throw DMMRankingError.unsupportedURL }
        var rows: [DMMRankingRow] = []
        for anchor in matches("<a\\b([^>]*)>(.*?)</a>", html) {
            let attrs = anchor[1], body = anchor[2]
            guard !matches("\\bdata-e2eid=[\"']title[\"']", attrs).isEmpty else { continue }
            guard let rankText = matches("<span\\b[^>]*>\\s*([0-9]+)位\\s*</span>", body).first?[1],
                  let rank = Int(rankText),
                  let href = matches("\\bhref=[\"']([^\"']+)[\"']", attrs).first?[1],
                  let url = URL(string: text(href), relativeTo: responseURL)?.absoluteURL,
                  validHost(url), URLComponents(url: url, resolvingAgainstBaseURL: false)?.path == "/av/content/",
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let ids = components.queryItems?.filter({ $0.name == "id" }), ids.count == 1,
                  let id = ids[0].value, cid(id),
                  let titleHTML = matches("<p\\b[^>]*>(.*?)</p>", body).first?[1] else { throw DMMRankingError.malformed }
            let title = text(titleHTML)
            guard !title.isEmpty else { throw DMMRankingError.malformed }
            // cid is a source identity only; never a JavDB/AVDB movie ID.
            let canonical = URL(string: "https://video.dmm.co.jp/av/content/?id=\(id)")!
            rows.append(DMMRankingRow(rank: rank, cid: id, sourceTitle: title, sourceURL: canonical))
        }
        guard !rows.isEmpty else { throw DMMRankingError.accessGate }
        // Observed weekly board is 100 entries in one document; never invent next-page URLs.
        guard rows.map(\.rank) == Array(1...100) else { throw DMMRankingError.incomplete }
        return DMMWeeklyBoard(sourceURL: responseURL, observedAt: observedAt, rows: rows)
    }
    static func manufacturer(html: String, responseURL: URL, expectedCID: String) throws -> DMMManufacturerEvidence {
        if responseURL.path.contains("age_check") || responseURL.host == "accounts.dmm.co.jp" { throw DMMRankingError.accessGate }
        guard validHost(responseURL), URLComponents(url: responseURL, resolvingAgainstBaseURL: false)?.path == "/av/content/", cid(expectedCID),
              let parts = URLComponents(url: responseURL, resolvingAgainstBaseURL: false),
              parts.queryItems?.filter({ $0.name == "id" }).map(\.value) == [expectedCID] else { throw DMMRankingError.unsupportedURL }
        var fields: [String: Set<String>] = [:]
        for row in matches("<tr\\b[^>]*>(.*?)</tr>", html) {
            guard let label = matches("<th\\b[^>]*>(.*?)</th>", row[1]).first?[1],
                  let value = matches("<td\\b[^>]*>(.*?)</td>", row[1]).first?[1] else { continue }
            fields[text(label), default: []].insert(text(value))
        }
        guard fields["配信品番"] == Set([expectedCID]), let values = fields["メーカー品番"], values.count == 1,
              let raw = values.first else { throw DMMRankingError.conflictingIdentity }
        let code = raw.uppercased()
        guard code.unicodeScalars.allSatisfy({ $0.isASCII }),
              code.range(of: "^[A-Z0-9]+-[A-Z0-9]+$", options: .regularExpression) != nil else { throw DMMRankingError.conflictingIdentity }
        // Preserve every digit and suffix. No CID prefix stripping, zero removal or guessed aliases.
        return DMMManufacturerEvidence(cid: expectedCID, code: code, sourceURL: responseURL)
    }
}
