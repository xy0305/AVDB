import Foundation

// Native cached-snapshot API. Does not scrape HTML, subscribe or mutate the VPS.
enum JAVLibraryKind: String, CaseIterable, Identifiable {
    case mostwanted, bestrated, actors
    var id: String { rawValue }
    var title: String {
        switch self {
        case .mostwanted: return "最想要"
        case .bestrated: return "高评价"
        case .actors: return "女优收藏"
        }
    }
}
struct JAVLibraryEntry: Decodable, Identifiable {
    let entityType: String
    let rank: Int
    let number: String?
    let name: String?
    let aliases: [String]?
    let title: String?
    let sourceURL: String
    // poster/avatar/local_tid deliberately never become an AVDB identity/cover.
    var id: String { sourceURL }
    enum CodingKeys: String, CodingKey {
        case entityType = "entity_type", sourceURL = "source_url"
        case rank, number, name, aliases, title
    }
    var video: JRVideo {
        JRVideo(path: sourceURL, code: number ?? "", title: title ?? number ?? "JAVLibrary", image: nil, subtitle: "")
    }
    var actor: MissAVActress {
        MissAVActress(path: sourceURL, name: name ?? "", aliases: [name ?? ""] + (aliases ?? []), rank: rank)
    }
}
struct JAVLibrarySnapshot: Decodable {
    let source: String
    let kind: String
    let entityType: String
    let fetchedAt: String
    let sourceURL: String
    let pages: Int
    let count: Int
    let stale: Bool
    let lastAttempt: Attempt?
    let items: [JAVLibraryEntry]
    struct Attempt: Decodable { let ok: Int; let attempted_at: String }
    enum CodingKeys: String, CodingKey {
        case source, kind, pages, count, stale, items
        case entityType = "entity_type", fetchedAt = "fetched_at", sourceURL = "source_url", lastAttempt = "last_attempt"
    }
    static func decode(_ bytes: Data, kind expected: JAVLibraryKind) throws -> Self {
        struct Envelope: Decodable { let code: Int; let data: JAVLibrarySnapshot }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: bytes), envelope.code == 0 else { throw ExternalLibraryError.schema }
        let snapshot = envelope.data
        let entity = expected == .actors ? "actor" : "movie"
        guard snapshot.source == "javlibrary", snapshot.kind == expected.rawValue,
              snapshot.entityType == entity, snapshot.count == snapshot.items.count,
              snapshot.pages > 0, snapshot.count <= 500,
              Set(snapshot.items.map(\.id)).count == snapshot.count,
              snapshot.items.allSatisfy({ $0.entityType == entity && $0.rank > 0 && !$0.sourceURL.isEmpty }),
              zip(snapshot.items, snapshot.items.dropFirst()).allSatisfy({ pair in pair.0.rank < pair.1.rank }) else { throw ExternalLibraryError.schema }
        // Never sort by AVDB metadata or silently renumber a server rank.
        return snapshot
    }
}
extension ExternalLibraryClient {
    @MainActor func javlibrary(_ kind: JAVLibraryKind, settings: ExternalLibrarySettings? = nil) async throws -> JAVLibrarySnapshot {
        let bytes = try await fetchRankingData(kind: kind.rawValue, settings: settings)
        return try JAVLibrarySnapshot.decode(bytes, kind: kind)
    }
}
