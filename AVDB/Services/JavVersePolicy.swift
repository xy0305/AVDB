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
    static func resolve(name: String, aliases: [String] = [], catalog: ActorAliasCatalog = .bundled(), search: Search) async throws -> ExternalActorResolver.Match? {
        let identity = identity(name: name, aliases: aliases, catalog: catalog)
        switch try await ExternalActorResolver.inspect(identity: identity, search: search, queryLimit: 12) {
        case .matched(let match): return match
        case .notFound: return nil
        case .ambiguous(let candidates): throw ExternalActorResolver.Failure.ambiguous(candidates)
        case .incomplete(let candidates, _): throw ExternalActorResolver.Failure.incomplete(candidates)
        }
    }
    /// Compatibility for callers that only need the actor. Video-count reason stays on Match.
    static func resolveActor(name: String, aliases: [String] = [], catalog: ActorAliasCatalog = .bundled(), search: Search) async throws -> Actor? {
        try await resolve(name: name, aliases: aliases, catalog: catalog, search: search)?.actor
    }
}
