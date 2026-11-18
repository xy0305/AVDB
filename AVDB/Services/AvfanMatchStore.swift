import Foundation
import Combine

/// Build 353 matching engine: external-board entries are matched to
/// avfan by exact code (actresses by exact name) and the results are
/// persisted so a matched entry is never queried again. Misses are
/// session-only. Enqueues are FIFO, so the boards enqueue in display
/// order — the visible screen matches first, the rest fills in
/// behind it.
/// Build 354 pacing (supersedes 353's 3 workers × 0.4 s lanes, which
/// tripped avfan's own rate limit on device): ONE serial worker, and
/// every fetch also passes AvfanClient's single 1.2 s lane. A bulk
/// enqueue accepts at most 40 new entries per call; entries beyond
/// the cap join when scrolled into view via prioritize. A 403
/// (Cloudflare) flips the store into degraded mode: prefetch pauses
/// and only an explicit tap retries (once). Avfan's own rate limit
/// (HTTP 429 / wait-page) instead pauses everything for ten minutes
/// with the queue intact and resumes by itself — persisted matches
/// keep displaying throughout the pause.
@MainActor
final class AvfanMatchStore: ObservableObject {
    static let shared = AvfanMatchStore()

    struct MovieMatch: Codable, Equatable {
        var pathID: String
        var coverURL: String?
        var title: String
    }

    struct ActorMatch: Codable, Equatable {
        var href: String
        var avatarURL: String?
    }

    private struct Persisted: Codable {
        var movies: [String: MovieMatch] = [:]
        var actors: [String: ActorMatch] = [:]
        /// Build 354: stored JavDB covers lifted from the frozen feed
        /// (tier-2 poster fallback), keyed like `movies`.
        var feedCovers: [String: String] = [:]
        var feedCoversLoaded = false

        private enum CodingKeys: String, CodingKey {
            case movies, actors, feedCovers, feedCoversLoaded
        }

        init() {}

        // decodeIfPresent throughout: a 353-era payload has no feed
        // keys and must still decode (matches are never re-queried).
        init(from decoder: Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            movies = try box.decodeIfPresent([String: MovieMatch].self, forKey: .movies) ?? [:]
            actors = try box.decodeIfPresent([String: ActorMatch].self, forKey: .actors) ?? [:]
            feedCovers = try box.decodeIfPresent([String: String].self, forKey: .feedCovers) ?? [:]
            feedCoversLoaded = try box.decodeIfPresent(Bool.self, forKey: .feedCoversLoaded) ?? false
        }
    }

    @Published private(set) var movieMatches: [String: MovieMatch] = [:]
    @Published private(set) var actorMatches: [String: ActorMatch] = [:]
    @Published private(set) var feedCoverMap: [String: String] = [:]
    @Published private(set) var degraded = false
    @Published private(set) var busy = false
    /// Build 354: while avfan's rate-limit gate is tripped, matching
    /// pauses (queue intact) until this date, then resumes by itself.
    @Published private(set) var rateLimitResumeAt: Date?

    private var movieMisses = Set<String>()
    private var actorMisses = Set<String>()
    private var movieQueue: [String] = []
    private var actorQueue: [String] = []
    private var inFlight = Set<String>()
    private var activeWorkers = 0
    private var feedCoversRequested = false
    private var recoveryTask: Task<Void, Never>?
    private var store = Persisted()

    private let defaultsKey = "avdb.avfan.match.v1"
    private static let maxConcurrent = 1
    /// Build 354: per-call cap on background pre-matching; anything
    /// beyond it waits until the user scrolls near (prioritize).
    private static let maxPrefetchPerEnqueue = 40

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(Persisted.self, from: data) {
            store = decoded
            movieMatches = decoded.movies
            actorMatches = decoded.actors
            feedCoverMap = decoded.feedCovers
        }
    }

    // MARK: Keys

    static func movieKey(_ code: String) -> String {
        code.uppercased().filter { !$0.isWhitespace }
    }

    /// MissAV slugs carry release-variant suffixes avfan does not use
    /// (AVFan's MissAVRankings rule): strip them before matching.
    static func missAVMatchCode(_ raw: String) -> String {
        var code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in ["-UNCENSORED-LEAK", "-CHINESE-SUBTITLE"] where code.uppercased().hasSuffix(suffix) {
            code = String(code.dropLast(suffix.count))
        }
        return code
    }

    // MARK: Reads

    func match(forCode code: String) -> MovieMatch? {
        movieMatches[Self.movieKey(code)]
    }

    func card(forCode code: String) -> AvfanMovieCard? {
        let key = Self.movieKey(code)
        guard let match = movieMatches[key] else { return nil }
        return AvfanMovieCard(
            pathID: match.pathID,
            href: "/movies/\(match.pathID)",
            code: key,
            title: match.title,
            coverURL: match.coverURL,
            date: nil,
            ratingText: nil,
            badges: [],
            canPlay: false
        )
    }

    func isMiss(code: String) -> Bool {
        movieMisses.contains(Self.movieKey(code))
    }

    func actorMatch(forName name: String) -> ActorMatch? {
        actorMatches[name.trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    // MARK: Stored JavDB feed covers (Build 354 tier-2 fallback)

    /// The JavDB cover the frozen pre-matching feed stored for this
    /// code (pipeline-era `match.cover`). Read-only use of that one
    /// field: it only ever feeds an image CDN URL into the poster
    /// chain — no JavDB API request is made and the 353 feed
    /// matching/routing stays removed.
    func feedCover(forCode code: String) -> String? {
        feedCoverMap[Self.movieKey(code)]
    }

    /// One-time lift of the stored covers out of the feed files that
    /// exist (MissAV/JAVLibrary/DMM-monthly were never published, so
    /// those boards simply skip this tier). The feed is frozen, so a
    /// successful lift persists and never repeats; a failed one (no
    /// file reachable) retries on a later launch.
    func ensureFeedCovers() {
        guard !feedCoversRequested else { return }
        feedCoversRequested = true
        guard !store.feedCoversLoaded else { return }
        Task { await self.loadFeedCovers() }
    }

    private func loadFeedCovers() async {
        let files: [(board: String, term: String)] = [
            ("dmm", "daily"), ("dmm", "weekly"),
            ("javranking", "explore"),
            ("zhongzhitong", "2026-09"), ("zhongzhitong", "2026-10")
        ]
        var map: [String: String] = [:]
        var loadedAny = false
        for file in files {
            guard let feed = await RankingFeedClient.load(board: file.board, term: file.term) else { continue }
            loadedAny = true
            for entry in feed.entries {
                guard entry.match.status == "matched",
                      let cover = entry.match.cover, !cover.isEmpty else { continue }
                if let code = entry.code { map[Self.movieKey(code)] = cover }
                if let number = entry.match.number { map[Self.movieKey(number)] = cover }
            }
        }
        guard loadedAny else { return }
        store.feedCovers = map
        store.feedCoversLoaded = true
        feedCoverMap = map
        persist()
    }

    // MARK: Poster movies (Build 354 cover chain)

    /// The poster Movie for a board/detail entry. Cover chain:
    /// tier 1 — MoviePosterImage's visible-HQ upgrade resolves the
    /// DMM/MGS HD portrait by number while the cell is on screen;
    /// tier 2 — the stored JavDB feed cover paints underneath;
    /// tier 3 — the avfan original cover (or the board's own
    /// fallback) when neither of the above exists. The Movie is
    /// typed as censored catalog so FrontPosterPolicy applies the
    /// standard HD/front-crop rules; HEYZO/FC2/Western numbers still
    /// resolve to original-artwork handling inside the policy.
    func posterMovie(id: String, code: String, title: String?, fallbackCover: String? = nil) -> Movie {
        let match = match(forCode: code)
        let base = feedCover(forCode: code) ?? match?.coverURL ?? fallbackCover
        return Movie(
            id: match?.pathID ?? id,
            type: "0",
            number: code,
            title: match?.title ?? title,
            coverURL: base
        )
    }

    func isActorMiss(name: String) -> Bool {
        actorMisses.contains(name.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var statusText: String? {
        if let rateLimitResumeAt {
            let minutes = max(1, Int(ceil(rateLimitResumeAt.timeIntervalSinceNow / 60)))
            return "avfan 限流中，约 \(minutes) 分钟后自动恢复（已匹配条目不受影响）"
        }
        if degraded { return "avfan 暂时限流，匹配已暂停" }
        if busy { return "正在匹配 AVFan…" }
        return nil
    }

    // MARK: Enqueue (priority = call order)

    func enqueue(codes: [String]) {
        ensureFeedCovers()
        guard !degraded else { return }
        var added = 0
        for code in codes {
            if added >= Self.maxPrefetchPerEnqueue { break }
            let key = Self.movieKey(code)
            guard !key.isEmpty,
                  movieMatches[key] == nil,
                  !movieMisses.contains(key),
                  !inFlight.contains(key),
                  !movieQueue.contains(key) else { continue }
            movieQueue.append(key)
            added += 1
        }
        pump()
    }

    /// Visible-screen entries jump the queue: not-yet-queued keys are
    /// inserted at the front, preserving their relative order.
    func prioritize(codes: [String]) {
        ensureFeedCovers()
        guard !degraded else { return }
        var front: [String] = []
        for code in codes {
            let key = Self.movieKey(code)
            guard !key.isEmpty,
                  movieMatches[key] == nil,
                  !movieMisses.contains(key),
                  !inFlight.contains(key),
                  !movieQueue.contains(key) else { continue }
            front.append(key)
        }
        if !front.isEmpty {
            movieQueue.insert(contentsOf: front, at: 0)
        }
        pump()
    }

    func enqueueActor(name: String) {
        guard !degraded else { return }
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty,
              actorMatches[key] == nil,
              !actorMisses.contains(key),
              !inFlight.contains("actor:" + key),
              !actorQueue.contains(key) else { return }
        actorQueue.append(key)
        pump()
    }

    private func pump() {
        busy = !movieQueue.isEmpty || !actorQueue.isEmpty || activeWorkers > 0
        guard !degraded, rateLimitResumeAt == nil else { return }
        while activeWorkers < Self.maxConcurrent, !movieQueue.isEmpty || !actorQueue.isEmpty {
            activeWorkers += 1
            Task { await self.workerLoop() }
        }
    }

    private func workerLoop() async {
        while !degraded, rateLimitResumeAt == nil {
            if let key = dequeueMovie() {
                await resolveMovie(key: key)
            } else if let name = dequeueActor() {
                await resolveActor(name: name)
            } else {
                break
            }
        }
        activeWorkers -= 1
        busy = !movieQueue.isEmpty || !actorQueue.isEmpty || activeWorkers > 0
    }

    private func dequeueMovie() -> String? {
        guard !movieQueue.isEmpty else { return nil }
        let key = movieQueue.removeFirst()
        inFlight.insert(key)
        return key
    }

    private func dequeueActor() -> String? {
        guard !actorQueue.isEmpty else { return nil }
        let name = actorQueue.removeFirst()
        inFlight.insert("actor:" + name)
        return name
    }

    // MARK: Resolution

    private func resolveMovie(key: String) async {
        defer { inFlight.remove(key) }
        do {
            let url = await AvfanClient.shared.searchURL(query: key, st: "all")
            let html = try await AvfanClient.shared.html(for: url, expectCatalog: true)
            let cards = await AvfanHTMLParser.detached { AvfanHTMLParser.movieCards(in: html) }
            if let hit = cards.first(where: { $0.code.map(Self.movieKey) == key }) {
                let match = MovieMatch(pathID: hit.pathID, coverURL: hit.coverURL, title: hit.title)
                movieMatches[key] = match
                store.movies[key] = match
                persist()
            } else {
                movieMisses.insert(key)
            }
        } catch let error as AvfanError {
            if case .blocked = error {
                enterDegraded()
            } else if case .rateLimited = error {
                // Not a miss: the entry goes back to the front of
                // the queue and waits out the pause.
                if movieMatches[key] == nil, !movieQueue.contains(key) {
                    movieQueue.insert(key, at: 0)
                }
                enterRateLimitPause()
            } else {
                movieMisses.insert(key)
            }
        } catch {
            movieMisses.insert(key)
        }
    }

    private func resolveActor(name: String) async {
        defer { inFlight.remove("actor:" + name) }
        do {
            let url = await AvfanClient.shared.searchURL(query: name, st: "cast")
            let html = try await AvfanClient.shared.html(for: url, expectCatalog: true)
            let cards = await AvfanHTMLParser.detached { AvfanHTMLParser.castCards(in: html) }
            let hit = cards.first(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) == name })
                ?? cards.first(where: { $0.name.contains(name) })
            if let hit {
                let match = ActorMatch(href: hit.href, avatarURL: hit.avatarURL)
                actorMatches[name] = match
                store.actors[name] = match
                persist()
            } else {
                actorMisses.insert(name)
            }
        } catch let error as AvfanError {
            if case .blocked = error {
                enterDegraded()
            } else if case .rateLimited = error {
                if actorMatches[name] == nil, !actorQueue.contains(name) {
                    actorQueue.insert(name, at: 0)
                }
                enterRateLimitPause()
            } else {
                actorMisses.insert(name)
            }
        } catch {
            actorMisses.insert(name)
        }
    }

    /// Explicit user intent (a tap on an unmatched entry): one serial
    /// attempt even in degraded mode. Returns the fresh match if any.
    func resolveNow(code: String) async -> MovieMatch? {
        ensureFeedCovers()
        let key = Self.movieKey(code)
        if let existing = movieMatches[key] { return existing }
        guard !inFlight.contains(key) else { return nil }
        inFlight.insert(key)
        await resolveMovie(key: key)
        inFlight.remove(key)
        return movieMatches[key]
    }

    func resolveActorNow(name: String) async -> ActorMatch? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = actorMatches[key] { return existing }
        guard !inFlight.contains("actor:" + key) else { return nil }
        inFlight.insert("actor:" + key)
        await resolveActor(name: key)
        inFlight.remove("actor:" + key)
        return actorMatches[key]
    }

    /// Manual retry for a session miss (the grids' retry button):
    /// clears the miss and re-queues the entry.
    func retry(code: String) {
        let key = Self.movieKey(code)
        movieMisses.remove(key)
        if degraded {
            Task { _ = await resolveNow(code: code) }
        } else {
            enqueue(codes: [code])
        }
    }

    func retryActor(name: String) {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
        actorMisses.remove(key)
        if degraded {
            Task { _ = await resolveActorNow(name: name) }
        } else {
            enqueueActor(name: name)
        }
    }

    /// Build 354: avfan's rate limit pauses everything for ten
    /// minutes. The queue is kept (unlike the Cloudflare degraded
    /// path), nothing probes the site meanwhile, and a recovery task
    /// resumes pumping on its own when the cooldown ends. The resume
    /// date is set synchronously so the worker loop stops at once;
    /// it is a moment after the client's own gate, so recovery never
    /// fires early.
    private func enterRateLimitPause() {
        if rateLimitResumeAt == nil {
            rateLimitResumeAt = Date().addingTimeInterval(AvfanClient.rateLimitCooldown)
        }
        recoveryTask?.cancel()
        let resume = rateLimitResumeAt ?? Date()
        let wait = max(1, resume.timeIntervalSinceNow)
        recoveryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.rateLimitResumeAt = nil
            self.pump()
        }
    }

    private func enterDegraded() {
        degraded = true
        // Paused prefetch: queued (not yet started) entries are dropped
        // without recording misses, so a later screen can retry them.
        for key in movieQueue { inFlight.remove(key) }
        for name in actorQueue { inFlight.remove("actor:" + name) }
        movieQueue.removeAll()
        actorQueue.removeAll()
        busy = false
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(store) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
