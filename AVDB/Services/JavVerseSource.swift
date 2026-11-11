import Foundation
import Combine

// Ranked-entry resolution shared by the external ranking sources (DMM):
// entries are matched to AVDB movies/actors by exact identity only.
// Build 336 removed the JavVerse ranking itself (view, live client,
// snapshot boards, Grok board, release probe); this resolution layer
// stays because DMMRankingView builds its rows on it.
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
    private let preferExactMovie: Bool
    private let accountProvider: @MainActor () -> String?
    private let scope: String
    init(scope: String = "javverse|legacy", search: JavVerseMovieResolver.Search? = nil,
         actorSearch: JavVerseActorResolver.Search? = nil,
         hydrateMovie: (@MainActor (String) async throws -> Movie)? = nil,
         hydrateActor: (@MainActor (String) async throws -> Actor?)? = nil,
         shareCache: Bool? = nil,
         accountProvider: @escaping @MainActor () -> String? = { APIClient.shared.token }) {
        self.scope = scope
        // Production (nil search) uses JavDBSDK.exactMovie: exact identity, stops on first unique page.
        self.preferExactMovie = search == nil
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
        guard !busy else { return nil }
        if account != accountProvider() { clear() }
        let epoch = generation, token = account
        // Current visible page only. At most four requests run together; paging cancels this generation.
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
                    group.addTask { @MainActor in await self.verify(entry, epoch: epoch, token: token, throttled: !retry) }
                }
                startNext(); startNext(); startNext(); startNext()
                while await group.next() != nil {
                    if Task.isCancelled || self.generation != epoch { break }
                    startNext()
                }
            }
        }
        return task
    }
    private func verify(_ entry: JavVerseEntry, epoch: UUID, token: String?, throttled: Bool) async {
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
                // Build 337: automatic page verifications pass the shared
                // throttle; retry taps (throttled == false) are the user's
                // own action and go straight through.
                var gateHeld = false
                if throttled {
                    guard await VerificationThrottle.acquire() else { return }
                    gateHeld = true
                }
                defer { if gateHeld { VerificationThrottle.release() } }
                if entry.kind == "movie" {
                    guard let source = entry.code else { throw JavVerseFailure.message("原始完整番号不可核验") }
                    if preferExactMovie {
                        // Fail-closed exact identity via SDK; early-exit on first unique page (never fuzzy first-hit).
                        do {
                            movie = try await JavDBSDK.shared.exactMovie(code: source)
                        } catch let error as JRError {
                            throw JavVerseFailure.message(error.errorDescription ?? "番号核验失败")
                        }
                    } else {
                        movie = try await JavVerseMovieResolver.resolve(code: source) { source, page in
                            try Task.checkCancellation()
                            guard self.generation == epoch, self.accountProvider() == token else { throw CancellationError() }
                            return try await self.search(source, page)
                        }
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
