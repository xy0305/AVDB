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
// Explicit UI-test-only, fabricated neutral data. Never presented as a source capture.
enum JavVerseNeutralFixture {
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
        let value: [String: Any] = ["schemaVersion": 1, "mode": "staticSnapshot",
            "origin": "https://javverse.com", "preparedAt": date, "boards": boards]
        return try JavVerseSnapshot.decode(JSONSerialization.data(withJSONObject: value))
    }
}
#endif
