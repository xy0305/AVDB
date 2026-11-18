import Foundation
import Combine

/// Build 353 matching engine: external-board entries are matched to
/// avfan by exact code (actresses by exact name) and the results are
/// persisted so a matched entry is never queried again. Misses are
/// session-only. Concurrency: up to 3 workers, each fetch also passes
/// AvfanClient's 3 lanes with ~0.4 s spacing per lane. Enqueues are
/// FIFO, so the boards enqueue in display order — the visible screen
/// matches first, the rest fills in behind it. A 403/429 from avfan
/// flips the store into degraded mode: prefetch pauses, matching
/// drops to serial, and only an explicit tap retries (once).
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
    }

    @Published private(set) var movieMatches: [String: MovieMatch] = [:]
    @Published private(set) var actorMatches: [String: ActorMatch] = [:]
    @Published private(set) var degraded = false
    @Published private(set) var busy = false

    private var movieMisses = Set<String>()
    private var actorMisses = Set<String>()
    private var movieQueue: [String] = []
    private var actorQueue: [String] = []
    private var inFlight = Set<String>()
    private var activeWorkers = 0
    private var store = Persisted()

    private let defaultsKey = "avdb.avfan.match.v1"
    private static let maxConcurrent = 3

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(Persisted.self, from: data) {
            store = decoded
            movieMatches = decoded.movies
            actorMatches = decoded.actors
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

    func isActorMiss(name: String) -> Bool {
        actorMisses.contains(name.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var statusText: String? {
        if degraded { return "avfan 暂时限流，匹配已暂停" }
        if busy { return "正在匹配 AVFan…" }
        return nil
    }

    // MARK: Enqueue (priority = call order)

    func enqueue(codes: [String]) {
        guard !degraded else { return }
        for code in codes {
            let key = Self.movieKey(code)
            guard !key.isEmpty,
                  movieMatches[key] == nil,
                  !movieMisses.contains(key),
                  !inFlight.contains(key),
                  !movieQueue.contains(key) else { continue }
            movieQueue.append(key)
        }
        pump()
    }

    /// Visible-screen entries jump the queue: not-yet-queued keys are
    /// inserted at the front, preserving their relative order.
    func prioritize(codes: [String]) {
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
        guard !degraded else { return }
        while activeWorkers < Self.maxConcurrent, !movieQueue.isEmpty || !actorQueue.isEmpty {
            activeWorkers += 1
            Task { await self.workerLoop() }
        }
    }

    private func workerLoop() async {
        while !degraded {
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
