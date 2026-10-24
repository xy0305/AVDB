import Foundation

// Internal injectable boundary: production still uses ONLY the existing AVDB movie SDK.
// MainActor matches JavDBSDK.shared; no detached tasks or cross-actor Movie transfer.
@MainActor enum JavVerseMovieResolver {
    typealias Search = @MainActor (String, Int) async throws -> [Movie]
    static func resolve(code source: String, search: Search) async throws -> Movie? {
        guard let key = JavVerseIdentity.code(source) else {
            throw JavVerseFailure.message("原始完整番号不可核验")
        }
        var matches: [String: Movie] = [:]
        var exhausted = false
        for page in 1...3 {
            try Task.checkCancellation()
            let rows = try await search(source, page)
            try Task.checkCancellation()
            for row in rows where JavVerseIdentity.code(row.number ?? "") == key {
                let id = row.id.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty, id == row.id else { continue }
                matches[id] = row
            }
            guard matches.count <= 1 else {
                throw JavVerseFailure.message("番号对应多个 AVDB ID；拒绝自动选择")
            }
            if rows.count < 20 { exhausted = true; break }
        }
        guard exhausted else {
            throw JavVerseFailure.message("搜索超过3页，核验范围不完整；未自动匹配")
        }
        return matches.values.first
    }
}

// External ranking names stay visible. AVDB navigation requires one exact identity.
@MainActor enum JavVerseActorResolver {
    typealias Search = @MainActor (String, Int) async throws -> [Actor]
    static func names(_ raw: String) -> Set<String> {
        let separators = CharacterSet(charactersIn: "()（）,，、/／;；\n")
        return Set(raw.components(separatedBy: separators).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }
    static func identity(name: String, aliases: [String] = [], catalog: ActorAliasCatalog = .bundled()) -> ExternalActorIdentity {
        ExternalActorIdentity.resolve(sourceName: name, aliases: aliases, catalog: catalog)
    }
    static func matches(_ source: String, actor: Actor) -> Bool {
        ExternalActorResolver.match(identity(name: source), actor: actor)
    }
    static func resolve(name: String, aliases: [String] = [], catalog: ActorAliasCatalog = .bundled(), search: Search) async throws -> Actor? {
        let identity = identity(name: name, aliases: aliases, catalog: catalog)
        switch try await ExternalActorResolver.inspect(identity: identity, search: search, queryLimit: 12) {
        case .matched(let match): return match.actor
        case .notFound: return nil
        case .ambiguous(let candidates): throw ExternalActorResolver.Failure.ambiguous(candidates)
        case .incomplete(let candidates, _): throw ExternalActorResolver.Failure.incomplete(candidates)
        }
    }
}

// Source order is never sorted by AVDB match status; pagination cannot backfill holes.
enum JavVersePagination {
    static let size = 20
    static func count(_ entries: [JavVerseEntry]) -> Int { max(1, (entries.count + size - 1) / size) }
    static func rows(_ entries: [JavVerseEntry], page: Int) -> [JavVerseEntry] {
        guard page >= 0, page < count(entries) else { return [] }
        return Array(entries.dropFirst(page * size).prefix(size))
    }
}

#if DEBUG
import UIKit
// Explicit UI-test-only, fabricated neutral data. Never presented as a source capture.
enum JavVerseNeutralFixture {
    @MainActor static var artwork: UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 90, height: 120)).image { context in
            UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 90, height: 120))
            ("NEUTRAL\n240" as NSString).draw(in: CGRect(x: 10, y: 40, width: 75, height: 60), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 14), .foregroundColor: UIColor.white])
        }
    }
    @MainActor static func mapper() -> JavVerseMapper {
        JavVerseMapper(search: { code, _ in
            [Movie(id: "neutral-\(code)", number: code)]
        }, actorSearch: { name, _ in
            let json: [String: String] = ["id": "neutral-\(name)", "name": name]
            return [try JSONDecoder().decode(Actor.self, from: JSONSerialization.data(withJSONObject: json))]
        }, shareCache: false, accountProvider: { nil })
    }
    static func snapshot() throws -> JavVerseSnapshot {
        let date = "2026-10-23T17:29:00Z"
        let boards: [[String: Any]] = [("featured", "中性演员测试", 8, "actor"),
                                       ("recent", "中性最近测试", 12, "movie"),
                                       ("daily", "中性分页测试", 45, "movie")].map { id, title, count, kind in
            let rows: [[String: Any]] = (1...count).map { rank in
                var row: [String: Any] = ["rank": rank, "kind": kind,
                    "label": kind == "movie" ? "TEST-\(String(format: "%03d", rank))" : "中性演员\(rank)",
                    "sourceURL": "https://javverse.com/neutral-test/\(rank)"]
                if kind == "movie" { row["code"] = row["label"] }
                return row
            }
            return ["id": id, "title": title, "period": "中性夹具 · 非原站采集 · 年份未公布",
                    "capturedAt": date, "sourceURL": "https://javverse.com/neutral-test",
                    "coverage": "complete", "entries": rows]
        }
        var value: [String: Any] = ["schemaVersion": 2, "mode": "staticSnapshot",
            "origin": "https://javverse.com", "preparedAt": date, "boards": boards]
        var expanded = boards
        // Distinct fabricated periods test selection; never represented as source evidence.
        for (id, term, key, code) in [("daily-old", "daily", "neutral-previous-day", "PAST"),
                                      ("weekly", "weekly", "neutral-week-current", "WEEK"),
                                      ("weekly-old", "weekly", "neutral-week-previous", "OLDWEEK"),
                                      ("monthly", "monthly", "unknown-year", "MONTH")] {
            var board = boards[2]
            board["id"] = id; board["term"] = term; board["periodKey"] = key
            board["selectionTitle"] = key; board["period"] = key
            board["entries"] = (1...45).map { rank -> [String: Any] in
                let label = "\(code)-\(String(format: "%03d", rank))"
                return ["rank": rank, "kind": "movie", "label": label, "code": label,
                        "sourceURL": "https://javverse.com/neutral-test/\(id)/\(rank)"]
            }
            expanded.append(board)
        }
        value["boards"] = expanded
        let people: [[String: Any]] = (1...250).map { index in
            let name = String(format: "中性演员%03d", index)
            let scores = ["total": 10000-index, "works": 9000-index/2, "pop": 8000-index,
                          "face": 7000+index, "body": 6000+index, "award": 5000, "years": 4000]
            let texts = scores.mapValues { String(format: "%.2f", Double($0)/1000) }
            return ["id": "neutral-\(index)", "nameJa": name, "nameZh": name,
                    "years": "年份未公布", "status": index % 2 == 0 ? "现役" : "引退",
                    "scores": scores, "scoreText": texts, "actressId": index]
        }
        value["grok"] = ["capturedAt": date, "sourceURL": "https://javverse.com/neutral-test",
                         "sortEvidence": "fabricated neutral UI fixture only", "people": people]
        return try JavVerseSnapshot.decode(JSONSerialization.data(withJSONObject: value))
    }
}
#endif
