import Foundation
import Combine

// Simulator-only Release acceptance: real bundle data, no account or image network.
enum JavVerseReleaseProbe {
    static var enabled: Bool {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("--javverse-release-bundle-ui")
        #else
        return false
        #endif
    }
}

struct JavVerseSnapshot: Decodable {
    let schemaVersion: Int
    let mode: String
    let origin: String
    let preparedAt: String
    let boards: [JavVerseBoard]
    let grok: JavVerseGrokSnapshot?
    // Informational stamp only; bundle replacement is not a decoding strategy.
    // The field is optional and is not a rank or source signal.
    let resourceRevision: Int?
    enum CodingKeys: String, CodingKey {
        case schemaVersion, mode, origin, preparedAt, boards, grok, resourceRevision
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        mode = try container.decode(String.self, forKey: .mode)
        origin = try container.decode(String.self, forKey: .origin)
        preparedAt = try container.decode(String.self, forKey: .preparedAt)
        boards = try container.decode([JavVerseBoard].self, forKey: .boards)
        grok = try container.decodeIfPresent(JavVerseGrokSnapshot.self, forKey: .grok)
        resourceRevision = try container.decodeIfPresent(Int.self, forKey: .resourceRevision)
        // Keys outside CodingKeys are not decoded, so an extra stamp cannot reject the snapshot.
    }
    // Resource decoding is independent from image/network mapping; warm navigation reuses metadata.
    private static var cachedBundle: Self?
    static func bundled(in bundle: Bundle = .main) throws -> Self {
        if bundle == .main, let cachedBundle { return cachedBundle }
        guard let url = bundle.url(forResource: "JavVerseSnapshot", withExtension: "json") else {
            throw JavVerseFailure.missingResource
        }
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { throw JavVerseFailure.unreadableResource }
        let value = try decode(data)
        if bundle == .main { cachedBundle = value }
        return value
    }
    static func decode(_ data: Data) throws -> Self {
        // JSONDecoder ignores unknown keys but preserves precise DecodingError paths.
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate()
        return value
    }
    func validate() throws {
        guard [1, 2].contains(schemaVersion), mode == "staticSnapshot", origin == "https://javverse.com",
              Self.timestamp(preparedAt), !boards.isEmpty,
              Set(boards.map(\.id)).count == boards.count else {
            throw JavVerseFailure.message("不支持的快照格式或时间")
        }
        if let grok {
            guard Self.timestamp(grok.capturedAt), Self.sourceURL(grok.sourceURL),
                  grok.people.count == 250, Set(grok.people.map(\.id)).count == 250,
                  grok.people.allSatisfy({ !$0.nameJa.isEmpty && !$0.nameZh.isEmpty && ["现役", "引退", "已故"].contains($0.status) && $0.actressId > 0 && Set($0.scores.keys) == Set(["total", "works", "pop", "face", "body", "award", "years"]) && $0.scores.values.allSatisfy({ (0...10000).contains($0) }) }) else {
                throw JavVerseFailure.message("Grok公开快照不完整；拒绝推测名次")
            }
        }
        for board in boards {
            guard !board.id.isEmpty, !board.title.isEmpty, !board.period.isEmpty,
                  board.coverage == "complete", Self.timestamp(board.capturedAt),
                  Self.sourceURL(board.sourceURL), !board.entries.isEmpty,
                  board.entries.map(\.rank) == Array(1...board.entries.count),
                  Set(board.entries.map(\.id)).count == board.entries.count else {
                throw JavVerseFailure.message("快照来源、时间或名次无效；拒绝补位")
            }
            for entry in board.entries {
                guard ["movie", "actor", "series"].contains(entry.kind), !entry.label.isEmpty,
                      Self.sourceURL(entry.sourceURL),
                      entry.kind != "movie" || entry.code.flatMap(JavVerseIdentity.code) != nil else {
                    throw JavVerseFailure.message("快照条目身份或来源无效")
                }
            }
        }
    }
    private static func timestamp(_ text: String) -> Bool {
        // 243 rejected fractional offsets such as 2026-10-24T03:58:55.413884+00:00.
        // Fractional or whole seconds are valid with Z or ±HH:MM. A zone is required.
        guard let separator = text.firstIndex(of: "T") else { return false }
        let clock = text[text.index(after: separator)...]
        guard clock.contains(":") else { return false }
        let zone = clock.suffix(6)
        let numericZone = zone.count == 6 && (zone.hasPrefix("+") || zone.hasPrefix("-"))
            && zone.dropFirst(1).dropLast(3).allSatisfy(\.isNumber)
            && zone.dropFirst(3).first == ":"
            && zone.suffix(2).allSatisfy(\.isNumber)
        guard clock.hasSuffix("Z") || numericZone else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if formatter.date(from: text) != nil { return true }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text) != nil
    }
    private static func sourceURL(_ text: String) -> Bool {
        guard let url = URLComponents(string: text) else { return false }
        return url.scheme == "https" && url.host == "javverse.com" && url.user == nil
            && url.password == nil && url.port == nil
    }
}
struct JavVerseBoard: Decodable, Identifiable {
    let id: String
    let title: String
    let period: String
    let capturedAt: String
    let sourceURL: String
    let coverage: String
    let entries: [JavVerseEntry]
    var term: String? = nil
    var periodKey: String? = nil
    var periodEnd: String? = nil
    var selectionTitle: String? = nil
    // Includes all source dimensions; mapping cache remains separately account/backend scoped.
    var selectionKey: String { "javverse|sales|sales|\(term ?? id)|\(periodKey ?? period)|all" }
}

enum JavVerseGrokMetric: String, CaseIterable, Identifiable {
    case total, works, pop, face, body
    var id: String { rawValue }
    var title: String {
        switch self { case .total: return "综合"; case .works: return "作品"; case .pop: return "人气"; case .face: return "颜值"; case .body: return "身材" }
    }
}
enum JavVerseGrokStatus: String, CaseIterable, Identifiable {
    case all, active, retired
    var id: String { rawValue }
    var title: String { self == .all ? "全部" : self == .active ? "现役" : "引退" }
}
struct JavVerseGrokPerson: Decodable, Identifiable {
    let id: String
    let nameJa: String
    let nameZh: String
    let years: String
    let status: String
    let scores: [String: Int]
    let scoreText: [String: String]
    let actressId: Int
    func entry(rank: Int) -> JavVerseEntry {
        // Japanese stays the visible source label. Chinese is evidence, not a rewritten rank row.
        JavVerseEntry(rank: rank, kind: "actor", label: nameJa, sourceURL: "https://javverse.com/actress/\(actressId)", code: nil, aliases: nameZh == nameJa ? [] : [nameZh])
    }
}
struct JavVerseGrokRow: Identifiable {
    let person: JavVerseGrokPerson
    let rank: Int
    var id: String { person.id }
    var entry: JavVerseEntry { person.entry(rank: rank) }
}
struct JavVerseGrokSnapshot: Decodable {
    let capturedAt: String
    let sourceURL: String
    let sortEvidence: String
    let people: [JavVerseGrokPerson]
    // Exact comparator from public 1958-5dff65ae7b330f9f.js function S.
    // JS < compares UTF-16 code units, not locale-aware name collation.
    private static func jsLess(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf16.lexicographicallyPrecedes(rhs.utf16)
    }
    func rows(metric: JavVerseGrokMetric, status: JavVerseGrokStatus) -> [JavVerseGrokRow] {
        let sorted = people.filter { status == .all || $0.status == status.title }.sorted { lhs, rhs in
            let a = lhs.scores[metric.rawValue] ?? -1, b = rhs.scores[metric.rawValue] ?? -1
            if a != b { return a > b }
            if metric == .total {
                let x = lhs.scores["works"] ?? -1, y = rhs.scores["works"] ?? -1
                if x != y { return x > y }
            }
            if lhs.nameJa != rhs.nameJa { return Self.jsLess(lhs.nameJa, rhs.nameJa) }
            return Self.jsLess(lhs.id, rhs.id)
        }
        var previous: Int?; var rank = 0
        return sorted.enumerated().map { index, person in
            let score = person.scores[metric.rawValue]
            // Comprehensive ranks are unique. Submetrics use competition ranking (1,1,3).
            if metric == .total || score != previous { rank = index + 1 }
            previous = score
            return JavVerseGrokRow(person: person, rank: rank)
        }
    }
}
struct JavVerseEntry: Decodable, Identifiable {
    let rank: Int
    let kind: String
    let label: String
    let sourceURL: String
    let code: String?
    var aliases: [String] = []
    var id: String { "\(rank)|\(kind)|\(sourceURL)|\(label)" }
}
// An extension keeps Swift's memberwise initializer (including aliases' default).
// Missing and null aliases mean no extra names; a wrong type still throws.
extension JavVerseEntry {
    private enum CodingKeys: String, CodingKey { case rank, kind, label, sourceURL, code, aliases }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rank = try c.decode(Int.self, forKey: .rank)
        kind = try c.decode(String.self, forKey: .kind)
        label = try c.decode(String.self, forKey: .label)
        sourceURL = try c.decode(String.self, forKey: .sourceURL)
        code = try c.decodeIfPresent(String.self, forKey: .code)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
    }
}
enum JavVerseFailure: LocalizedError {
    case message(String)
    case missingResource, unreadableResource
    static func diagnostic(_ error: Error) -> String {
        func path(_ keys: [CodingKey]) -> String {
            var result = ""
            for key in keys {
                if let index = key.intValue { result += "[\(index)]" }
                else { result += (result.isEmpty ? "" : ".") + key.stringValue }
            }
            return result.isEmpty ? "$" : result
        }
        switch error {
        case DecodingError.keyNotFound(let key, let c):
            return "快照字段缺失 [keyNotFound]：\(path(c.codingPath + [key]))"
        case DecodingError.typeMismatch(_, let c):
            return "快照字段类型错误 [typeMismatch]：\(path(c.codingPath))"
        case DecodingError.valueNotFound(_, let c):
            return "快照字段为空 [valueNotFound]：\(path(c.codingPath))"
        case DecodingError.dataCorrupted(let c):
            return "快照JSON或字段损坏 [dataCorrupted]：\(path(c.codingPath))"
        case JavVerseFailure.missingResource:
            return "快照资源不存在 [resourceMissing]：JavVerseSnapshot.json"
        case JavVerseFailure.unreadableResource:
            return "快照资源读取失败 [resourceRead]：JavVerseSnapshot.json"
        case let failure as JavVerseFailure:
            return "快照业务校验 [validation]：\(failure.localizedDescription)"
        default:
            // Never display NSError userInfo, paths, response bodies or credentials.
            return "快照资源读取或JSON解析失败 [resourceOrJSON]"
        }
    }
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}
// Strict number identity: uppercase and surrounding whitespace ONLY.
// Never remove zeros, hyphens, suffixes or infer a number from a title/source numeric ID.
enum JavVerseIdentity {
    static func code(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.unicodeScalars.allSatisfy({ $0.isASCII }) else { return nil }
        let key = trimmed.uppercased()
        guard key.range(of: #"^[A-Z0-9]+-[A-Z0-9]+$"#, options: .regularExpression) != nil else { return nil }
        return key
    }
}

@MainActor final class JavVerseMapper: ObservableObject {
    @Published private(set) var movies: [String: Movie] = [:]
    @Published private(set) var actors: [String: Actor] = [:]
    @Published private(set) var avatars: [String: String] = [:]
    @Published private(set) var avatarStatus: [String: String] = [:]
    @Published private(set) var messages: [String: String] = [:]
    @Published private(set) var candidates: [String: [Actor]] = [:]
    @Published private(set) var videoCounts: [String: Int] = [:]
    @Published private(set) var busy = false
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    private struct Cached { let movie: Movie?; let actor: Actor?; let candidates: [Actor]; let message: String?; let date: Date }
    // In-memory only, bounded and account/backend scoped; no credentials persisted or logged.
    private static var cache: [String: Cached] = [:]
    private static var order: [String] = []
    private var account: String?
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private var observation: AnyCancellable?
    private let search: JavVerseMovieResolver.Search
    private let actorSearch: JavVerseActorResolver.Search
    private let hydrateMovie: @MainActor (String) async throws -> Movie
    private let hydrateActor: @MainActor (String) async throws -> Actor?
    private let sharedCache: Bool
    private let movieHydration: Bool
    private let actorHydration: Bool
    private let accountProvider: @MainActor () -> String?
    private let scope: String
    init(scope: String = "javverse|legacy", search: JavVerseMovieResolver.Search? = nil,
         actorSearch: JavVerseActorResolver.Search? = nil,
         hydrateMovie: (@MainActor (String) async throws -> Movie)? = nil,
         hydrateActor: (@MainActor (String) async throws -> Actor?)? = nil,
         shareCache: Bool? = nil,
         accountProvider: @escaping @MainActor () -> String? = { APIClient.shared.token }) {
        self.scope = scope
        self.search = search ?? { source, page in
            try await JavDBSDK.shared.search(keyword: source, page: page, type: "movie", limit: 20)
        }
        self.actorSearch = actorSearch ?? { name, page in
            try await JavDBSDK.shared.searchActors(keyword: name, page: page, limit: 20)
        }
        self.hydrateMovie = hydrateMovie ?? { try await JavDBSDK.shared.movieDetail($0) }
        self.hydrateActor = hydrateActor ?? { try await JavDBSDK.shared.actorDetail($0).actor }
        self.movieHydration = search == nil || hydrateMovie != nil
        self.actorHydration = actorSearch == nil || hydrateActor != nil
        self.sharedCache = shareCache ?? (search == nil && actorSearch == nil)
        self.accountProvider = accountProvider
        account = accountProvider()
        observation = NotificationCenter.default.publisher(for: Notification.Name("avdb.catalog.accountChanged"))
            .sink { [weak self] _ in Task { @MainActor in
                Self.cache.removeAll(); Self.order.removeAll(); self?.clear()
            } }
    }
    func clear() {
        cancel(); movies.removeAll(); actors.removeAll(); avatars.removeAll(); candidates.removeAll(); videoCounts.removeAll(); messages.removeAll(); account = accountProvider()
    }
    func waitUntilIdle() async { await task?.value }
    func cancel() {
        task?.cancel(); task = nil; generation = UUID(); busy = false
        for (key, value) in messages where value == "排队中" || value == "请求中…" { messages.removeValue(forKey: key) }
    }
    func movie(for entry: JavVerseEntry) -> Movie? {
        guard account == accountProvider() else { return nil }; return movies[entry.id]
    }
    func actor(for entry: JavVerseEntry) -> Actor? {
        guard account == accountProvider() else { return nil }; return actors[entry.id]
    }
    func candidates(for entry: JavVerseEntry) -> [Actor] {
        guard account == accountProvider() else { return [] }
        return candidates[entry.id] ?? []
    }
    private func remember(_ entry: JavVerseEntry, movie: Movie?, actor: Actor?, choices: [Actor], message: String) {
        guard sharedCache, movie != nil || actor != nil || !choices.isEmpty else { return }
        let cacheKey = key(entry)
        Self.cache[cacheKey] = Cached(movie: movie, actor: actor, candidates: choices, message: message, date: Date())
        Self.order.removeAll { $0 == cacheKey }; Self.order.append(cacheKey)
        while Self.order.count > 160 { Self.cache.removeValue(forKey: Self.order.removeFirst()) }
    }
    private func pace(since start: Date) async throws {
        let elapsed = Date().timeIntervalSince(start)
        if elapsed < 0.05 { try await Task.sleep(nanoseconds: UInt64((0.05 - elapsed) * 1_000_000_000)) }
    }
    private func key(_ entry: JavVerseEntry) -> String {
        let identity = entry.kind == "movie" ? (entry.code.flatMap(JavVerseIdentity.code) ?? entry.label) : entry.label
        return "\(scope)|\(JavDBConstants.baseURL)|\(account ?? "<anonymous>")|\(entry.kind)|\(identity)"
    }
    @discardableResult
    func resolve(_ entries: [JavVerseEntry], retry: Bool = false) -> Task<Void, Never>? {
        guard !JavVerseReleaseProbe.enabled else { return nil }
        guard !busy else { return nil }
        if account != accountProvider() { clear() }
        let epoch = generation, token = account
        // Current visible page only. At most two requests run together; paging cancels this generation.
        let batch = Array(entries.filter { ($0.kind == "movie" || $0.kind == "actor") && movies[$0.id] == nil && actors[$0.id] == nil && (retry || messages[$0.id] == nil) }.prefix(20))
        guard !batch.isEmpty else { return nil }
        busy = true; completed = 0; total = batch.count
        for entry in batch { messages[entry.id] = "排队中" }
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.generation == epoch {
                    self.busy = false; self.task = nil
                    for (key, value) in self.messages where value == "排队中" || value == "请求中…" { self.messages.removeValue(forKey: key) }
                }
            }
            await withTaskGroup(of: Void.self) { group in
                var index = 0
                func startNext() {
                    guard index < batch.count else { return }
                    let entry = batch[index]
                    index += 1
                    group.addTask { @MainActor in await self.verify(entry, epoch: epoch, token: token) }
                }
                startNext(); startNext()
                while await group.next() != nil {
                    if Task.isCancelled || self.generation != epoch { break }
                    startNext()
                }
            }
        }
        return task
    }
    private func verify(_ entry: JavVerseEntry, epoch: UUID, token: String?) async {
        var choices: [Actor] = []
        let started = Date()
        do {
            try Task.checkCancellation()
            guard generation == epoch, accountProvider() == token else { throw CancellationError() }
            let cacheKey = key(entry)
            var cached = sharedCache ? Self.cache[cacheKey] : nil
            if let value = cached, Date().timeIntervalSince(value.date) > 600 { cached = nil }
            messages[entry.id] = "请求中…"
            var movie = cached?.movie; var actor = cached?.actor
            choices = cached?.candidates ?? []
            if cached == nil {
                if entry.kind == "movie" {
                    guard let source = entry.code else { throw JavVerseFailure.message("原始完整番号不可核验") }
                    movie = try await JavVerseMovieResolver.resolve(code: source) { source, page in
                        try Task.checkCancellation()
                        guard self.generation == epoch, self.accountProvider() == token else { throw CancellationError() }
                        return try await self.search(source, page)
                    }
                    if movieHydration, let found = movie, (found.coverURL ?? "").isEmpty && (found.thumbURL ?? "").isEmpty {
                        let detail = try await hydrateMovie(found.id)
                        guard detail.id == found.id, JavVerseIdentity.code(detail.number ?? "") == JavVerseIdentity.code(source) else {
                            throw JavVerseFailure.message("详情身份不一致；拒绝替换")
                        }
                        movie = detail
                    }
                } else {
                    do {
                        let match = try await JavVerseActorResolver.resolve(name: entry.label, aliases: entry.aliases, search: actorSearch)
                        actor = match?.actor
                        if let count = match?.byVideoCount { videoCounts[entry.id] = count }
                    } catch let failure as ExternalActorResolver.Failure {
                        switch failure {
                        case .ambiguous(let found), .incomplete(let found): choices = found
                        }
                        throw failure
                    }
                    if actorHydration, let found = actor, (found.avatarURL ?? found.coverURL ?? "").isEmpty {
                        let detail = try await hydrateActor(found.id)
                        guard let detail, detail.id == found.id, JavVerseActorResolver.matches(entry.label, actor: detail) else {
                            throw JavVerseFailure.message("演员详情身份未通过；拒绝替换")
                        }
                        actor = detail
                    }
                    if let found = actor {
                        let lookup = await ActorAvatarFallback.resolveMissing(actor: found, names: JavVerseActorResolver.identity(name: entry.label, aliases: entry.aliases).queries)
                        if lookup.status == .matched { avatars[entry.id] = lookup.url }
                        else if lookup.status == .missingKey { avatarStatus[entry.id] = "未设置" }
                    }
                }
            }
            try Task.checkCancellation()
            guard generation == epoch, accountProvider() == token else { throw CancellationError() }
            movies[entry.id] = movie; actors[entry.id] = actor
            candidates[entry.id] = choices.isEmpty ? nil : choices
            let message: String
            if movie != nil { message = "已核验 AVDB 唯一身份" }
            else if let count = videoCounts[entry.id] { message = "已按作品数最多匹配（\(count)部）" }
            else if actor != nil { message = "已核验 AVDB 唯一身份" }
            else { message = "未找到：AVDB 无完整身份匹配" }
            messages[entry.id] = message
            remember(entry, movie: movie, actor: actor, choices: choices, message: message)
            completed += 1
            if cached == nil { try await pace(since: started) }
        } catch is CancellationError { return }
        catch let failure as ExternalActorResolver.Failure {
            guard !Task.isCancelled, generation == epoch, accountProvider() == token else { return }
            candidates[entry.id] = choices.isEmpty ? nil : choices
            messages[entry.id] = failure.localizedDescription
            remember(entry, movie: nil, actor: nil, choices: choices, message: failure.localizedDescription)
            completed += 1
            try? await pace(since: started)
        }
        catch {
            guard !Task.isCancelled, generation == epoch, accountProvider() == token else { return }
            messages[entry.id] = "请求/核验失败：\(error.localizedDescription)"; completed += 1
        }
    }

}

// Diagnostic only, never interpreted as a live data API. No cookies, authentication or challenge solver.
enum JavVerseHTTPProbe {
    static func status() async throws -> Int {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://javverse.com/rankings")!)
        request.httpShouldHandleCookies = false
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw JavVerseFailure.message("非HTTP响应") }
        return http.statusCode
    }
}
