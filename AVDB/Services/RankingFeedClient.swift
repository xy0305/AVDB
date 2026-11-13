import Foundation
import Combine
import SwiftUI

// Build 349: server-side pre-matching feed for the five ranking boards.
// The VPS pipeline (pipeline.py) resolves source codes to JavDB identities
// once a day and publishes one JSON per board/term on the repo's `feed`
// branch. The app reads the feed first and pre-fills the boards' existing
// result tables; anything the feed does not cover — entries missing from
// the feed, a feed that cannot be fetched, or a feed older than 48 hours —
// falls back to the existing on-device verification (VerificationThrottle),
// which stays fully in place. Feed entries the server marked `ambiguous`
// are fail-closed: shown as unmatched and never re-resolved automatically.
// Entries marked pending (server daily budget ran out) are not seeded at
// all, so the device fallback owns them until the server catches up.
//
// File naming follows pipeline.py write_feed: "<board>-<term>.json".
//   dmm:          daily | weekly | monthly | actress
//   javranking:   explore
//   missav:       today-hot | weekly-hot | monthly-hot
//   zhongzhitong: YYYY-MM (one file per month)
//   javlibrary:   mostwanted | bestrated | actors
struct RankingFeedMatch: Decodable {
    let status: String
    let javdbID: String?
    let number: String?
    let title: String?
    let cover: String?
    let thumb: String?
    let releaseDate: String?
    let score: Double?
    let name: String?
    let avatar: String?
    let pending: Bool?
    enum CodingKeys: String, CodingKey {
        case status, number, title, cover, thumb, score, name, avatar, pending
        case javdbID = "javdb_id"
        case releaseDate = "release_date"
    }
    var isMatched: Bool { status == "matched" && (javdbID?.isEmpty == false) }
}

struct RankingFeedEntry: Decodable, Identifiable {
    let rank: Int
    let code: String?
    let label: String?
    let name: String?
    let aliases: [String]?
    let actresses: [String]?
    let sourceURL: String?
    let match: RankingFeedMatch
    var id: String { "\(rank)|\(code ?? name ?? "")|\(sourceURL ?? "")" }
    enum CodingKeys: String, CodingKey {
        case rank, code, label, name, aliases, actresses, match
        case sourceURL = "source_url"
    }
    /// The matched JavDB movie, built from the feed's own display fields.
    func makeMovie() -> Movie? {
        guard match.isMatched, let jid = match.javdbID else { return nil }
        return Movie(id: jid, number: match.number ?? code, title: match.title ?? label,
                     thumbURL: match.thumb, coverURL: match.cover)
    }
    /// The matched JavDB actor (name/avatar only; detail loads on tap).
    func makeActor() -> Actor? {
        guard match.isMatched, let jid = match.javdbID else { return nil }
        return RankingFeedClient.makeActor(id: jid, name: match.name ?? name, avatar: match.avatar)
    }
}

struct RankingFeed: Decodable {
    let board: String
    let term: String?
    let generatedAt: String
    let source: String
    let entries: [RankingFeedEntry]
    enum CodingKeys: String, CodingKey {
        case board, term, source, entries
        case generatedAt = "generated_at"
    }
    var generatedDate: Date? { RankingFeedClient.parseISO(generatedAt) }
    /// A feed older than 48 hours is stale: its matched rows are still
    /// shown, but uncovered entries fall back to on-device verification.
    var isStale: Bool { RankingFeedClient.isStale(generatedAt: generatedAt) }
    func movieEntry(forCode code: String) -> RankingFeedEntry? {
        guard let key = JRPolicy.exactCode(code) else { return nil }
        return entries.first { entry in
            guard let raw = entry.code, entry.name == nil else { return false }
            return JRPolicy.exactCode(raw) == key
        }
    }
    func actorEntry(forNames names: [String]) -> RankingFeedEntry? {
        let wanted = Set(names.map(RankingFeedClient.nameKey).filter { !$0.isEmpty })
        guard !wanted.isEmpty else { return nil }
        return entries.first { entry in
            guard let name = entry.name else { return false }
            var keys: Set<String> = [RankingFeedClient.nameKey(name)]
            for alias in entry.aliases ?? [] { keys.insert(RankingFeedClient.nameKey(alias)) }
            keys.remove("")
            return !keys.isDisjoint(with: wanted)
        }
    }
}

enum RankingFeedClient {
    static let rawBase = "https://raw.githubusercontent.com/xy0305/AVDB/feed/feed"
    static let staleInterval: TimeInterval = 48 * 3600
    static let maxBytes = 4_000_000

    static func fileName(board: String, term: String?) -> String {
        term.map { "\(board)-\($0).json" } ?? "\(board).json"
    }
    static func url(board: String, term: String?) -> URL {
        URL(string: "\(rawBase)/\(fileName(board: board, term: term))")!
    }
    static func nameKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    static func parseISO(_ value: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
    static func isStale(generatedAt: String, now: Date = Date()) -> Bool {
        guard let date = parseISO(generatedAt) else { return true }
        return now.timeIntervalSince(date) > staleInterval
    }
    /// Actor has no memberwise initializer; build one through its decoder.
    static func makeActor(id: String, name: String?, avatar: String?) -> Actor? {
        var payload: [String: Any] = ["id": id]
        if let name { payload["name"] = name }
        if let avatar { payload["avatar_url"] = avatar }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        return try? JSONDecoder().decode(Actor.self, from: data)
    }

    private static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RankingFeed349")
    }
    private static func cacheFile(board: String, term: String?) -> URL {
        cacheDirectory.appendingPathComponent(fileName(board: board, term: term))
    }
    static func cached(board: String, term: String?) -> RankingFeed? {
        guard let data = try? Data(contentsOf: cacheFile(board: board, term: term)) else { return nil }
        return decode(data, board: board, term: term)
    }
    static func decode(_ data: Data, board: String, term: String?) -> RankingFeed? {
        guard data.count <= maxBytes,
              let feed = try? JSONDecoder().decode(RankingFeed.self, from: data),
              feed.board == board, term == nil || feed.term == term,
              feed.generatedDate != nil, feed.entries.count <= 600 else { return nil }
        return feed
    }
    /// Network first; the last good copy is the fallback. A remote copy is
    /// accepted only when its generated_at is not older than the cached
    /// one (monotonic), so a stale mirror can never rewind the boards.
    static func load(board: String, term: String?) async -> RankingFeed? {
        let local = cached(board: board, term: term)
        do {
            var request = URLRequest(url: url(board: board, term: term),
                                     cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let remote = decode(data, board: board, term: term) else { return local }
            if let local, let old = local.generatedDate, let new = remote.generatedDate, new < old {
                return local
            }
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try? data.write(to: cacheFile(board: board, term: term), options: .atomic)
            return remote
        } catch {
            return local
        }
    }
}

/// Session-scoped feed store: each board/term is fetched at most once per
/// app session (the pipeline publishes daily), then shared by every board
/// view for both pre-filling and the "数据更新于 X" note.
@MainActor final class RankingFeedState: ObservableObject {
    static let shared = RankingFeedState()
    @Published private(set) var feeds: [String: RankingFeed] = [:]
    private var attempted: Set<String> = []
    private func key(board: String, term: String?) -> String { "\(board)|\(term ?? "")" }
    func feed(board: String, term: String?) -> RankingFeed? { feeds[key(board: board, term: term)] }
    @discardableResult
    func ensure(board: String, term: String?) async -> RankingFeed? {
        let key = key(board: board, term: term)
        if attempted.contains(key) { return feeds[key] }
        attempted.insert(key)
        let loaded = await RankingFeedClient.load(board: board, term: term)
        if let loaded { feeds[key] = loaded }
        return loaded
    }
    func noteText(board: String, term: String?) -> String? {
        guard let feed = feed(board: board, term: term), let date = feed.generatedDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let base = "数据更新于 \(formatter.string(from: date))"
        return feed.isStale ? base + " · 可能过期" : base
    }
}

/// Small caption shown on each board: when the server feed was generated,
/// plus a stale warning past 48 hours (data still shows; the device
/// fallback covers whatever the stale feed cannot).
struct RankingFeedNote: View {
    let board: String
    let term: String?
    @ObservedObject private var state = RankingFeedState.shared
    var body: some View {
        if let text = state.noteText(board: board, term: term) {
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
