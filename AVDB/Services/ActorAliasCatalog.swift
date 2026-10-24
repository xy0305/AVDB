import Foundation

// Compiled offline from actor-mapping.xml. Exact normalized lookup only.
// Conflicting aliases are omitted and never auto-assigned to either actor.
struct ActorAliasIndex: Decodable, Sendable {
    struct Actor: Decodable, Sendable {
        let id: String
        let canonical: String
        let display: String
        let aliases: [String]
    }
    struct Conflict: Decodable, Sendable {
        let alias: String
        let actors: [String]
    }
    let schema: Int
    let actors: [Actor]
    let conflicts: [Conflict]

    static func bundled(in bundle: Bundle = .main) -> ActorAliasIndex? {
        guard let url = bundle.url(forResource: "ActorAliasIndex", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(ActorAliasIndex.self, from: data),
              value.schema == 1 else { return nil }
        return value
    }
}

enum ActorNameNormalizer {
    // NFKC + casefold + collapsed whitespace. No translation, romanization, or substring match.
    static func key(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

struct ActorAliasRecord: Hashable, Sendable {
    let id: String
    let canonical: String
    let display: String
    let aliases: [String]
}

// Bounded in-memory index. Lookup never guesses an unmapped same-name person.
struct ActorAliasCatalog: Sendable {
    let records: [ActorAliasRecord]
    private let byAlias: [String: String]
    let conflicts: [String: [String]]

    init(index: ActorAliasIndex) {
        var records: [ActorAliasRecord] = []
        var byAlias: [String: String] = [:]
        for actor in index.actors {
            let record = ActorAliasRecord(id: actor.id, canonical: actor.canonical, display: actor.display, aliases: actor.aliases)
            records.append(record)
            for alias in actor.aliases {
                let key = ActorNameNormalizer.key(alias)
                guard !key.isEmpty, byAlias[key] == nil else { continue }
                byAlias[key] = actor.id
            }
        }
        self.records = records
        self.byAlias = byAlias
        self.conflicts = Dictionary(uniqueKeysWithValues: index.conflicts.map {
            (ActorNameNormalizer.key($0.alias), $0.actors)
        })
    }

    static func bundled() -> ActorAliasCatalog {
        ActorAliasCatalog(index: ActorAliasIndex.bundled() ?? ActorAliasIndex(schema: 1, actors: [], conflicts: []))
    }

    func record(id: String) -> ActorAliasRecord? { records.first { $0.id == id } }

    func lookup(_ names: [String]) -> ActorAliasRecord? {
        let keys = Set(names.map(ActorNameNormalizer.key).filter { !$0.isEmpty && conflicts[$0] == nil })
        guard !keys.isEmpty else { return nil }
        let ids = Set(keys.compactMap { byAlias[$0] })
        guard ids.count == 1, let id = ids.first else { return nil }
        return record(id: id)
    }

    func isConflict(_ name: String) -> Bool { conflicts[ActorNameNormalizer.key(name)] != nil }
}

// Display identity for external rankings. Source rank/order stays with the caller.
struct ExternalActorIdentity: Hashable, Sendable {
    let sourceName: String
    let canonical: String?
    let display: String
    let mapID: String?
    let queries: [String]
    var unified: Bool { mapID != nil }

    static func resolve(sourceName: String, aliases: [String], catalog: ActorAliasCatalog) -> ExternalActorIdentity {
        let visible = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let supplied = ([visible] + aliases).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let record = catalog.lookup(supplied) else {
            return ExternalActorIdentity(sourceName: visible, canonical: nil, display: visible.isEmpty ? (aliases.first ?? "") : visible, mapID: nil, queries: Array(Set(supplied)).sorted())
        }
        return ExternalActorIdentity(sourceName: visible, canonical: record.canonical, display: record.display, mapID: record.id, queries: record.aliases)
    }
}
