import Foundation
import Combine

// Build 351: server-side metadata enrichment feed. The VPS pipeline
// (enrich.py) fills the fields JavDB does not reliably provide — plot,
// director, score, stills, trailer, an upscaled cover for movies; profile
// data, a bio and a better portrait for actors — from DMM / Wikidata /
// gfriends and publishes them on the repo's `feed` branch next to the
// Build 349 ranking feed. This client mirrors RankingFeedClient: network
// first, last-good Caches copy as fallback, generated_at monotonicity,
// one fetch per file per session. Unlike the ranking feed there is no
// on-device fallback for enrichment, so staleness never gates usage: a
// stale copy still merges (the data is reference material, not a match
// verdict), and a missing entry simply leaves the detail page as it was.
//
// Files (same raw base as RankingFeedClient):
//   enrich-m-<shard>.json  shard = first character of the JavDB movie id,
//                          lowercased; entries keyed by javdb_id.
//   enrich-actors.json     one file; entries keyed by javdb_id when the
//                          pipeline has one, else by actor name.
struct EnrichmentFeed<Entry: Decodable>: Decodable {
    let board: String
    let term: String?
    let generatedAt: String
    let source: String
    let entries: [Entry]
    enum CodingKeys: String, CodingKey {
        case board, term, source, entries
        case generatedAt = "generated_at"
    }
    var generatedDate: Date? { RankingFeedClient.parseISO(generatedAt) }
}

enum EnrichmentFeedClient {
    static let maxBytes = 8_000_000
    static let maxEntries = 10_000

    static func movieFileName(shard: String) -> String { "enrich-m-\(shard).json" }
    static let actorsFileName = "enrich-actors.json"
    static func shard(forMovieID id: String) -> String? {
        guard let first = id.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
        return String(first).lowercased()
    }
    /// The shape check itself lives on MovieEnrichment (Models layer) so
    /// Movie.swift stays self-contained; this is the feed client's entry.
    static func isEnrichmentCover(_ value: String) -> Bool {
        MovieEnrichment.isEnrichmentCover(value)
    }

    private static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EnrichmentFeed351")
    }
    private static func decode<Entry: Decodable>(_ data: Data, term: String) -> EnrichmentFeed<Entry>? {
        guard data.count <= maxBytes,
              let feed = try? JSONDecoder().decode(EnrichmentFeed<Entry>.self, from: data),
              feed.board == "enrich", feed.term == term,
              feed.generatedDate != nil, feed.entries.count <= maxEntries else { return nil }
        return feed
    }
    private static func load<Entry: Decodable>(fileName: String, term: String) async -> EnrichmentFeed<Entry>? {
        let cacheFile = cacheDirectory.appendingPathComponent(fileName)
        let local: EnrichmentFeed<Entry>? = (try? Data(contentsOf: cacheFile)).flatMap { decode($0, term: term) }
        do {
            var request = URLRequest(url: URL(string: "\(RankingFeedClient.rawBase)/\(fileName)")!,
                                     cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let remote: EnrichmentFeed<Entry> = decode(data, term: term) else { return local }
            if let local, let old = local.generatedDate, let new = remote.generatedDate, new < old {
                return local
            }
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try? data.write(to: cacheFile, options: .atomic)
            return remote
        } catch {
            return local
        }
    }
    static func loadMovies(shard: String) async -> EnrichmentFeed<MovieEnrichment>? {
        await load(fileName: movieFileName(shard: shard), term: "m-\(shard)")
    }
    static func loadActors() async -> EnrichmentFeed<ActorEnrichment>? {
        await load(fileName: actorsFileName, term: "actors")
    }
}

/// Session-scoped enrichment store: each shard file / the actors file is
/// fetched at most once per app session, then shared by every detail page.
@MainActor final class EnrichmentFeedState: ObservableObject {
    static let shared = EnrichmentFeedState()
    private var movieFeeds: [String: EnrichmentFeed<MovieEnrichment>] = [:]
    private var movieAttempted: Set<String> = []
    private var actorsByID: [String: ActorEnrichment] = [:]
    private var actorsByNameKey: [String: ActorEnrichment] = [:]
    private var actorsAttempted = false

    func movieEnrichment(javdbID: String) async -> MovieEnrichment? {
        guard let shard = EnrichmentFeedClient.shard(forMovieID: javdbID) else { return nil }
        if !movieAttempted.contains(shard) {
            movieAttempted.insert(shard)
            if let feed = await EnrichmentFeedClient.loadMovies(shard: shard) {
                movieFeeds[shard] = feed
            }
        }
        return movieFeeds[shard]?.entries.first { $0.javdbID == javdbID }
    }

    /// Actor lookup: javdb_id first; name fallback goes through the alias
    /// catalog normalization on both sides (ActorNameNormalizer.key over
    /// the catalog's canonical + alias names), so a feed entry filed under
    /// any known alias of the actor still matches.
    func actorEnrichment(id: String?, names: [String]) async -> ActorEnrichment? {
        if !actorsAttempted {
            actorsAttempted = true
            if let feed = await EnrichmentFeedClient.loadActors() {
                let catalog = ActorAliasCatalog.bundled()
                for entry in feed.entries {
                    if let jid = entry.javdbID, !jid.isEmpty { actorsByID[jid] = entry }
                    var keys: Set<String> = [ActorNameNormalizer.key(entry.name)]
                    if let mapped = catalog.lookup([entry.name]) {
                        for alias in [mapped.canonical] + mapped.aliases {
                            keys.insert(ActorNameNormalizer.key(alias))
                        }
                    }
                    for key in keys where !key.isEmpty {
                        if actorsByNameKey[key] == nil { actorsByNameKey[key] = entry }
                    }
                }
            }
        }
        if let id, !id.isEmpty, let hit = actorsByID[id] { return hit }
        for name in names {
            let key = ActorNameNormalizer.key(name)
            if !key.isEmpty, let hit = actorsByNameKey[key] { return hit }
        }
        return nil
    }
}
