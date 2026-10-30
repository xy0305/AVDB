//
//  RecommendationStore.swift
//  AVDB
//
//  Build 281 「为你推荐」 state: local signals → profile → candidate sourcing (rate-limited) → ranking,
//  computed off the main thread and cached on device. No upload, no server, no login prompts.
//

import Foundation
import Combine

struct RecSeed: Hashable, Sendable { var id: String; var number: String }

/// Local, already-on-device inputs (观看历史 / 稍后再看 / 关注 / feedback).
struct RecSnapshot: Sendable {
    var signals: [RecSignal]
    var follows: [RecFeature]
    var recentPositives: [RecSeed]
    /// Movies whose detail metadata is worth having (history / favourites), newest first.
    var seedItems: [RecItem]
}

/// App side: JavDB + local stores. The screenshot host provides a fixture implementation.
protocol RecommendationSource: AnyObject {
    @MainActor func snapshot(feedback: [RecSignal], playCounts: [String: Int], since: Date?) -> RecSnapshot
    func detail(_ id: String) async throws -> RecItem
    func list(_ request: RecSourcingPlan.Request) async throws -> [RecItem]
    /// Seconds between two network requests (0 for fixtures).
    var requestSpacing: Double { get }
}

struct RecPreferenceSummary: Equatable, Sendable {
    struct Community: Equatable, Sendable, Identifiable { var id: Int; var weight: Double; var names: [String] }
    var actors: [RecPreference] = []
    var tags: [RecPreference] = []
    var series: [RecPreference] = []
    var makers: [RecPreference] = []
    var negatives: [RecPreference] = []
    var communities: [Community] = []
    var positiveItems = 0
    var explicitSignals = 0
    var coldStart = true
}

enum RecFeedbackAction: String, Sendable {
    case like, notInterested, lessActor, lessTag, lessSeries
}

enum RecommendationLimits {
    static let metadataCap = 1500
    static let poolCap = 40
    static let feedbackCap = 500
    static let shownCap = 300
    static let poolTTL: TimeInterval = 12 * 3600
    static let autoRefreshInterval: TimeInterval = 6 * 3600
    static let maxConsecutiveFailures = 3
    static func requestBudget(manual: Bool) -> Int { manual ? 10 : 7 }
    static func detailBudget(manual: Bool) -> Int { manual ? 10 : 6 }

    /// LRU by fetchedAt, but never evict items the user interacted with.
    static func capMetadata(_ items: [String: RecItem], keep: Set<String>, cap: Int = metadataCap) -> [String: RecItem] {
        guard items.count > cap else { return items }
        let evictable = items.values.filter { !keep.contains($0.id) }.sorted { $0.fetchedAt < $1.fetchedAt }
        var out = items
        for item in evictable.prefix(items.count - cap) { out.removeValue(forKey: item.id) }
        return out
    }
}

@MainActor
final class RecommendationStore: ObservableObject {
    static let shared = RecommendationStore(source: RecommendationSourceRegistry.make())

    struct Pool: Codable { var ids: [String]; var fetchedAt: Date; var source: RecCandidateSource; var via: String; var viaName: String }
    struct CacheFile: Codable {
        var items: [String: RecItem] = [:]
        var pools: [String: Pool] = [:]
        var results: [RecResult] = []
        var coldStart = true
        var updatedAt: Date? = nil
        var shownX: [String: [Double]] = [:]
        var trained: [String] = []
        var playCounts: [String: Int] = [:]
        var lastPlayedAt: [String: Date] = [:]
    }

    @Published private(set) var hero: RecResult?
    @Published private(set) var groups: [RecGroup] = []
    @Published private(set) var results: [RecResult] = []
    @Published private(set) var coldStart = true
    @Published private(set) var isRefreshing = false
    @Published private(set) var status: String?
    @Published private(set) var updatedAt: Date?
    @Published private(set) var summary = RecPreferenceSummary()
    @Published private(set) var ranker = RecRanker()

    private let source: RecommendationSource
    private let defaults: UserDefaults
    private let fileURL: URL?
    private var cache = CacheFile()
    private var feedback: [RecSignal] = []
    private var resetAt: Date?
    private var task: Task<Void, Never>?

    static let feedbackKey = "avdb.rec.feedback.v1"
    static let rankerKey = "avdb.rec.ranker.v1"
    static let resetKey = "avdb.rec.resetAt.v1"

    init(source: RecommendationSource, defaults: UserDefaults = .standard, fileURL: URL? = RecommendationStore.defaultFileURL()) {
        self.source = source
        self.defaults = defaults
        self.fileURL = fileURL
        feedback = defaults.data(forKey: Self.feedbackKey).flatMap { try? JSONDecoder().decode([RecSignal].self, from: $0) } ?? []
        ranker = defaults.data(forKey: Self.rankerKey).flatMap { try? JSONDecoder().decode(RecRanker.self, from: $0) } ?? RecRanker()
        resetAt = defaults.object(forKey: Self.resetKey) as? Date
        if let fileURL, let data = try? Data(contentsOf: fileURL), let decoded = try? JSONDecoder().decode(CacheFile.self, from: data) {
            cache = decoded
            publish(results: decoded.results, coldStart: decoded.coldStart)
            updatedAt = decoded.updatedAt
        }
    }

    nonisolated static func defaultFileURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("avdb-recommender-v1.json")
    }

    var hasContent: Bool { hero != nil }

    /// Called on appear (cached result reused for 6 h) and by pull-to-refresh (manual).
    func refresh(manual: Bool) {
        if !manual, let updatedAt, Date().timeIntervalSince(updatedAt) < RecommendationLimits.autoRefreshInterval, hasContent { return }
        guard task == nil else { return }
        isRefreshing = true
        status = manual ? "正在更新推荐…" : nil
        task = Task { [weak self] in
            await self?.run(manual: manual)
            self?.task = nil
            self?.isRefreshing = false
        }
    }

    /// Pull-to-refresh: start (or join) a manual run and wait for it.
    func refreshNow() async {
        refresh(manual: true)
        await task?.value
    }

    private func run(manual: Bool) async {
        let now = Date()
        updatePlayCounts()
        let snapshot = source.snapshot(feedback: feedback, playCounts: cache.playCounts, since: resetAt)
        trainFromHistory(snapshot.signals)
        // Seed metadata: local items always known at list level; fetch details for the newest unknown ones.
        for item in snapshot.seedItems { cache.items[item.id] = (cache.items[item.id].map { $0.merged(with: item) }) ?? item }
        var failures = 0
        var requests = 0
        func spaced() async { if requests > 0, source.requestSpacing > 0 { try? await Task.sleep(nanoseconds: UInt64(source.requestSpacing * 1_000_000_000)) } }
        let needDetail = snapshot.seedItems.filter { cache.items[$0.id]?.detailed != true }.prefix(RecommendationLimits.detailBudget(manual: manual))
        for seed in needDetail where failures < RecommendationLimits.maxConsecutiveFailures {
            if Task.isCancelled { return }
            await spaced(); requests += 1
            do { let d = try await source.detail(seed.id); cache.items[d.id] = (cache.items[d.id].map { $0.merged(with: d) }) ?? d; failures = 0 }
            catch { failures += 1 }
        }
        var items = cache.items
        var profile = await Self.computeProfile(snapshot.signals, items: items, now: now)
        // Candidate sourcing within a request budget; fresh pools are reused.
        let plan = RecSourcingPlan.make(profile: profile, follows: snapshot.follows,
                                        recentPositives: snapshot.recentPositives.map { ($0.id, $0.number) },
                                        budget: RecommendationLimits.requestBudget(manual: manual) + 2)
        var listCalls = 0
        for request in plan where failures < RecommendationLimits.maxConsecutiveFailures {
            if Task.isCancelled { return }
            if let pool = cache.pools[request.key], now.timeIntervalSince(pool.fetchedAt) < RecommendationLimits.poolTTL, !manual { continue }
            guard listCalls < RecommendationLimits.requestBudget(manual: manual) else { break }
            await spaced(); requests += 1; listCalls += 1
            do {
                let found = try await source.list(request)
                for f in found { cache.items[f.id] = (cache.items[f.id].map { $0.merged(with: f) }) ?? f }
                cache.pools[request.key] = Pool(ids: found.map(\.id), fetchedAt: now, source: request.source, via: request.id, viaName: request.name)
                failures = 0
            } catch { failures += 1 }
        }
        // Follow feed (280) is in-network without any request.
        let planKeys = Set(plan.map(\.key))
        var candidates: [RecCandidate] = []
        for (key, pool) in cache.pools where planKeys.contains(key) || now.timeIntervalSince(pool.fetchedAt) < RecommendationLimits.poolTTL {
            for id in pool.ids { if let item = cache.items[id] { candidates.append(RecCandidate(item: item, source: pool.source, via: pool.via, viaName: pool.viaName)) } }
        }
        let followKeys = Set(snapshot.follows.map(\.key))
        candidates = candidates.map { c in
            var c = c
            if c.item.features.contains(where: { followKeys.contains($0.key) }) && (c.source == .actor || c.source == .series || c.source == .maker) { c.source = .follow }
            return c
        }
        items = cache.items
        var output = await Self.computeOutput(candidates, signals: snapshot.signals, items: items, ranker: ranker, now: now)
        // Detail-hydrate the top of the feed (tags / actresses for reasons + embeddings), then re-rank once.
        let top = output.results.prefix(12).filter { cache.items[$0.id]?.detailed != true }.prefix(RecommendationLimits.detailBudget(manual: manual))
        var hydrated = false
        for r in top where failures < RecommendationLimits.maxConsecutiveFailures {
            if Task.isCancelled { return }
            await spaced(); requests += 1
            do { let d = try await source.detail(r.id); cache.items[d.id] = (cache.items[d.id].map { $0.merged(with: d) }) ?? d; failures = 0; hydrated = true }
            catch { failures += 1 }
        }
        if hydrated {
            items = cache.items
            candidates = candidates.map { c in var c = c; if let i = items[c.item.id] { c.item = i }; return c }
            output = await Self.computeOutput(candidates, signals: snapshot.signals, items: items, ranker: ranker, now: now)
            profile = await Self.computeProfile(snapshot.signals, items: items, now: now)
        }
        // Persist (capped) and publish.
        for r in output.results { cache.shownX[r.id] = r.x }
        if cache.shownX.count > RecommendationLimits.shownCap { cache.shownX = Dictionary(uniqueKeysWithValues: cache.shownX.sorted { $0.key < $1.key }.suffix(RecommendationLimits.shownCap).map { ($0.key, $0.value) }) }
        let keep = Set(snapshot.signals.compactMap(\.movieID)).union(output.results.map(\.id))
        cache.items = RecommendationLimits.capMetadata(cache.items, keep: keep)
        if cache.pools.count > RecommendationLimits.poolCap {
            for (k, _) in cache.pools.sorted(by: { $0.value.fetchedAt < $1.value.fetchedAt }).prefix(cache.pools.count - RecommendationLimits.poolCap) { cache.pools.removeValue(forKey: k) }
        }
        cache.results = output.results
        cache.coldStart = output.coldStart
        cache.updatedAt = Date()
        publish(results: output.results, coldStart: output.coldStart)
        let finalProfile = profile, finalItems = items
        summary = await Task.detached(priority: .utility) {
            Self.summarize(finalProfile, clusters: RecClusters.build(items: Array(finalItems.values), focus: Set(finalProfile.affinity.keys)))
        }.value
        updatedAt = cache.updatedAt
        status = failures >= RecommendationLimits.maxConsecutiveFailures ? "网络或 JavDB 暂时不可用，显示的是已缓存的推荐" : nil
        persist()
    }

    nonisolated static func computeProfile(_ signals: [RecSignal], items: [String: RecItem], now: Date) async -> RecProfile {
        await Task.detached(priority: .utility) {
            let all = Array(items.values)
            let index = RecIndex(items: all)
            let clusters = RecClusters.build(items: all)
            return RecProfile.build(signals: signals, items: items, index: index, clusters: clusters, now: now)
        }.value
    }

    nonisolated static func computeOutput(_ candidates: [RecCandidate], signals: [RecSignal], items: [String: RecItem], ranker: RecRanker, now: Date) async -> RecOutput {
        await Task.detached(priority: .utility) {
            let all = Array(items.values)
            let index = RecIndex(items: all)
            let profile0 = RecProfile.build(signals: signals, items: items, index: index, clusters: RecClusters(), now: now)
            let clusters = RecClusters.build(items: all, focus: Set(profile0.affinity.keys))
            let profile = RecProfile.build(signals: signals, items: items, index: index, clusters: clusters, now: now)
            return RecommenderPipeline.rank(candidates: candidates, profile: profile, ranker: ranker, index: index, clusters: clusters, now: now)
        }.value
    }

    nonisolated static func summarize(_ p: RecProfile, clusters: RecClusters) -> RecPreferenceSummary {
        var s = RecPreferenceSummary()
        s.actors = p.top(.actor, limit: 8)
        s.tags = p.top(.tag, limit: 14)
        s.series = p.top(.series, limit: 5)
        s.makers = Array((p.top(.maker, limit: 4) + p.top(.director, limit: 2)).sorted { $0.weight > $1.weight }.prefix(5))
        s.negatives = p.top(nil, limit: 8, positive: false)
        s.communities = p.communities.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(4).compactMap { id, w in
            let names = (clusters.members[id] ?? []).compactMap { p.names[$0] }.prefix(4)
            return names.isEmpty ? nil : RecPreferenceSummary.Community(id: id, weight: w, names: Array(names))
        }
        s.positiveItems = p.positiveItems
        s.explicitSignals = p.explicitPositives + p.lessFeatures.count + p.dislikedItems.count
        s.coldStart = p.isColdStart
        return s
    }

    private func publish(results: [RecResult], coldStart: Bool) {
        self.results = results
        self.coldStart = coldStart
        hero = results.first
        groups = RecommenderPipeline.group(Array(results.dropFirst()))
    }

    // MARK: Feedback (X: explicit negative feedback + online model update)

    func feedback(_ action: RecFeedbackAction, on result: RecResult) {
        let now = Date()
        switch action {
        case .like:
            feedback.append(RecSignal(kind: .like, movieID: result.id, at: now))
            ranker.update(result.x, label: 1)
        case .notInterested:
            feedback.append(RecSignal(kind: .dislike, movieID: result.id, at: now))
            ranker.update(result.x, label: 0)
        case .lessActor:
            guard let a = result.item.primaryActor else { return }
            feedback.append(RecSignal(kind: .lessFeature, featureKey: a.key, featureName: a.name, at: now))
            ranker.update(result.x, label: 0, rate: RecRanker.learningRate / 2)
        case .lessTag:
            guard let t = Self.topTag(result) else { return }
            feedback.append(RecSignal(kind: .lessFeature, featureKey: t.key, featureName: t.name, at: now))
            ranker.update(result.x, label: 0, rate: RecRanker.learningRate / 2)
        case .lessSeries:
            guard let s = result.item.primarySeries else { return }
            feedback.append(RecSignal(kind: .lessFeature, featureKey: s.key, featureName: s.name, at: now))
            ranker.update(result.x, label: 0, rate: RecRanker.learningRate / 2)
        }
        if feedback.count > RecommendationLimits.feedbackCap { feedback.removeFirst(feedback.count - RecommendationLimits.feedbackCap) }
        // Apply immediately to what is on screen, then re-rank quietly in the background.
        if action != .like {
            let drop = Self.dropPredicate(action, result)
            let kept = results.filter { !drop($0) }
            publish(results: kept, coldStart: coldStart)
            cache.results = kept
        }
        persistFeedback(); persist()
    }

    nonisolated static func topTag(_ r: RecResult) -> RecFeature? {
        r.item.features(.tag).first { r.reason.text.contains($0.name) } ?? r.item.features(.tag).first
    }

    nonisolated static func dropPredicate(_ action: RecFeedbackAction, _ r: RecResult) -> (RecResult) -> Bool {
        switch action {
        case .like: return { _ in false }
        case .notInterested: return { $0.id == r.id }
        case .lessActor: let k = r.item.primaryActor?.key; return { $0.id == r.id || ($0.item.primaryActor?.key == k && k != nil) }
        case .lessSeries: let k = r.item.primarySeries?.key; return { $0.id == r.id || ($0.item.primarySeries?.key == k && k != nil) }
        case .lessTag: let k = topTag(r)?.key; return { $0.id == r.id || ($0.reason.groupKey == k && k != nil) }
        }
    }

    /// Metadata seen elsewhere in the app (detail page). Persisted with the next refresh.
    func remember(_ item: RecItem) {
        guard !item.id.isEmpty else { return }
        cache.items[item.id] = (cache.items[item.id].map { $0.merged(with: item) }) ?? item
    }

    func removeNegative(_ key: String) {
        feedback.removeAll { $0.featureKey == key && $0.kind == .lessFeature }
        persistFeedback()
        summary.negatives.removeAll { $0.key == key }
    }

    /// 「重置偏好」: forget feedback + learned weights, ignore earlier history, keep the metadata cache.
    func reset() {
        task?.cancel(); task = nil; isRefreshing = false
        feedback = []; ranker = RecRanker(); resetAt = Date()
        defaults.set(resetAt, forKey: Self.resetKey)
        cache.results = []; cache.shownX = [:]; cache.trained = []; cache.playCounts = [:]; cache.updatedAt = nil
        publish(results: [], coldStart: true)
        summary = RecPreferenceSummary()
        persistFeedback(); persist()
        refresh(manual: true)
    }

    // MARK: Learning from what was watched

    private func updatePlayCounts() {
        for s in source.snapshot(feedback: [], playCounts: [:], since: resetAt).signals where s.kind == .watch {
            guard let id = s.movieID else { continue }
            if let last = cache.lastPlayedAt[id], s.at.timeIntervalSince(last) > 1800 { cache.playCounts[id, default: 1] += 1 }
            else if cache.lastPlayedAt[id] == nil { cache.playCounts[id] = cache.playCounts[id] ?? 1 }
            cache.lastPlayedAt[id] = max(cache.lastPlayedAt[id] ?? .distantPast, s.at)
        }
    }

    /// A shown recommendation that was then watched ≥ 50 % is a positive label; a quick bail a negative one.
    private func trainFromHistory(_ signals: [RecSignal]) {
        var trained = Set(cache.trained)
        for s in signals where s.kind == .watch {
            guard let id = s.movieID, let x = cache.shownX[id], !trained.contains(id), let r = s.ratio else { continue }
            if r >= 0.5 { ranker.update(x, label: 1) } else if r < RecSignalWeights.quickBailRatio { ranker.update(x, label: 0) } else { continue }
            trained.insert(id)
        }
        cache.trained = Array(trained.sorted().suffix(RecommendationLimits.shownCap))
        persistFeedback()
    }

    private func persistFeedback() {
        if let d = try? JSONEncoder().encode(feedback) { defaults.set(d, forKey: Self.feedbackKey) }
        if let d = try? JSONEncoder().encode(ranker) { defaults.set(d, forKey: Self.rankerKey) }
    }

    private func persist() {
        guard let fileURL else { return }
        let snapshot = cache
        Task.detached(priority: .background) {
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: fileURL, options: .atomic) }
        }
    }

}
