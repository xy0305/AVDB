import Foundation
import Combine

struct JavVerseSnapshot: Decodable {
    let schemaVersion: Int
    let mode: String
    let origin: String
    let preparedAt: String
    let boards: [JavVerseBoard]
    let grok: JavVerseGrokSnapshot?
    // Resource decoding is independent from image/network mapping; warm navigation reuses metadata.
    private static var cachedBundle: Self?
    static func bundled(in bundle: Bundle = .main) throws -> Self {
        if bundle == .main, let cachedBundle { return cachedBundle }
        guard let url = bundle.url(forResource: "JavVerseSnapshot", withExtension: "json") else {
            throw JavVerseFailure.message("缺少 JavVerseSnapshot.json 离线资源")
        }
        let value = try decode(Data(contentsOf: url))
        if bundle == .main { cachedBundle = value }
        return value
    }
    static func decode(_ data: Data) throws -> Self {
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
        JavVerseEntry(rank: rank, kind: "actor", label: nameJa,
                      sourceURL: "https://javverse.com/actress/\(actressId)", code: nil)
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
    var id: String { "\(rank)|\(kind)|\(sourceURL)|\(label)" }
}
enum JavVerseFailure: LocalizedError {
    case message(String)
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
    @Published private(set) var messages: [String: String] = [:]
    @Published private(set) var busy = false
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    private struct Cached { let movie: Movie?; let actor: Actor?; let date: Date }
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
        cancel(); movies.removeAll(); actors.removeAll(); messages.removeAll(); account = accountProvider()
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
    private func key(_ entry: JavVerseEntry) -> String {
        let identity = entry.kind == "movie" ? (entry.code.flatMap(JavVerseIdentity.code) ?? entry.label) : entry.label
        return "\(scope)|\(JavDBConstants.baseURL)|\(account ?? "<anonymous>")|\(entry.kind)|\(identity)"
    }
    @discardableResult
    func resolve(_ entries: [JavVerseEntry], retry: Bool = false) -> Task<Void, Never>? {
        guard !busy else { return nil }
        if account != accountProvider() { clear() }
        let epoch = generation, token = account
        // A finite visible page/home section only, serial, never append an infinite scroll queue.
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
            for entry in batch {
                do {
                    try Task.checkCancellation()
                    guard self.generation == epoch, self.accountProvider() == token else { throw CancellationError() }
                    let cacheKey = self.key(entry)
                    var cached = self.sharedCache ? Self.cache[cacheKey] : nil
                    if let value = cached, Date().timeIntervalSince(value.date) > 600 { cached = nil }
                    self.messages[entry.id] = "请求中…"
                    var movie = cached?.movie; var actor = cached?.actor
                    if cached == nil {
                        if entry.kind == "movie" {
                            guard let source = entry.code else { throw JavVerseFailure.message("原始完整番号不可核验") }
                            movie = try await JavVerseMovieResolver.resolve(code: source) { source, page in
                                try Task.checkCancellation()
                                guard self.generation == epoch, self.accountProvider() == token else { throw CancellationError() }
                                return try await self.search(source, page)
                            }
                            if self.movieHydration, let found = movie, (found.coverURL ?? "").isEmpty && (found.thumbURL ?? "").isEmpty {
                                let detail = try await self.hydrateMovie(found.id)
                                guard detail.id == found.id, JavVerseIdentity.code(detail.number ?? "") == JavVerseIdentity.code(source) else {
                                    throw JavVerseFailure.message("详情身份不一致；拒绝替换")
                                }
                                movie = detail
                            }
                        } else {
                            actor = try await JavVerseActorResolver.resolve(name: entry.label, search: self.actorSearch)
                            if self.actorHydration, let found = actor, (found.avatarURL ?? found.coverURL ?? "").isEmpty {
                                let detail = try await self.hydrateActor(found.id)
                                guard let detail, detail.id == found.id, JavVerseActorResolver.matches(entry.label, actor: detail) else {
                                    throw JavVerseFailure.message("演员详情身份未通过；拒绝替换")
                                }
                                actor = detail
                            }
                        }
                    }
                    try Task.checkCancellation()
                    guard self.generation == epoch, self.accountProvider() == token else { throw CancellationError() }
                    self.movies[entry.id] = movie; self.actors[entry.id] = actor
                    self.messages[entry.id] = movie != nil || actor != nil ? "已核验 AVDB 唯一身份" : "未找到：AVDB 无完整身份匹配"
                    // Only successful identities cached; errors/absence explicitly retryable.
                    if self.sharedCache && (movie != nil || actor != nil) {
                        Self.cache[cacheKey] = Cached(movie: movie, actor: actor, date: Date())
                        Self.order.removeAll { $0 == cacheKey }; Self.order.append(cacheKey)
                        while Self.order.count > 160 { Self.cache.removeValue(forKey: Self.order.removeFirst()) }
                    }
                    self.completed += 1
                    try await Task.sleep(nanoseconds: 180_000_000)
                } catch is CancellationError { return }
                catch {
                    guard !Task.isCancelled, self.generation == epoch, self.accountProvider() == token else { return }
                    self.messages[entry.id] = "请求/核验失败：\(error.localizedDescription)"; self.completed += 1
                }
            }
        }
        return task
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
