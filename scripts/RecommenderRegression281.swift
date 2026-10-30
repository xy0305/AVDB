// Build 281 recommender regression: executed with swiftc together with AVDB/Services/Recommender.swift
// (+ RecommendationStore.swift and a fixture source for the async store part).
import Foundation

func check(_ c: @autoclosure () -> Bool, _ msg: String, line: Int = #line) {
    if !c() { print("FAIL line \(line): \(msg)"); exit(1) }
}
let now = Date(timeIntervalSince1970: 1_800_000_000)
func daysAgo(_ d: Double) -> Date { now.addingTimeInterval(-d * 86_400) }
func A(_ id: String, _ n: String) -> RecFeature { RecFeature(kind: .actor, id: id, name: n) }
func T(_ id: String, _ n: String) -> RecFeature { RecFeature(kind: .tag, id: id, name: n) }
func S(_ id: String, _ n: String) -> RecFeature { RecFeature(kind: .series, id: id, name: n) }
func M(_ id: String, _ n: String) -> RecFeature { RecFeature(kind: .maker, id: id, name: n) }
func item(_ id: String, _ f: [RecFeature], date: String = "2026-09-01", pop: Double = 100, rating: Double = 4.0) -> RecItem {
    RecItem(id: id, number: "ABC-" + id, title: "作品 " + id, type: "0", coverURL: "https://c/\(id).jpg", releaseDate: date, rating: rating, popularity: pop, features: f, detailed: true, fetchedAt: now)
}

// ---- decay / signal weights
check(abs(RecSignalWeights.decay(daysAgo(30), now: now) - 0.5) < 1e-9, "30-day half life")
check(abs(RecSignalWeights.decay(now, now: now) - 1) < 1e-9, "no decay now")
let bail = RecSignal(kind: .watch, movieID: "x", ratio: 0.05, at: now)
check(RecSignalWeights.base(bail) < 0, "quick bail is a weak negative")
check(RecSignalWeights.base(bail) > RecSignalWeights.base(RecSignal(kind: .dislike, movieID: "x", at: now)), "bail weaker than dislike")
let once = RecSignal(kind: .watch, movieID: "x", ratio: 0.9, at: now), twice = RecSignal(kind: .watch, movieID: "x", ratio: 0.9, plays: 3, at: now)
check(RecSignalWeights.base(twice) > RecSignalWeights.base(once), "rewatch bonus")
check(RecSignalWeights.base(RecSignal(kind: .watch, movieID: "x", ratio: 0.9, at: now)) > RecSignalWeights.base(RecSignal(kind: .watch, movieID: "x", ratio: 0.3, at: now)), "watch ratio")
check(RecSignalWeights.weight(RecSignal(kind: .follow, featureKey: "a:1", at: daysAgo(365)), now: now) == 2.5, "follows do not decay")

// ---- corpus
let mikami = A("1", "三上悠亚"), yua = A("2", "河北彩花"), other = A("3", "某某")
let black = T("10", "黑丝"), legs = T("11", "美脚"), office = T("12", "OL"), school = T("13", "校服")
let s1 = S("100", "绝顶系列"), mk = M("200", "S1")
var items: [String: RecItem] = [:]
for i in 0..<6 { items["h\(i)"] = item("h\(i)", [mikami, black, i % 2 == 0 ? legs : office, s1, mk]) }
items["h6"] = item("h6", [yua, black, office])
for i in 0..<8 { items["c\(i)"] = item("c\(i)", [mikami, black, i % 2 == 0 ? legs : office, s1]) }       // same actress candidates
for i in 0..<6 { items["y\(i)"] = item("y\(i)", [yua, black, legs]) }
for i in 0..<6 { items["o\(i)"] = item("o\(i)", [other, school], pop: 4000, rating: 4.6) }               // unrelated but popular
items["bad"] = item("bad", [other, black])
let index = RecIndex(items: Array(items.values))
check(index.idf(school.key) > index.idf(black.key), "rarer feature has higher idf")
let v = index.vector(items["h0"]!)
check(abs(RecVectorMath.norm(v) - 1) < 1e-9, "item vector normalised")

// ---- SimClusters-style communities
let clusters = RecClusters.build(items: Array(items.values))
check(clusters.assignment[mikami.key] != nil && clusters.assignment[mikami.key] == clusters.assignment[s1.key], "co-occurring features share a community")
check(clusters.assignment[other.key] == clusters.assignment[school.key], "other community coherent")
check(clusters.assignment[school.key] != clusters.assignment[s1.key], "unrelated features in different communities")
let dist = clusters.distribution(items["h0"]!)
check(abs(dist.values.reduce(0, +) - 1) < 1e-9, "community distribution sums to 1")

// ---- TwHIN-style embedding: neighbours make related-but-not-identical items closer than unrelated ones
let e1 = RecEmbedding.embed(clusters.smoothed(index.vector(items["y0"]!)))
let e2 = RecEmbedding.embed(clusters.smoothed(index.vector(items["h0"]!)))
let e3 = RecEmbedding.embed(clusters.smoothed(index.vector(items["o0"]!)))
check(e1.count == RecEmbedding.dimensions && abs(RecVectorMath.dot(e1, e1) - 1) < 1e-9, "unit embedding")
check(RecVectorMath.dot(e1, e2) > RecVectorMath.dot(e3, e2), "related > unrelated in embedding space")
check(RecEmbedding.embed(["a:1": 1]) == RecEmbedding.embed(["a:1": 1]), "deterministic projection")

// ---- profile
var signals: [RecSignal] = (0..<6).map { RecSignal(kind: .watch, movieID: "h\($0)", ratio: 0.9, at: daysAgo(Double($0))) }
signals.append(RecSignal(kind: .watch, movieID: "h6", ratio: 0.04, at: daysAgo(1)))          // quick bail on 河北彩花
signals.append(RecSignal(kind: .dislike, movieID: "bad", at: daysAgo(2)))
var profile = RecProfile.build(signals: signals, items: items, index: index, clusters: clusters, now: now)
check(!profile.isColdStart, "6 watched items is not cold")
check(profile.top(.actor, limit: 1).first?.name == "三上悠亚", "top actress")
check(profile.top(.tag, limit: 1).first?.name == "黑丝", "top tag 黑丝")
check((profile.affinity[yua.key] ?? 0) < 0, "quick bail makes the actress slightly negative")
check(profile.dislikedItems.contains("bad") && profile.watchedFraction["h0"] == 0.9, "dislike + watched fractions")
check(abs(RecVectorMath.norm(profile.userVector) - 1) < 1e-9, "user vector normalised")
check(!profile.communities.isEmpty, "user communities")
// recency decay: an old heavy viewer counts less than a recent one
let old = RecProfile.build(signals: [RecSignal(kind: .watch, movieID: "o0", ratio: 1, at: daysAgo(120))], items: items, index: index, clusters: clusters, now: now)
let fresh = RecProfile.build(signals: [RecSignal(kind: .watch, movieID: "o0", ratio: 1, at: now)], items: items, index: index, clusters: clusters, now: now)
check((fresh.affinity[other.key] ?? 0) > 8 * (old.affinity[other.key] ?? 0), "recency decay")

// ---- cold start
let cold = RecProfile.build(signals: [RecSignal(kind: .watch, movieID: "h0", ratio: 0.9, at: now)], items: items, index: index, clusters: clusters, now: now)
check(cold.isColdStart, "1 item is cold")
let coldPlan = RecSourcingPlan.make(profile: cold, follows: [], recentPositives: [], budget: 7)
check(coldPlan.first?.source == .popular && coldPlan.contains { $0.source == .latest }, "cold start sources popular + new")
let followCold = RecProfile.build(signals: [RecSignal(kind: .follow, featureKey: mikami.key, featureName: mikami.name, at: now),
                                            RecSignal(kind: .like, movieID: "h1", at: now), RecSignal(kind: .watch, movieID: "h0", ratio: 0.9, at: now)],
                                  items: items, index: index, clusters: clusters, now: now)
check(!followCold.isColdStart, "follow + like + watch leaves cold start")

// ---- sourcing plan: follows first, less-features excluded, budget respected
var lessProfile = profile; lessProfile.lessFeatures.insert(mikami.key)
let plan = RecSourcingPlan.make(profile: lessProfile, follows: [S("100", "绝顶系列")], recentPositives: [("h0", "ABC-h0")], budget: 5)
check(plan.count == 5 && plan.first?.source == .series, "follows first + budget")
check(!plan.contains { $0.source == .actor && $0.id == "1" }, "less actress not sourced")
check(plan.contains { $0.source == .similar && $0.id == "h0" }, "similar works from a recent positive")
check(Set(plan.map(\.key)).count == plan.count, "no duplicate requests")

// ---- ranking: affinity beats popularity once warm
let ranker = RecRanker()
func cand(_ id: String, _ src: RecCandidateSource = .actor) -> RecCandidate { RecCandidate(item: items[id]!, source: src, via: nil, viaName: nil) }
let xLiked = RecRanker.features(cand("c0"), profile: profile, index: index, clusters: clusters, now: now)
let xOther = RecRanker.features(cand("o0", .popular), profile: profile, index: index, clusters: clusters, now: now)
check(xLiked.count == RecRanker.featureNames.count && xLiked.count == ranker.weights.count, "feature vector size")
check(ranker.predict(xLiked) > ranker.predict(xOther), "liked actress outranks unrelated popular")
let xYua = RecRanker.features(cand("y0", .tag), profile: profile, index: index, clusters: clusters, now: now)
check(xYua[12] < 0, "negative affinity feature present")

// ---- filtering
var fp = profile; fp.watchedFraction["c1"] = 0.85; fp.lessFeatures.insert(yua.key)
check(RecFilter.reject(cand("c1"), profile: fp) == .watched, "watched > 80 % filtered")
check(RecFilter.reject(cand("c2"), profile: fp) == nil, "normal candidate kept")
check(RecFilter.reject(RecCandidate(item: items["bad"]!, source: .tag), profile: fp) == .disliked, "disliked filtered")
check(RecFilter.reject(cand("y1"), profile: fp) == .lessFeature, "少推该女优 filtered")
check(RecFilter.reject(RecCandidate(item: RecItem(id: "z", number: "", title: ""), source: .tag), profile: fp) == .unavailable, "unavailable filtered")
var lessTagProfile = profile; lessTagProfile.lessFeatures.insert(school.key)
check(RecFilter.reject(cand("o1", .popular), profile: lessTagProfile) == .lessFeature, "少推该标签 filtered when it dominates")

// ---- full pipeline: diversity + author diversity + reasons + groups
var cands: [RecCandidate] = (0..<8).map { cand("c\($0)") } + (0..<6).map { cand("y\($0)", .tag) } + (0..<6).map { cand("o\($0)", .popular) }
cands.append(cand("c0", .similar))                       // duplicate via another source
cands.append(RecCandidate(item: items["bad"]!, source: .tag))
var dup = items["c3"]!; dup.id = "c3-dup"; cands.append(RecCandidate(item: dup, source: .maker))   // same 番号, different id
let out = RecommenderPipeline.rank(candidates: cands, profile: profile, ranker: ranker, index: index, clusters: clusters, now: now)
check(out.hero?.item.primaryActor?.key == mikami.key, "hero is the favourite actress")
check(Set(out.results.map(\.id)).count == out.results.count, "no duplicate ids")
check(!out.results.contains { $0.id == "bad" } && (out.dropped["disliked"] ?? 0) == 1, "pipeline filters")
check((out.dropped["duplicate"] ?? 0) == 1, "same 番号 deduped")
var run = 0, last: String? = nil, perActor: [String: Int] = [:]
for r in out.results {
    let a = r.item.primaryActor?.key
    run = (a != nil && a == last) ? run + 1 : 1; last = a
    check(run <= RecDiversity.maxRun, "no more than 2 of the same actress in a row")
    if let a { perActor[a, default: 0] += 1 }
}
check(perActor.values.allSatisfy { $0 <= RecDiversity.maxPerAuthor }, "≤4 per actress")
check(out.results.contains { $0.item.primaryActor?.key == other.key }, "out-of-network items survive diversity")
let heroReason = out.hero!.reason
check(heroReason.kind == .actor && heroReason.text.hasPrefix("因为你常看 三上悠亚") && heroReason.text.contains("黑丝"), "reason text: \(heroReason.text)")
check(out.groups.allSatisfy { $0.items.count >= RecommenderPipeline.minGroup || $0.key == "more" }, "small groups fold into 更多")
check(out.groups.count <= RecommenderPipeline.maxGroups, "group cap")

// reasons for other sources
var followCand = cand("c4"); followCand.source = .follow
check(RecReasoner.reason(followCand, profile: profile).text == "关注的 三上悠亚 新作", "follow reason")
let simCand = RecCandidate(item: items["o2"]!, source: .similar, via: "h0", viaName: "ABC-h0")
check(RecReasoner.reason(simCand, profile: profile).text == "与 ABC-h0 相似", "similar reason")
let seriesOnly = item("s9", [s1, black])
let sr = RecReasoner.reason(RecCandidate(item: seriesOnly, source: .series), profile: profile)
check(sr.kind == .series && sr.text == "黑丝 · 同系列" && sr.groupTitle.hasPrefix("同系列新作"), "series reason: \(sr.text)")
let tagOnly = item("t9", [black, legs])
let tr = RecReasoner.reason(RecCandidate(item: tagOnly, source: .tag), profile: profile)
check(tr.kind == .tag && tr.groupTitle == "黑丝精选", "tag reason group: \(tr.groupTitle)")
check(RecReasoner.reason(RecCandidate(item: items["o3"]!, source: .popular), profile: cold).kind == .popular, "cold popular reason")

// cold-start pipeline ranks by popularity/freshness prior
let coldOut = RecommenderPipeline.rank(candidates: (0..<6).map { cand("o\($0)", .popular) } + [cand("c0", .latest)], profile: cold, ranker: ranker, index: index, clusters: clusters, now: now)
check(coldOut.coldStart && coldOut.hero != nil, "cold start still recommends")

// ---- online learning (heavy-ranker update from feedback)
var learner = RecRanker()
let before = learner.predict(xOther)
for _ in 0..<30 { learner.update(xOther, label: 1) }
check(learner.predict(xOther) > before + 0.2 && learner.updates == 30, "positive feedback raises score")
var learner2 = RecRanker()
for _ in 0..<30 { learner2.update(xLiked, label: 0) }
check(learner2.predict(xLiked) < ranker.predict(xLiked), "negative feedback lowers score")
var clamp = RecRanker()
for _ in 0..<5000 { clamp.update([1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], label: 1, rate: 1) }
check(clamp.weights.allSatisfy { abs($0) <= 5 }, "weights clamped")
var bad = RecRanker(); bad.update([.nan], label: 1); check(bad.updates == 0, "malformed input ignored")
let data = try! JSONEncoder().encode(learner)
check(try! JSONDecoder().decode(RecRanker.self, from: data) == learner, "ranker persists")

// ---- storage cap keeps interacted items
var many: [String: RecItem] = [:]
for i in 0..<30 { var it = item("m\(i)", []); it.fetchedAt = Date(timeIntervalSince1970: Double(i)); many[it.id] = it }
let capped = RecommendationLimits.capMetadata(many, keep: ["m0"], cap: 10)
check(capped.count == 10 && capped["m0"] != nil && capped["m29"] != nil && capped["m1"] == nil, "LRU cap keeps interacted")

// ---- merge keeps detail + list knowledge
let listLevel = RecItem(id: "q", number: "Q-1", title: "", coverURL: "c", features: [A("1", "三上悠亚")], detailed: false)
let detailLevel = RecItem(id: "q", number: "Q-1", title: "标题", features: [T("10", "黑丝")], detailed: true)
let merged = listLevel.merged(with: detailLevel)
check(merged.detailed && merged.features.count == 2 && merged.coverURL == "c" && merged.title == "标题", "merge")

print("PASS recommender281 core: decay/bail/rewatch, TF-IDF, SimClusters communities, TwHIN-style embedding, profile, cold start, sourcing plan, ranking, filters, MMR + author diversity, reasons, groups, online LR, storage cap")

Task { @MainActor in
    await storeTests()
    exit(0)
}
dispatchMain()
