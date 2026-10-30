//
//  Recommender.swift
//  AVDB
//
//  Build 281 「为你推荐」: an on-device recommender adapted from the concepts in X's open-sourced
//  recommendation algorithm (twitter/the-algorithm): in-network + out-of-network candidate sourcing,
//  SimClusters-style interest communities, TwHIN-style embeddings, a light "heavy ranker" that predicts
//  engagement (online logistic regression), then filtering, MMR diversity and author-diversity decay.
//  Everything here is pure Foundation code: no network, no upload, deterministic, unit-tested with swiftc.
//

import Foundation

// MARK: - Model

enum RecFeatureKind: String, Codable, CaseIterable, Hashable, Sendable {
    case actor = "a", tag = "t", maker = "m", series = "s", director = "d"
    var label: String {
        switch self { case .actor: return "女优"; case .tag: return "标签"; case .maker: return "片商"; case .series: return "系列"; case .director: return "导演" }
    }
    /// Relative importance of one shared feature (an actress says more about taste than a generic tag).
    var weight: Double {
        switch self { case .actor: return 1.0; case .series: return 0.9; case .maker: return 0.6; case .director: return 0.5; case .tag: return 0.55 }
    }
}

struct RecFeature: Codable, Hashable, Sendable {
    var kind: RecFeatureKind
    var id: String
    var name: String
    var key: String { kind.rawValue + ":" + id }
    static func key(_ kind: RecFeatureKind, _ id: String) -> String { kind.rawValue + ":" + id }
}

/// Cached movie metadata (no stream URLs, no account data).
struct RecItem: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var number: String
    var title: String
    var type: String? = nil
    var coverURL: String? = nil
    var thumbURL: String? = nil
    /// "yyyy-MM-dd"
    var releaseDate: String? = nil
    /// JavDB rating 0…5
    var rating: Double? = nil
    /// watched + want-watch + reviews counts
    var popularity: Double? = nil
    var features: [RecFeature] = []
    /// True when tags / actresses come from the detail payload (not only from the list that found it).
    var detailed: Bool = false
    var fetchedAt: Date = Date(timeIntervalSince1970: 0)

    func features(_ kind: RecFeatureKind) -> [RecFeature] { features.filter { $0.kind == kind } }
    var primaryActor: RecFeature? { features.first { $0.kind == .actor } }
    var primarySeries: RecFeature? { features.first { $0.kind == .series } }
    /// Merges list-level knowledge into detail-level knowledge without losing either.
    func merged(with other: RecItem) -> RecItem {
        var base = other.detailed && !detailed ? other : self
        let extra = other.detailed && !detailed ? self : other
        var keys = Set(base.features.map(\.key))
        for f in extra.features where keys.insert(f.key).inserted { base.features.append(f) }
        base.coverURL = base.coverURL ?? extra.coverURL
        base.thumbURL = base.thumbURL ?? extra.thumbURL
        base.releaseDate = base.releaseDate ?? extra.releaseDate
        base.rating = base.rating ?? extra.rating
        base.popularity = base.popularity ?? extra.popularity
        base.type = base.type ?? extra.type
        if base.title.isEmpty { base.title = extra.title }
        base.detailed = detailed || other.detailed
        base.fetchedAt = max(fetchedAt, other.fetchedAt)
        return base
    }
}

enum RecSignalKind: String, Codable, Sendable {
    case watch, favorite, like, dislike, follow, lessFeature, moreFeature
}

struct RecSignal: Codable, Hashable, Sendable {
    var kind: RecSignalKind
    var movieID: String? = nil
    var featureKey: String? = nil
    var featureName: String? = nil
    /// Watched fraction 0…1 for `.watch`.
    var ratio: Double? = nil
    /// Number of distinct sessions for `.watch` (rewatch ≥ 2).
    var plays: Int = 1
    var at: Date
}

// MARK: - Signal weights + time decay (X: engagement weights × recency)

enum RecSignalWeights {
    static let halfLifeDays = 30.0
    static let quickBailRatio = 0.10
    static func decay(_ at: Date, now: Date) -> Double {
        let days = max(0, now.timeIntervalSince(at) / 86_400)
        return pow(0.5, days / halfLifeDays)
    }
    /// Base weight before decay. Quick bail (<10 % watched) is a weak negative.
    static func base(_ s: RecSignal) -> Double {
        switch s.kind {
        case .watch:
            let r = min(1, max(0, s.ratio ?? 0.3))
            if r < quickBailRatio { return -0.35 }
            let rewatch = s.plays > 1 ? min(1.2, 0.6 * log2(Double(s.plays))) : 0
            return 0.4 + 1.2 * r + rewatch
        case .favorite: return 1.0
        case .like: return 2.0
        case .dislike: return -2.5
        case .follow: return 2.5
        case .lessFeature: return -2.0
        case .moreFeature: return 1.5
        }
    }
    /// Follows are current state (no decay); explicit feedback decays twice as slowly as viewing.
    static func weight(_ s: RecSignal, now: Date) -> Double {
        switch s.kind {
        case .follow: return base(s)
        case .like, .dislike, .lessFeature, .moreFeature: return base(s) * pow(0.5, max(0, now.timeIntervalSince(s.at) / 86_400) / (halfLifeDays * 2))
        default: return base(s) * decay(s.at, now: now)
        }
    }
}

// MARK: - TF-IDF index (sparse item vectors)

typealias RecVector = [String: Double]

enum RecVectorMath {
    static func norm(_ v: RecVector) -> Double { sqrt(v.values.reduce(0) { $0 + $1 * $1 }) }
    static func normalized(_ v: RecVector) -> RecVector {
        let n = norm(v); guard n > 0 else { return [:] }
        return v.mapValues { $0 / n }
    }
    static func dot(_ a: RecVector, _ b: RecVector) -> Double {
        let (small, big) = a.count <= b.count ? (a, b) : (b, a)
        var s = 0.0
        for (k, x) in small { if let y = big[k] { s += x * y } }
        return s
    }
    static func cosine(_ a: RecVector, _ b: RecVector) -> Double {
        let na = norm(a), nb = norm(b)
        guard na > 0, nb > 0 else { return 0 }
        return dot(a, b) / (na * nb)
    }
    static func dot(_ a: [Double], _ b: [Double]) -> Double { zip(a, b).reduce(0) { $0 + $1.0 * $1.1 } }
}

struct RecIndex: Sendable {
    private(set) var df: [String: Int] = [:]
    private(set) var count = 0
    init(items: [RecItem]) {
        count = items.count
        for item in items { for key in Set(item.features.map(\.key)) { df[key, default: 0] += 1 } }
    }
    func idf(_ key: String) -> Double { log(Double(count + 1) / Double((df[key] ?? 0) + 1)) + 1 }
    /// Binary TF × IDF × kind weight; tags share one budget so tag-heavy items do not dominate.
    func vector(_ item: RecItem) -> RecVector {
        var v: RecVector = [:]
        let tagCount = max(1, item.features(.tag).count)
        for f in item.features {
            let scale = f.kind == .tag ? 1 / sqrt(Double(tagCount)) : 1
            v[f.key] = max(v[f.key] ?? 0, f.kind.weight * idf(f.key) * scale)
        }
        return RecVectorMath.normalized(v)
    }
}

// MARK: - SimClusters-style interest communities (feature co-occurrence + label propagation)

struct RecClusters: Codable, Equatable, Sendable {
    /// feature key → community id
    var assignment: [String: Int] = [:]
    /// community id → top member keys (by degree)
    var members: [Int: [String]] = [:]
    /// feature key → strongest co-occurring keys with normalised weights (TwHIN-style neighbourhood)
    var neighbours: [String: [String: Double]] = [:]

    static let maxFeatures = 400
    static let iterations = 8
    static let neighbourLimit = 5

    static func build(items: [RecItem], focus: Set<String> = []) -> RecClusters {
        var freq: [String: Int] = [:]
        for item in items { for k in Set(item.features.map(\.key)) { freq[k, default: 0] += 1 } }
        // Keep the most frequent features plus everything the user interacted with.
        let ranked = freq.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
        var keep = Set(ranked.prefix(maxFeatures)); keep.formUnion(focus.filter { freq[$0] != nil })
        var co: [String: [String: Double]] = [:]
        for item in items {
            let keys = Array(Set(item.features.map(\.key)).intersection(keep)).sorted()
            guard keys.count > 1 else { continue }
            for i in 0..<keys.count { for j in (i + 1)..<keys.count {
                co[keys[i], default: [:]][keys[j], default: 0] += 1
                co[keys[j], default: [:]][keys[i], default: 0] += 1
            } }
        }
        // Cosine-normalised co-occurrence (c_ij / sqrt(c_i c_j)).
        var graph: [String: [String: Double]] = [:]
        for (a, row) in co {
            for (b, c) in row {
                let w = c / sqrt(Double(freq[a] ?? 1) * Double(freq[b] ?? 1))
                if w >= 0.08 { graph[a, default: [:]][b] = w }
            }
        }
        var out = RecClusters()
        for (k, row) in graph {
            let top = row.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(neighbourLimit)
            out.neighbours[k] = Dictionary(uniqueKeysWithValues: top.map { ($0.key, $0.value) })
        }
        // Deterministic label propagation.
        let nodes = keep.sorted()
        var label: [String: Int] = [:]
        for (i, k) in nodes.enumerated() { label[k] = i }
        for _ in 0..<iterations {
            var changed = false
            for k in nodes {
                guard let row = graph[k], !row.isEmpty else { continue }
                var votes: [Int: Double] = [:]
                for (n, w) in row { if let l = label[n] { votes[l, default: 0] += w } }
                votes[label[k]!, default: 0] += 0.5   // inertia
                let best = votes.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }!.key
                if best != label[k] { label[k] = best; changed = true }
            }
            if !changed { break }
        }
        // Compact ids, drop singletons without edges.
        var remap: [Int: Int] = [:]
        for k in nodes where graph[k] != nil {
            let l = label[k]!
            if remap[l] == nil { remap[l] = remap.count }
            out.assignment[k] = remap[l]!
        }
        var groups: [Int: [String]] = [:]
        for (k, c) in out.assignment { groups[c, default: []].append(k) }
        for (c, keys) in groups {
            out.members[c] = keys.sorted { (freq[$0] ?? 0) != (freq[$1] ?? 0) ? (freq[$0] ?? 0) > (freq[$1] ?? 0) : $0 < $1 }.prefix(6).map { $0 }
        }
        return out
    }

    /// Item → normalised community distribution.
    func distribution(_ item: RecItem) -> [Int: Double] {
        var d: [Int: Double] = [:]
        for f in item.features { if let c = assignment[f.key] { d[c, default: 0] += f.kind.weight } }
        let total = d.values.reduce(0, +)
        return total > 0 ? d.mapValues { $0 / total } : [:]
    }

    /// Neighbourhood-smoothed vector: an item also "means" what its features usually co-occur with.
    func smoothed(_ v: RecVector, strength: Double = 0.35) -> RecVector {
        var out = v
        for (k, x) in v { for (n, w) in neighbours[k] ?? [:] { out[n, default: 0] += strength * x * w } }
        return RecVectorMath.normalized(out)
    }
}

/// TwHIN-style dense embedding: a fixed hashed random projection of the smoothed sparse vector.
/// Cosine in this space approximates cosine of the smoothed vectors, so out-of-network items that share
/// co-occurring features (not identical ones) still score.
enum RecEmbedding {
    static let dimensions = 32
    static func hash(_ s: String, _ d: Int) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        h ^= UInt64(d) &* 0x9E3779B97F4A7C15
        h ^= h >> 33; h = h &* 0xff51afd7ed558ccd; h ^= h >> 33
        return h
    }
    static func embed(_ v: RecVector) -> [Double] {
        var e = [Double](repeating: 0, count: dimensions)
        for (k, x) in v { for d in 0..<dimensions { e[d] += (hash(k, d) & 1 == 0 ? 1 : -1) * x } }
        let n = sqrt(e.reduce(0) { $0 + $1 * $1 })
        return n > 0 ? e.map { $0 / n } : e
    }
}

// MARK: - User profile

struct RecPreference: Equatable, Sendable {
    var key: String
    var kind: RecFeatureKind
    var name: String
    var weight: Double
}

struct RecProfile: Sendable {
    var affinity: [String: Double] = [:]
    var names: [String: String] = [:]
    var userVector: RecVector = [:]
    var embedding: [Double] = []
    var communities: [Int: Double] = [:]
    var positiveItems = 0
    var negativeItems = 0
    var explicitPositives = 0
    var dislikedItems: Set<String> = []
    var lessFeatures: Set<String> = []
    var watchedFraction: [String: Double] = [:]

    static let coldStartMinimum = 3
    var isColdStart: Bool { positiveItems + explicitPositives < Self.coldStartMinimum }

    func top(_ kind: RecFeatureKind?, limit: Int, positive: Bool = true) -> [RecPreference] {
        affinity.compactMap { key, w -> RecPreference? in
            guard let kindRaw = key.split(separator: ":").first, let k = RecFeatureKind(rawValue: String(kindRaw)) else { return nil }
            guard kind == nil || k == kind, positive ? w > 0.05 : w < -0.05 else { return nil }
            return RecPreference(key: key, kind: k, name: names[key] ?? String(key.dropFirst(2)), weight: w)
        }
        .sorted { positive ? ($0.weight != $1.weight ? $0.weight > $1.weight : $0.key < $1.key) : ($0.weight != $1.weight ? $0.weight < $1.weight : $0.key < $1.key) }
        .prefix(limit).map { $0 }
    }

    static func build(signals: [RecSignal], items: [String: RecItem], index: RecIndex, clusters: RecClusters, now: Date) -> RecProfile {
        var p = RecProfile()
        var vector: RecVector = [:]
        for s in signals {
            let w = RecSignalWeights.weight(s, now: now)
            if let key = s.featureKey {
                p.affinity[key, default: 0] += w
                if let name = s.featureName { p.names[key] = name }
                if s.kind == .lessFeature { p.lessFeatures.insert(key) }
                if s.kind == .follow || s.kind == .moreFeature { p.explicitPositives += 1 }
                vector[key, default: 0] += w * 0.5
                continue
            }
            guard let id = s.movieID else { continue }
            if s.kind == .dislike { p.dislikedItems.insert(id) }
            if s.kind == .like { p.explicitPositives += 1 }
            if s.kind == .watch, let r = s.ratio { p.watchedFraction[id] = max(p.watchedFraction[id] ?? 0, r) }
            if w > 0 { p.positiveItems += s.kind == .watch || s.kind == .favorite ? 1 : 0 } else { p.negativeItems += 1 }
            guard let item = items[id] else { continue }
            let tagCount = max(1, item.features(.tag).count)
            for f in item.features {
                let scale = f.kind == .tag ? 1 / sqrt(Double(tagCount)) : 1
                p.affinity[f.key, default: 0] += w * f.kind.weight * scale
                p.names[f.key] = f.name
            }
            // Negative items pull the user vector away at half strength.
            let iv = index.vector(item)
            for (k, x) in iv { vector[k, default: 0] += (w > 0 ? w : 0.5 * w) * x }
        }
        p.userVector = RecVectorMath.normalized(vector.filter { $0.value > 0 })
        p.embedding = RecEmbedding.embed(clusters.smoothed(p.userVector))
        var comm: [Int: Double] = [:]
        for (k, w) in p.affinity where w > 0 { if let c = clusters.assignment[k] { comm[c, default: 0] += w } }
        let total = comm.values.reduce(0, +)
        p.communities = total > 0 ? comm.mapValues { $0 / total } : [:]
        return p
    }
}

// MARK: - Candidates

enum RecCandidateSource: String, Codable, Hashable, Sendable {
    case follow, actor, series, maker, tag, similar, popular, latest
    /// X: in-network = graph the user explicitly connected to; out-of-network = discovery.
    var inNetwork: Bool { self == .follow || self == .actor || self == .series }
}

struct RecCandidate: Hashable, Sendable {
    var item: RecItem
    var source: RecCandidateSource
    /// The feature / movie that produced it (actor key, series key, tag key, or seed movie id for `.similar`).
    var via: String? = nil
    var viaName: String? = nil
}

/// Which lists to fetch this run, most valuable first (X candidate sourcing with a request budget).
enum RecSourcingPlan {
    struct Request: Hashable, Sendable {
        var source: RecCandidateSource
        var id: String
        var name: String
        var key: String { source.rawValue + ":" + id }
    }
    static func make(profile: RecProfile, follows: [RecFeature], recentPositives: [(id: String, number: String)], budget: Int) -> [Request] {
        var out: [Request] = []
        var seen = Set<String>()
        func add(_ r: Request) { if seen.insert(r.key).inserted { out.append(r) } }
        if profile.isColdStart {
            add(Request(source: .popular, id: "weekly", name: "热门"))
            add(Request(source: .latest, id: "0", name: "新作"))
        }
        for f in follows.prefix(3) {
            let src: RecCandidateSource = f.kind == .actor ? .actor : (f.kind == .series ? .series : .maker)
            add(Request(source: src, id: f.id, name: f.name))
        }
        for p in profile.top(.actor, limit: 3) where !profile.lessFeatures.contains(p.key) { add(Request(source: .actor, id: String(p.key.dropFirst(2)), name: p.name)) }
        for p in profile.top(.series, limit: 2) where !profile.lessFeatures.contains(p.key) { add(Request(source: .series, id: String(p.key.dropFirst(2)), name: p.name)) }
        for m in recentPositives.prefix(2) { add(Request(source: .similar, id: m.id, name: m.number)) }
        for p in profile.top(.tag, limit: 2) where !profile.lessFeatures.contains(p.key) { add(Request(source: .tag, id: String(p.key.dropFirst(2)), name: p.name)) }
        for p in profile.top(.maker, limit: 1) where !profile.lessFeatures.contains(p.key) { add(Request(source: .maker, id: String(p.key.dropFirst(2)), name: p.name)) }
        if !profile.isColdStart { add(Request(source: .popular, id: "weekly", name: "热门")) }
        return Array(out.prefix(max(0, budget)))
    }
}

// MARK: - Heavy ranker (online logistic regression over engineered features)

struct RecRanker: Codable, Equatable, Sendable {
    static let featureNames = ["bias", "内容相似", "嵌入相似", "兴趣社区", "女优", "系列", "片商/导演", "标签", "关注网络", "新鲜度", "热度", "评分", "负反馈"]
    static let initial: [Double] = [-1.2, 2.0, 1.0, 1.2, 1.6, 1.2, 0.6, 0.9, 0.5, 0.6, 0.4, 0.4, 2.2]
    var weights: [Double] = RecRanker.initial
    var updates = 0
    static let learningRate = 0.08
    static let l2 = 0.001

    static func sigmoid(_ z: Double) -> Double { 1 / (1 + exp(-z)) }
    func predict(_ x: [Double]) -> Double { Self.sigmoid(RecVectorMath.dot(weights, x)) }

    /// One SGD step on log-loss; bias is not regularised; weights clamped to keep the model sane.
    mutating func update(_ x: [Double], label: Double, rate: Double = RecRanker.learningRate) {
        guard x.count == weights.count, x.allSatisfy({ $0.isFinite }) else { return }
        let g = label - predict(x)
        for i in weights.indices {
            let reg = i == 0 ? 0 : Self.l2 * weights[i]
            weights[i] = min(5, max(-5, weights[i] + rate * (g * x[i] - reg)))
        }
        updates += 1
    }

    static func releaseAgeDays(_ date: String?, now: Date) -> Double? {
        guard let date, date.count >= 10 else { return nil }
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Tokyo"); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(date.prefix(10))) else { return nil }
        return now.timeIntervalSince(d) / 86_400
    }

    static func features(_ c: RecCandidate, profile: RecProfile, index: RecIndex, clusters: RecClusters, now: Date) -> [Double] {
        let item = c.item
        let iv = index.vector(item)
        let content = RecVectorMath.dot(profile.userVector, iv)
        let embed = profile.embedding.isEmpty ? 0 : max(0, RecVectorMath.dot(profile.embedding, RecEmbedding.embed(clusters.smoothed(iv))))
        let dist = clusters.distribution(item)
        var community = 0.0
        for (k, x) in dist { community += x * (profile.communities[k] ?? 0) }
        func aff(_ kinds: [RecFeatureKind]) -> Double {
            let values = item.features.filter { kinds.contains($0.kind) }.map { profile.affinity[$0.key] ?? 0 }
            return tanh((values.max() ?? 0) / 3)
        }
        let tagValues = item.features(.tag).map { profile.affinity[$0.key] ?? 0 }.sorted(by: >).prefix(3)
        let tag = tagValues.isEmpty ? 0 : tanh((tagValues.reduce(0, +) / Double(tagValues.count)) / 2)
        let negative = tanh(min(0, item.features.map { profile.affinity[$0.key] ?? 0 }.min() ?? 0) / 2)
        let fresh = releaseAgeDays(item.releaseDate, now: now).map { exp(-max(0, $0) / 60) } ?? 0.2
        let pop = min(1, log1p(max(0, item.popularity ?? 0)) / log1p(5000))
        let rating = min(1, max(0, (item.rating ?? 0) / 5))
        return [1, content, embed, community, aff([.actor]), aff([.series]), aff([.maker, .director]), tag,
                c.source.inNetwork ? 1 : 0, fresh, pop, rating, negative]
    }
}

// MARK: - Filters, reasons, diversity

struct RecResult: Codable, Hashable, Identifiable, Sendable {
    var item: RecItem
    var score: Double
    var reason: RecReason
    var source: RecCandidateSource
    /// Ranker input kept so feedback can train the model on exactly what was shown.
    var x: [Double]
    var id: String { item.id }
}

struct RecReason: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case follow, actor, series, maker, tag, similar, popular, fresh, taste }
    var kind: Kind
    var text: String
    var symbol: String
    /// Carousel group key + title (因为你常看 XX / 黑丝精选 / 同系列新作).
    var groupKey: String
    var groupTitle: String
}

enum RecFilter {
    static let watchedCutoff = 0.80
    enum Drop: String { case watched, disliked, lessFeature, unavailable, duplicate }
    static func reject(_ c: RecCandidate, profile: RecProfile) -> Drop? {
        let item = c.item
        if item.id.isEmpty || (item.number.isEmpty && item.coverURL == nil && item.thumbURL == nil) { return .unavailable }
        if profile.dislikedItems.contains(item.id) { return .disliked }
        if (profile.watchedFraction[item.id] ?? 0) > watchedCutoff { return .watched }
        if let a = item.primaryActor, profile.lessFeatures.contains(a.key) { return .lessFeature }
        if let s = item.primarySeries, profile.lessFeatures.contains(s.key) { return .lessFeature }
        let lessTags = item.features(.tag).filter { profile.lessFeatures.contains($0.key) }.count
        if lessTags > 0 && lessTags * 2 >= max(1, item.features(.tag).count) { return .lessFeature }
        return nil
    }
}

enum RecReasoner {
    static func reason(_ c: RecCandidate, profile: RecProfile) -> RecReason {
        let item = c.item
        func best(_ kind: RecFeatureKind) -> (RecFeature, Double)? {
            item.features(kind).map { ($0, profile.affinity[$0.key] ?? 0) }.filter { $0.1 > 0.3 }.max { $0.1 < $1.1 }
        }
        let tags = item.features(.tag).map { ($0, profile.affinity[$0.key] ?? 0) }.filter { $0.1 > 0.25 }.sorted { $0.1 > $1.1 }
        if c.source == .follow, let name = c.viaName ?? (item.primaryActor ?? item.primarySeries)?.name {
            return RecReason(kind: .follow, text: "关注的 \(name) 新作", symbol: "bell.fill", groupKey: "follow", groupTitle: "关注更新")
        }
        if c.source == .similar, let seed = c.viaName {
            return RecReason(kind: .similar, text: "与 \(seed) 相似", symbol: "sparkles", groupKey: "similar:" + (c.via ?? seed), groupTitle: "看过 \(seed) 的人也喜欢")
        }
        if let (a, _) = best(.actor) {
            let tail = tags.first.map { " · " + $0.0.name } ?? ""
            return RecReason(kind: .actor, text: "因为你常看 \(a.name)" + tail, symbol: "person.crop.circle.fill", groupKey: a.key, groupTitle: "因为你常看 \(a.name)")
        }
        if let (s, _) = best(.series) {
            let head = tags.first.map { $0.0.name + " · " } ?? ""
            return RecReason(kind: .series, text: head + "同系列", symbol: "square.stack.fill", groupKey: s.key, groupTitle: "同系列新作 · \(s.name)")
        }
        if let t = tags.first {
            let text = tags.prefix(2).map(\.0.name).joined(separator: " · ")
            return RecReason(kind: .tag, text: text, symbol: "tag.fill", groupKey: t.0.key, groupTitle: "\(t.0.name)精选")
        }
        if let (m, _) = best(.maker) ?? best(.director) {
            return RecReason(kind: .maker, text: "常看 \(m.name)", symbol: "building.2.fill", groupKey: "maker", groupTitle: "常看片商")
        }
        if c.source == .latest { return RecReason(kind: .fresh, text: "新作", symbol: "clock.fill", groupKey: "popular", groupTitle: "热门新作") }
        if c.source == .popular || profile.isColdStart {
            return RecReason(kind: .popular, text: "本周热门", symbol: "flame.fill", groupKey: "popular", groupTitle: "热门新作")
        }
        return RecReason(kind: .taste, text: "符合你的口味", symbol: "heart.fill", groupKey: "taste", groupTitle: "更多为你推荐")
    }
}

enum RecDiversity {
    static let lambda = 0.75
    /// X author-diversity: each further item of the same actress/series is multiplied by this decay.
    static let authorDecay = 0.6
    static let maxRun = 2
    static let maxPerAuthor = 4

    static func authors(_ item: RecItem) -> [String] { [item.primaryActor?.key, item.primarySeries?.key].compactMap { $0 } }

    /// MMR + author-diversity decay + "no more than 2 of the same actress / series in a row".
    static func rerank(_ ranked: [RecResult], index: RecIndex, limit: Int) -> [RecResult] {
        var pool = ranked
        var out: [RecResult] = []
        var vectors: [String: RecVector] = [:]
        for r in ranked { vectors[r.id] = index.vector(r.item) }
        var perAuthor: [String: Int] = [:]
        while out.count < limit, !pool.isEmpty {
            var bestIndex: Int?
            var bestValue = -Double.infinity
            for (i, r) in pool.enumerated() {
                let a = authors(r.item)
                if a.contains(where: { (perAuthor[$0] ?? 0) >= maxPerAuthor }) { continue }
                if out.count >= maxRun, let shared = a.first(where: { key in out.suffix(maxRun).allSatisfy { authors($0.item).contains(key) } }), !shared.isEmpty { continue }
                let redundancy = out.map { RecVectorMath.dot(vectors[r.id] ?? [:], vectors[$0.id] ?? [:]) }.max() ?? 0
                let decay = a.map { pow(authorDecay, Double(perAuthor[$0] ?? 0)) }.min() ?? 1
                let value = lambda * r.score * decay - (1 - lambda) * redundancy
                if value > bestValue { bestValue = value; bestIndex = i }
            }
            guard let i = bestIndex else { break }   // only constraint-blocked items remain
            let pick = pool.remove(at: i)
            for a in authors(pick.item) { perAuthor[a, default: 0] += 1 }
            out.append(pick)
        }
        return out
    }
}

// MARK: - Pipeline

struct RecGroup: Hashable, Identifiable, Sendable {
    var key: String
    var title: String
    var symbol: String
    var items: [RecResult]
    var id: String { key }
}

struct RecOutput: Sendable {
    var hero: RecResult?
    var results: [RecResult]
    var groups: [RecGroup]
    var coldStart: Bool
    var dropped: [String: Int]
}

enum RecommenderPipeline {
    static let feedLimit = 40
    static let minGroup = 3
    static let maxGroups = 6

    static func rank(candidates: [RecCandidate], profile: RecProfile, ranker: RecRanker, index: RecIndex, clusters: RecClusters, now: Date) -> RecOutput {
        var dropped: [String: Int] = [:]
        var byID: [String: RecCandidate] = [:]
        var numbers = Set<String>()
        // Merge the same movie found by several sources: keep the richest metadata, prefer in-network source.
        for c in candidates {
            if var existing = byID[c.item.id] {
                existing.item = existing.item.merged(with: c.item)
                if c.source.inNetwork && !existing.source.inNetwork { existing.source = c.source; existing.via = c.via; existing.viaName = c.viaName }
                if c.source == .follow { existing.source = .follow }
                byID[c.item.id] = existing
            } else { byID[c.item.id] = c }
        }
        var scored: [RecResult] = []
        for c in byID.values.sorted(by: { $0.item.id < $1.item.id }) {
            if let why = RecFilter.reject(c, profile: profile) { dropped[why.rawValue, default: 0] += 1; continue }
            let n = c.item.number.uppercased()
            if !n.isEmpty, !numbers.insert(n).inserted { dropped[RecFilter.Drop.duplicate.rawValue, default: 0] += 1; continue }
            let x = RecRanker.features(c, profile: profile, index: index, clusters: clusters, now: now)
            let score: Double
            if profile.isColdStart {
                // Cold start: popularity + freshness + rating prior, nudged by whatever little we know.
                score = 0.45 * x[10] + 0.3 * x[9] + 0.15 * x[11] + 0.1 * ranker.predict(x)
            } else {
                score = ranker.predict(x)
            }
            scored.append(RecResult(item: c.item, score: score, reason: RecReasoner.reason(c, profile: profile), source: c.source, x: x))
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.id < $1.id }
        let feed = RecDiversity.rerank(Array(scored.prefix(feedLimit * 3)), index: index, limit: feedLimit)
        return RecOutput(hero: feed.first, results: feed, groups: group(Array(feed.dropFirst())), coldStart: profile.isColdStart, dropped: dropped)
    }

    /// Carousels by reason. Small groups fold into 「更多为你推荐」.
    static func group(_ results: [RecResult]) -> [RecGroup] {
        var order: [String] = []
        var buckets: [String: RecGroup] = [:]
        for r in results {
            let key = r.reason.groupKey
            if buckets[key] == nil { order.append(key); buckets[key] = RecGroup(key: key, title: r.reason.groupTitle, symbol: r.reason.symbol, items: []) }
            buckets[key]!.items.append(r)
        }
        var groups: [RecGroup] = []
        var rest: [RecResult] = []
        for key in order {
            let g = buckets[key]!
            if g.items.count >= minGroup && groups.count < maxGroups - 1 { groups.append(g) } else { rest += g.items }
        }
        if !rest.isEmpty { groups.append(RecGroup(key: "more", title: "更多为你推荐", symbol: "sparkles", items: rest)) }
        return groups
    }
}
