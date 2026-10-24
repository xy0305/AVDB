import Foundation

// Cross-board actor identity. AVDB IDs are never invented or merged here.
// A unique SDK row must evidence the canonical name or a mapped alias exactly.
@MainActor enum ExternalActorResolver {
    typealias Search = @MainActor (String, Int) async throws -> [Actor]
    struct Match: Sendable {
        let actor: Actor
        let identity: ExternalActorIdentity
    }

    static func match(_ identity: ExternalActorIdentity, actor: Actor) -> Bool {
        let wanted = Set(identity.queries.map(ActorNameNormalizer.key))
        let evidence = [actor.name, actor.otherName, actor.keyword, actor.nameZht, actor.displayName]
            .compactMap { $0 }
            .flatMap { $0.components(separatedBy: CharacterSet(charactersIn: ",，、;；|/／\n")) }
            .map(ActorNameNormalizer.key)
        return !wanted.isEmpty && !wanted.isDisjoint(with: Set(evidence))
    }

    static func resolve(identity: ExternalActorIdentity, search: Search, queryLimit: Int = 4) async throws -> Match? {
        let queries = Array(Set(identity.queries.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        guard !queries.isEmpty else { return nil }
        var matches: [String: Actor] = [:]
        for query in queries.prefix(max(1, queryLimit)) {
            var exhausted = false
            for page in 1...3 {
                try Task.checkCancellation()
                let rows = try await search(query, page)
                try Task.checkCancellation()
                for row in rows where !row.id.isEmpty && row.id == row.id.trimmingCharacters(in: .whitespacesAndNewlines) && match(identity, actor: row) {
                    matches[row.id] = row
                }
                guard matches.count <= 1 else { return nil }
                if rows.count < 20 { exhausted = true; break }
            }
            guard exhausted else { return nil }
        }
        guard let actor = matches.values.first else { return nil }
        return Match(actor: actor, identity: identity)
    }
}

enum ActorAvatarLookupStatus: String, Sendable {
    case existing
    case matched
    case notFound = "not_found"
    case ambiguous
    case missingKey = "missing_key"
    case failed
    case cancelled
}

struct ActorAvatarLookup: Sendable {
    let status: ActorAvatarLookupStatus
    let url: String?
    let personID: Int?
}

// Public person metadata only. Existing AVDB artwork always wins and is never replaced.
@MainActor enum ActorAvatarFallback {
    typealias Search = @MainActor ([String]) async throws -> ActorAvatarLookup
    private struct Cached { let lookup: ActorAvatarLookup; let date: Date }
    private static var cache: [String: Cached] = [:]
    private static var order: [String] = []
    static let ttl: TimeInterval = 60 * 60 * 24 * 7
    static let imageBase = "https://image.tmdb.org/t/p/w185"

    static func resetCache() { cache.removeAll(); order.removeAll() }

    static func existing(_ actor: Actor) -> String? {
        [actor.avatarURL, actor.coverURL].compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func resolveMissing(actor: Actor, names: [String]) async -> ActorAvatarLookup {
        await resolve(actor: actor, names: names) { names in
            // Read at request time. A blank field never reaches the network.
            try await TMDBPersonClient.search(names: names, apiKey: TMDBAvatarSettings.shared.currentKey())
        }
    }

    static func resolve(actor: Actor, names: [String], search: Search) async -> ActorAvatarLookup {
        if existing(actor) != nil { return ActorAvatarLookup(status: .existing, url: nil, personID: nil) }
        let keys = Array(Set(names.map(ActorNameNormalizer.key).filter { !$0.isEmpty })).sorted()
        guard !keys.isEmpty else { return ActorAvatarLookup(status: .notFound, url: nil, personID: nil) }
        let key = keys.joined(separator: "\u{1f}")
        if let cached = cache[key] {
            if Date().timeIntervalSince(cached.date) <= ttl { return cached.lookup }
            cache[key] = nil
        }
        let lookup: ActorAvatarLookup
        do {
            try Task.checkCancellation()
            lookup = try await search(names)
            try Task.checkCancellation()
        } catch is CancellationError {
            return ActorAvatarLookup(status: .cancelled, url: nil, personID: nil)
        } catch {
            return ActorAvatarLookup(status: .failed, url: nil, personID: nil)
        }
        // Absence is cached so a visible card does not repeat the same public request.
        // Cancellation is intentionally not cached.
        cache[key] = Cached(lookup: lookup, date: Date())
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > 240 { cache.removeValue(forKey: order.removeFirst()) }
        return lookup
    }

    nonisolated static func officialURL(profilePath: String) -> String? {
        guard profilePath.hasPrefix("/"), !profilePath.contains(".."),
              profilePath.range(of: #"^/[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else { return nil }
        return imageBase + profilePath
    }
}

struct TMDBPerson: Decodable, Sendable {
    let id: Int
    let name: String
    let alsoKnownAs: [String]
    let gender: Int?
    let profilePath: String?
    enum CodingKeys: String, CodingKey {
        case id, name, gender
        case alsoKnownAs = "also_known_as"
        case profilePath = "profile_path"
    }
}

enum TMDBPersonSelector {
    // Canonical or mapped alias must equal name or also_known_as. First result is never chosen.
    static func select(_ people: [TMDBPerson], names: [String]) -> ActorAvatarLookup {
        let wanted = Set(names.map(ActorNameNormalizer.key).filter { !$0.isEmpty })
        let hits = people.filter { person in
            let evidence = ([person.name] + person.alsoKnownAs).map(ActorNameNormalizer.key)
            return !wanted.isDisjoint(with: Set(evidence)) && person.profilePath?.isEmpty == false
        }
        guard hits.count == 1, let person = hits.first, let path = person.profilePath,
              let url = ActorAvatarFallback.officialURL(profilePath: path) else {
            return ActorAvatarLookup(status: hits.count > 1 ? .ambiguous : .notFound, url: nil, personID: nil)
        }
        return ActorAvatarLookup(status: .matched, url: url, personID: person.id)
    }
}

@MainActor enum TMDBPersonClient {
    static func search(names: [String], apiKey: String?, session: URLSession = .shared) async throws -> ActorAvatarLookup {
        let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else { return ActorAvatarLookup(status: .missingKey, url: nil, personID: nil) }
        let query = names.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
        guard !query.isEmpty, var components = URLComponents(string: "https://api.themoviedb.org/3/search/person") else {
            return ActorAvatarLookup(status: .notFound, url: nil, personID: nil)
        }
        components.queryItems = [URLQueryItem(name: "query", value: query), URLQueryItem(name: "include_adult", value: "true")]
        guard let url = components.url else { return ActorAvatarLookup(status: .notFound, url: nil, personID: nil) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return ActorAvatarLookup(status: .failed, url: nil, personID: nil)
        }
        struct Payload: Decodable { let results: [TMDBPerson] }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return TMDBPersonSelector.select(payload.results, names: names)
    }
}

/// Device-only Read Access Token. Never logged, bundled, or echoed back into the field.
struct TMDBAvatarTokenStore: ExternalTokenStore {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "app.avdb.tmdb-avatar",
         kSecAttrAccount as String: "read-access-token",
         kSecAttrSynchronizable as String: false]
    }
    func read() throws -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
            throw ExternalLibraryError.keychain(status)
        }
        return token
    }
    func write(_ token: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ExternalLibraryError.keychain(status) }
    }
    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ExternalLibraryError.keychain(status) }
    }
}

@MainActor final class TMDBAvatarSettings: ObservableObject {
    static let shared = TMDBAvatarSettings()
    private let store: ExternalTokenStore
    @Published private(set) var configured = false
    init(store: ExternalTokenStore = TMDBAvatarTokenStore()) {
        self.store = store
        configured = ((try? store.read()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
    func currentKey() -> String? {
        let value = ((try? store.read()) ?? nil)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
    /// Empty replacement keeps the stored key. Only the clear action deletes it.
    func save(replacement: String) throws {
        let trimmed = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 4096, trimmed.utf8.allSatisfy({ (33...126).contains($0) }) else { throw ExternalLibraryError.invalidToken }
        if !trimmed.isEmpty { try store.write(trimmed) }
        configured = currentKey() != nil
    }
    func clear() throws {
        try store.clear()
        configured = false
    }
}

struct TMDBAvatarSettingsView: View {
    @ObservedObject private var settings = TMDBAvatarSettings.shared
    @State private var token = ""
    @State private var status = ""
    var body: some View {
        Form {
            Section("TMDB 头像") {
                SecureField("TMDB 头像（不回显）", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("tmdb-avatar-token")
                Text(settings.configured ? "已设置（不显示内容）" : "未设置")
                    .accessibilityIdentifier("tmdb-avatar-configuration")
                Button("保存") {
                    do {
                        try settings.save(replacement: token)
                        token = ""
                        status = settings.configured ? "已保存到本机钥匙串" : "未填写，已保留原设置"
                    } catch {
                        token = ""
                        status = "保存失败，请检查密钥格式或解锁设备后重试"
                    }
                }.accessibilityIdentifier("tmdb-avatar-save")
                Button("清除", role: .destructive) {
                    do { try settings.clear(); token = ""; status = "已清除本机密钥" }
                    catch { token = ""; status = "清除失败，请解锁设备后重试" }
                }.accessibilityIdentifier("tmdb-avatar-clear")
                if !status.isEmpty { Text(status).accessibilityIdentifier("tmdb-avatar-status") }
            }
            Section("范围") {
                Text("仅在已有 AVDB 头像缺失、且姓名唯一匹配时使用。已有 AVDB 头像始终优先，不会被替换。")
                Text("密钥仅存本机钥匙串，仅发送到 https://api.themoviedb.org。不写入日志，不进入 IPA。留空保存不会清除；未设置时界面显示“未设置”且不发请求。")
            }
        }
        .navigationTitle("TMDB 头像")
        .onDisappear { token = "" }
    }
}
