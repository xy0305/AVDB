//
//  RecommendationJavDBSource.swift
//  AVDB
//
//  Build 281: the app's recommendation inputs. Local stores (观看历史 / 稍后再看 / 关注 / feedback) are
//  read on device; candidate lists and details use the existing JavDB API with whatever session exists
//  (never a login prompt), spaced like Build 280's follow checks. Nothing is uploaded.
//

import Foundation

enum RecommendationSourceRegistry {
    @MainActor static func make() -> RecommendationSource { JavDBRecommendationSource() }
}

final class JavDBRecommendationSource: RecommendationSource {
    var requestSpacing: Double { 1.0 }

    @MainActor func snapshot(feedback: [RecSignal], playCounts: [String: Int], since: Date?) -> RecSnapshot {
        let floor = since ?? .distantPast
        var signals: [RecSignal] = []
        var seeds: [RecItem] = []
        var positives: [RecSeed] = []
        for h in PlaybackHistoryStore.shared.items where !h.isTangxin && h.playedAt > floor {
            signals.append(RecSignal(kind: .watch, movieID: h.movieID, ratio: h.fraction, plays: playCounts[h.movieID] ?? 1, at: h.playedAt))
            if seeds.count < 60 { seeds.append(RecItem(id: h.movieID, number: h.number, title: h.title, type: h.type, coverURL: h.coverURL)) }
            if positives.count < 2, (h.fraction ?? 0.3) >= 0.3 { positives.append(RecSeed(id: h.movieID, number: h.number)) }
        }
        for w in WatchLaterStore.shared.items where w.addedAt > floor {
            signals.append(RecSignal(kind: .favorite, movieID: w.movieID, at: w.addedAt))
            if seeds.count < 80 { seeds.append(RecItem(id: w.movieID, number: w.number, title: w.title, type: w.type, coverURL: w.coverURL, thumbURL: w.thumbURL)) }
        }
        var follows: [RecFeature] = []
        for t in FollowStore.shared.targets {
            let kind: RecFeatureKind = t.kind == .actor ? .actor : (t.kind == .series ? .series : .maker)
            let f = RecFeature(kind: kind, id: t.tagID, name: t.name)
            follows.append(f)
            signals.append(RecSignal(kind: .follow, featureKey: f.key, featureName: f.name, at: t.addedAt))
        }
        signals += feedback.filter { $0.at > floor }
        return RecSnapshot(signals: signals, follows: follows, recentPositives: positives, seedItems: seeds)
    }

    func detail(_ id: String) async throws -> RecItem {
        Self.item(try await JavDBSDK.shared.movieDetail(id), detailed: true)
    }

    func list(_ r: RecSourcingPlan.Request) async throws -> [RecItem] {
        let sdk = JavDBSDK.shared
        let movies: [Movie]
        var via: RecFeature?
        switch r.source {
        case .actor, .follow:
            movies = try await sdk.actorMovies(r.id, page: 1, limit: 24, sortBy: "release"); via = RecFeature(kind: .actor, id: r.id, name: r.name)
        case .series:
            movies = try await sdk.seriesMovies(r.id, page: 1, limit: 24); via = RecFeature(kind: .series, id: r.id, name: r.name)
        case .maker:
            movies = try await sdk.makerMovies(r.id, page: 1, limit: 24); via = RecFeature(kind: .maker, id: r.id, name: r.name)
        case .tag:
            movies = try await sdk.moviesByTag(filterBy: "0:t::\(r.id)::", page: 1, limit: 24); via = RecFeature(kind: .tag, id: r.id, name: r.name)
        case .similar:
            movies = try await sdk.mayAlsoLike(r.id)
        case .popular:
            movies = try await sdk.rankings(type: "0", period: "weekly")
        case .latest:
            movies = try await sdk.latestMovies(page: 1, limit: 30, type: "0")
        }
        return movies.map { m in
            var item = Self.item(m, detailed: false)
            // List payloads often omit cast/tags: the list that found the movie is itself a feature.
            if let via, !item.features.contains(where: { $0.key == via.key }) { item.features.append(via) }
            return item
        }
    }

    static func item(_ m: Movie, detailed: Bool) -> RecItem {
        var features: [RecFeature] = []
        for a in m.actors ?? [] where a.gender != 1 { features.append(RecFeature(kind: .actor, id: a.id, name: a.displayName)) }
        if let id = m.seriesID, !id.isEmpty { features.append(RecFeature(kind: .series, id: id, name: m.seriesName ?? id)) }
        if let id = m.makerID, !id.isEmpty { features.append(RecFeature(kind: .maker, id: id, name: m.makerName ?? id)) }
        if let id = m.directorID, !id.isEmpty { features.append(RecFeature(kind: .director, id: id, name: m.directorName ?? id)) }
        for t in m.tags ?? [] { features.append(RecFeature(kind: .tag, id: t.id, name: t.name ?? t.id)) }
        let pop = Double((m.watchedCount ?? 0) + (m.wantWatchCount ?? 0) + (m.reviewsCount ?? 0))
        return RecItem(id: m.id, number: m.displayNumber, title: m.title ?? "", type: m.type, coverURL: m.coverURL, thumbURL: m.thumbURL,
                       releaseDate: m.releaseDate, rating: m.score, popularity: pop > 0 ? pop : nil, features: features,
                       detailed: detailed && !(m.tags ?? []).isEmpty, fetchedAt: Date())
    }
}

/// The detail page already has the full payload: remember it so the recommender needs fewer requests.
enum RecommendationIngest {
    @MainActor static func remember(_ movie: Movie) {
        RecommendationStore.shared.remember(JavDBRecommendationSource.item(movie, detailed: true))
    }
}

extension RecItem {
    var movie: Movie { Movie(id: id, type: type, number: number, title: title, thumbURL: thumbURL ?? coverURL, coverURL: coverURL) }
}
