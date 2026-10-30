// Build 281 store regression with a fixture source (no network): refresh, feedback, reset.
import Foundation

final class FixtureRecSource: RecommendationSource {
    var requestSpacing: Double { 0 }
    var listCalls = 0, detailCalls = 0
    var cold = false
    func f(_ k: RecFeatureKind, _ id: String, _ n: String) -> RecFeature { RecFeature(kind: k, id: id, name: n) }
    func movie(_ id: String, actor: (String, String), tags: [(String, String)], series: (String, String)? = nil) -> RecItem {
        var fs = [f(.actor, actor.0, actor.1)] + tags.map { f(.tag, $0.0, $0.1) }
        if let series { fs.append(f(.series, series.0, series.1)) }
        return RecItem(id: id, number: id.uppercased(), title: "作品 " + id, type: "0", coverURL: "https://c/\(id)", releaseDate: "2026-10-01", rating: 4.2, popularity: 300, features: fs, detailed: true, fetchedAt: Date())
    }
    @MainActor func snapshot(feedback: [RecSignal], playCounts: [String: Int], since: Date?) -> RecSnapshot {
        let floor = since ?? .distantPast
        let watched = cold ? ["w0"] : ["w0", "w1", "w2", "w3"]
        let signals = watched.enumerated().map { RecSignal(kind: .watch, movieID: $0.element, ratio: 0.9, at: Date().addingTimeInterval(Double(-$0.offset) * 3600)) }.filter { $0.at > floor }
        return RecSnapshot(signals: signals + feedback.filter { $0.at > floor }, follows: [], recentPositives: [RecSeed(id: "w0", number: "W0")],
                           seedItems: watched.map { RecItem(id: $0, number: $0.uppercased(), title: "") })
    }
    func detail(_ id: String) async throws -> RecItem {
        detailCalls += 1
        return movie(id, actor: ("1", "三上悠亚"), tags: [("10", "黑丝"), ("11", "美脚")], series: ("100", "绝顶系列"))
    }
    func list(_ r: RecSourcingPlan.Request) async throws -> [RecItem] {
        listCalls += 1
        switch r.source {
        case .actor: return (0..<6).map { movie("a\(r.id)-\($0)", actor: (r.id, r.name), tags: [("10", "黑丝")]) }
        case .popular, .latest: return (0..<6).map { movie("p\($0)", actor: ("9\($0)", "新人\($0)"), tags: [("20", "剧情")]) }
        default: return (0..<4).map { movie("\(r.source.rawValue)\(r.id)-\($0)", actor: ("5\($0)", "演员\($0)"), tags: [("10", "黑丝"), ("12", "OL")]) }
        }
    }
}

@MainActor func storeTests() async {
    let suite = "rec281." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(suite + ".json")
    let src = FixtureRecSource()
    let store = RecommendationStore(source: src, defaults: defaults, fileURL: file)
    await store.refreshNow()
    check(store.hero != nil && !store.coldStart, "store produced a warm feed")
    check(src.listCalls <= RecommendationLimits.requestBudget(manual: true), "list budget \(src.listCalls)")
    check(src.detailCalls <= 2 * RecommendationLimits.detailBudget(manual: true), "detail budget \(src.detailCalls)")
    check(!store.summary.actors.isEmpty && store.summary.actors.first?.name == "三上悠亚", "preference summary")
    check(!store.results.contains { ["w0", "w1", "w2", "w3"].contains($0.id) }, "watched items not recommended")
    let calls = src.listCalls
    store.refresh(manual: false)                                         // fresh cache: no new run
    check(src.listCalls == calls && !store.isRefreshing, "auto refresh reuses cache")
    let target = store.results.first { $0.item.primaryActor != nil }!
    let actorKey = target.item.primaryActor!.key
    store.feedback(.lessActor, on: target)
    check(!store.results.contains { $0.item.primaryActor?.key == actorKey }, "少推该女优 applies immediately")
    let other = store.results.first!
    store.feedback(.notInterested, on: other)
    check(!store.results.contains { $0.id == other.id }, "不感兴趣 removes the item")
    let updates = store.ranker.updates
    store.feedback(.like, on: store.results.first!)
    check(store.ranker.updates == updates + 1, "like trains the ranker")
    await store.refreshNow()
    check(!store.results.contains { $0.item.primaryActor?.key == actorKey }, "少推 persists across refresh")
    check(!store.results.contains { $0.id == other.id }, "不感兴趣 persists across refresh")
    // restart from disk
    try? await Task.sleep(nanoseconds: 300_000_000)
    let reopened = RecommendationStore(source: src, defaults: defaults, fileURL: file)
    check(reopened.hero != nil && reopened.ranker.updates >= updates + 1, "cache + model restored")
    store.reset()
    check(store.ranker == RecRanker() && store.hero == nil, "reset clears model and feed")
    await store.refreshNow()
    check(store.coldStart, "after reset earlier history is ignored → cold start")
    // cold start fixture
    let coldSrc = FixtureRecSource(); coldSrc.cold = true
    let coldStore = RecommendationStore(source: coldSrc, defaults: UserDefaults(suiteName: suite + ".c")!, fileURL: nil)
    await coldStore.refreshNow()
    check(coldStore.coldStart && coldStore.hero != nil, "cold start shows popular / new")
    defaults.removePersistentDomain(forName: suite)
    try? FileManager.default.removeItem(at: file)
    print("PASS recommender281 store: refresh budget, cache reuse, watched filter, 不感兴趣 / 少推 / 喜欢 (immediate + persisted), model persistence, reset, cold start")
}

enum RecommendationSourceRegistry { @MainActor static func make() -> RecommendationSource { FixtureRecSource() } }
