import Foundation

// Read-only, dependency-free parser. No HTTP, account, Cookie, WebView, image or playback code.
// Official video.dmm.co.jp/av/ranking query space (observed 2026-10-27 JS allowlist):
//   content: term=daily|weekly|monthly  (expected rows 20/100/100)
//   actress: term=monthly&type=actress  (expected rows 100; actress boards are monthly-only)

enum DMMRankingKind: String, CaseIterable, Identifiable, Sendable {
    case daily, weekly, monthly, actress
    var id: String { rawValue }
    var periodLabel: String {
        switch self {
        case .daily: return "日間"
        case .weekly: return "週間"
        case .monthly: return "月間"
        case .actress: return "月間女優"
        }
    }
    /// Official page sizes from ranking JS (`Unsupported ranking page type` table).
    var expectedCount: Int {
        switch self {
        case .daily: return 20
        case .weekly, .monthly, .actress: return 100
        }
    }
    var isActress: Bool { self == .actress }
    var sourceURL: URL {
        switch self {
        case .daily: return URL(string: "https://video.dmm.co.jp/av/ranking/?term=daily")!
        case .weekly: return URL(string: "https://video.dmm.co.jp/av/ranking/?term=weekly")!
        case .monthly: return URL(string: "https://video.dmm.co.jp/av/ranking/?term=monthly")!
        case .actress: return URL(string: "https://video.dmm.co.jp/av/ranking/?term=monthly&type=actress")!
        }
    }
    static func from(url: URL) -> DMMRankingKind? {
        guard DMMRankingCore.validRankingHost(url),
              URLComponents(url: url, resolvingAgainstBaseURL: false)?.path == "/av/ranking/",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        let map = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (String, String)? in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })
        if map.keys.sorted() == ["term"], let term = map["term"] {
            switch term {
            case "daily": return .daily
            case "weekly": return .weekly
            case "monthly": return .monthly
            default: return nil
            }
        }
        if map.keys.sorted() == ["term", "type"], map["term"] == "monthly", map["type"] == "actress" {
            return .actress
        }
        return nil
    }
}

struct DMMContentRow: Equatable, Identifiable, Sendable {
    let rank: Int
    let cid: String
    let sourceTitle: String
    let sourceURL: URL
    let kind: DMMRankingKind
    var id: String { "dmm|\(kind.rawValue)|\(rank)|\(cid)" }
}

struct DMMActressRow: Equatable, Identifiable, Sendable {
    let rank: Int
    let actressID: String
    let name: String
    let sourceURL: URL
    var id: String { "dmm|actress|\(rank)|\(actressID)" }
}

struct DMMRankingBoard: Sendable {
    let kind: DMMRankingKind
    let sourceURL: URL
    let observedAt: Date
    // Public ranking pages inspected do not expose a verified statistical date interval.
    let periodStart: Date? = nil
    let periodEnd: Date? = nil
    let contentRows: [DMMContentRow]
    let actressRows: [DMMActressRow]
    var periodLabel: String { kind.periodLabel }
    var count: Int { kind.isActress ? actressRows.count : contentRows.count }
}

struct DMMManufacturerEvidence: Equatable, Sendable {
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
        for (a, b) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] {
            value = value.replacingOccurrences(of: a, with: b)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func validRankingHost(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "video.dmm.co.jp" && url.user == nil && url.password == nil && url.port == nil
    }
    private static func cid(_ value: String) -> Bool {
        value.range(of: "^[a-z0-9_]+$", options: .regularExpression) != nil && value.count <= 100
    }
    private static func actressID(_ value: String) -> Bool {
        value.range(of: "^[0-9]+$", options: .regularExpression) != nil && value.count <= 20
    }

    /// Parses a content or actress ranking document. Kind must match responseURL.
    static func board(html: String, responseURL: URL, observedAt: Date) throws -> DMMRankingBoard {
        if responseURL.path.contains("age_check") || responseURL.host == "accounts.dmm.co.jp" { throw DMMRankingError.accessGate }
        guard let kind = DMMRankingKind.from(url: responseURL) else { throw DMMRankingError.unsupportedURL }
        if kind.isActress {
            return try actressBoard(html: html, responseURL: responseURL, kind: kind, observedAt: observedAt)
        }
        return try contentBoard(html: html, responseURL: responseURL, kind: kind, observedAt: observedAt)
    }

    /// Compatibility alias used by older call sites / fixtures targeting weekly.
    static func weekly(html: String, responseURL: URL, observedAt: Date) throws -> DMMRankingBoard {
        let board = try board(html: html, responseURL: responseURL, observedAt: observedAt)
        guard board.kind == .weekly else { throw DMMRankingError.unsupportedURL }
        return board
    }

    private static func contentBoard(html: String, responseURL: URL, kind: DMMRankingKind, observedAt: Date) throws -> DMMRankingBoard {
        var rows: [DMMContentRow] = []
        for anchor in matches("<a\\b([^>]*)>(.*?)</a>", html) {
            let attrs = anchor[1], body = anchor[2]
            guard !matches("\\bdata-e2eid=[\"']title[\"']", attrs).isEmpty else { continue }
            guard let rankText = matches("<span\\b[^>]*>\\s*([0-9]+)位\\s*</span>", body).first?[1],
                  let rank = Int(rankText),
                  let href = matches("\\bhref=[\"']([^\"']+)[\"']", attrs).first?[1],
                  let url = URL(string: text(href), relativeTo: responseURL)?.absoluteURL,
                  validRankingHost(url), URLComponents(url: url, resolvingAgainstBaseURL: false)?.path == "/av/content/",
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let ids = components.queryItems?.filter({ $0.name == "id" }), ids.count == 1,
                  let id = ids[0].value, cid(id),
                  let titleHTML = matches("<p\\b[^>]*>(.*?)</p>", body).first?[1] else { throw DMMRankingError.malformed }
            let title = text(titleHTML)
            guard !title.isEmpty else { throw DMMRankingError.malformed }
            let canonical = URL(string: "https://video.dmm.co.jp/av/content/?id=\(id)")!
            rows.append(DMMContentRow(rank: rank, cid: id, sourceTitle: title, sourceURL: canonical, kind: kind))
        }
        guard !rows.isEmpty else { throw DMMRankingError.accessGate }
        // Observed content boards are a single document; never invent next-page URLs.
        guard rows.map(\.rank) == Array(1...kind.expectedCount) else { throw DMMRankingError.incomplete }
        return DMMRankingBoard(kind: kind, sourceURL: responseURL, observedAt: observedAt, contentRows: rows, actressRows: [])
    }

    private static func actressBoard(html: String, responseURL: URL, kind: DMMRankingKind, observedAt: Date) throws -> DMMRankingBoard {
        // Browser-rendered actress cards: rank "N位" beside links to /av/list/?actress=<numeric-id>.
        // Image and name both link; one row per rank; fail closed on identity conflicts.
        struct Partial { var actressID: String?; var name: String?; var sourceURL: URL? }
        var byRank: [Int: Partial] = [:]
        var cursor = html.startIndex
        for anchor in matches("<a\\b([^>]*)>(.*?)</a>", html) {
            let attrs = anchor[1], body = anchor[2]
            guard let href = matches("\\bhref=[\"']([^\"']+)[\"']", attrs).first?[1],
                  let url = URL(string: text(href), relativeTo: responseURL)?.absoluteURL,
                  validRankingHost(url),
                  URLComponents(url: url, resolvingAgainstBaseURL: false)?.path == "/av/list/",
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let actressItems = components.queryItems?.filter({ $0.name == "actress" }), actressItems.count == 1,
                  let rawID = actressItems[0].value, actressID(rawID) else { continue }
            let found = html.range(of: href, range: cursor..<html.endIndex) ?? html.range(of: href)
            guard let hrefRange = found else { continue }
            cursor = hrefRange.upperBound
            let prefix = String(html[..<hrefRange.lowerBound])
            guard let rankMatch = matches("([0-9]+)(?:<[^>]*>|\\s)*位", String(prefix.suffix(500))).last,
                  let rank = Int(rankMatch[1]), rank >= 1, rank <= kind.expectedCount else { throw DMMRankingError.malformed }
            let name = text(body)
            var partial = byRank[rank] ?? Partial()
            if let existing = partial.actressID, existing != rawID { throw DMMRankingError.conflictingIdentity }
            partial.actressID = rawID
            partial.sourceURL = URL(string: "https://video.dmm.co.jp/av/list/?actress=\(rawID)")!
            if !name.isEmpty {
                if let existing = partial.name, existing != name { throw DMMRankingError.conflictingIdentity }
                partial.name = name
            }
            byRank[rank] = partial
        }
        var rows: [DMMActressRow] = []
        for rank in 1...kind.expectedCount {
            guard let partial = byRank[rank], let id = partial.actressID, let name = partial.name, let url = partial.sourceURL, !name.isEmpty else {
                throw DMMRankingError.incomplete
            }
            rows.append(DMMActressRow(rank: rank, actressID: id, name: name, sourceURL: url))
        }
        guard Set(rows.map(\.actressID)).count == rows.count else { throw DMMRankingError.conflictingIdentity }
        return DMMRankingBoard(kind: kind, sourceURL: responseURL, observedAt: observedAt, contentRows: [], actressRows: rows)
    }

    static func manufacturer(html: String, responseURL: URL, expectedCID: String) throws -> DMMManufacturerEvidence {
        if responseURL.path.contains("age_check") || responseURL.host == "accounts.dmm.co.jp" { throw DMMRankingError.accessGate }
        guard validRankingHost(responseURL), URLComponents(url: responseURL, resolvingAgainstBaseURL: false)?.path == "/av/content/", cid(expectedCID),
              let parts = URLComponents(url: responseURL, resolvingAgainstBaseURL: false),
              parts.queryItems?.filter({ $0.name == "id" }).map(\.value) == [expectedCID] else { throw DMMRankingError.unsupportedURL }
        var fields: [String: Set<String>] = [:]
        for row in matches("<tr\\b[^>]*>(.*?)</tr>", html) {
            guard let label = matches("<th\\b[^>]*>(.*?)</th>", row[1]).first?[1],
                  let value = matches("<td\\b[^>]*>(.*?)</td>", row[1]).first?[1] else { continue }
            fields[text(label), default: []].insert(text(value))
        }
        guard fields["配信品番"] == Set([expectedCID]), let values = fields["メーカー品番"], values.count == 1,
              let raw = values.first, let code = manufacturerCode(raw) else { throw DMMRankingError.conflictingIdentity }
        // Preserve every digit and suffix. No CID prefix stripping, zero removal or guessed aliases.
        return DMMManufacturerEvidence(cid: expectedCID, code: code, sourceURL: responseURL)
    }

    /// Official メーカー品番 / GraphQL makerContentId only. Never derived from CID.
    static func manufacturerCode(_ raw: String) -> String? {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty, code.unicodeScalars.allSatisfy({ $0.isASCII }),
              code.range(of: "^[A-Z0-9]+-[A-Z0-9]+$", options: .regularExpression) != nil else { return nil }
        return code
    }
}
