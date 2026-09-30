//
//  FeatureStores.swift
//  AVDB
//
//  抽签历史、稍后再看、播放进度和新作提醒的本地记录。
//

import Foundation

struct DrawRecord: Codable, Identifiable, Hashable {
    let movieID: String
    let number: String
    let title: String
    let coverURL: String?
    let day: String
    var id: String { "\(day)-\(movieID)" }
}

struct WatchLaterItem: Codable, Identifiable, Hashable {
    let movieID: String
    let number: String
    let title: String
    let coverURL: String?
    let addedAt: Date
    var id: String { movieID }

    var movie: Movie {
        Movie(id: movieID, number: number, title: title, thumbURL: coverURL, coverURL: coverURL)
    }
}

struct PlaybackProgress: Codable, Hashable {
    let movieID: String
    let time: TimeInterval
    let duration: TimeInterval
    let updatedAt: Date
}

struct UpdateNotice: Codable, Identifiable, Hashable {
    let tagID: Int
    let tagName: String
    let movieID: String
    let number: String
    let title: String
    let coverURL: String?
    var id: String { "\(tagID)-\(movieID)" }

    var movie: Movie {
        Movie(id: movieID, number: number, title: title, thumbURL: coverURL, coverURL: coverURL)
    }
}

enum LocalJSONStore {
    static func load<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

@MainActor
final class DrawHistoryStore: ObservableObject {
    static let shared = DrawHistoryStore()
    @Published private(set) var records: [DrawRecord] = []
    private let key = "avdb.draw.history"

    private init() { records = LocalJSONStore.load(key, as: [DrawRecord].self) ?? [] }

    func contains(_ movieID: String, on day: String) -> Bool {
        records.contains { $0.movieID == movieID && $0.day == day }
    }

    func add(_ movie: Movie) {
        let record = DrawRecord(
            movieID: movie.id,
            number: movie.displayNumber,
            title: movie.displayTitle,
            coverURL: movie.coverURL ?? movie.thumbURL,
            day: Self.today
        )
        records.removeAll { $0.movieID == movie.id && $0.day == record.day }
        records.insert(record, at: 0)
        records = Array(records.prefix(180))
        LocalJSONStore.save(records, key: key)
    }

    static var today: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

@MainActor
final class WatchLaterStore: ObservableObject {
    static let shared = WatchLaterStore()
    @Published private(set) var items: [WatchLaterItem] = []
    private let key = "avdb.watch.later"

    private init() { items = LocalJSONStore.load(key, as: [WatchLaterItem].self) ?? [] }

    func contains(_ movieID: String) -> Bool { items.contains { $0.movieID == movieID } }

    func toggle(_ movie: Movie) {
        if contains(movie.id) {
            items.removeAll { $0.movieID == movie.id }
        } else {
            items.insert(WatchLaterItem(
                movieID: movie.id,
                number: movie.displayNumber,
                title: movie.displayTitle,
                coverURL: movie.coverURL ?? movie.thumbURL,
                addedAt: Date()
            ), at: 0)
        }
        LocalJSONStore.save(items, key: key)
    }
}

enum PlaybackProgressStore {
    private static let key = "avdb.playback.progress"

    static func progress(for movieID: String) -> PlaybackProgress? {
        let all = LocalJSONStore.load(key, as: [String: PlaybackProgress].self) ?? [:]
        return all[movieID]
    }

    static func save(movieID: String, time: TimeInterval, duration: TimeInterval) {
        guard time >= 5, duration > 30, time < duration - 15 else { return }
        var all = LocalJSONStore.load(key, as: [String: PlaybackProgress].self) ?? [:]
        all[movieID] = PlaybackProgress(movieID: movieID, time: time, duration: duration, updatedAt: Date())
        LocalJSONStore.save(all, key: key)
    }
}

@MainActor
final class UpdateNoticeStore: ObservableObject {
    static let shared = UpdateNoticeStore()
    @Published private(set) var notices: [UpdateNotice] = []
    private let key = "avdb.update.notices"
    private let seenKey = "avdb.update.seen"

    private init() { notices = LocalJSONStore.load(key, as: [UpdateNotice].self) ?? [] }

    func refresh() async {
        var seen = Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? [])
        var found: [UpdateNotice] = []
        for tag in FollowingTagsStore.shared.tags.prefix(12) {
            guard let filter = tag.moviesFilterBy else { continue }
            let movies = (try? await JavDBSDK.shared.moviesByTag(filterBy: filter, page: 1, limit: 6)) ?? []
            for movie in movies.prefix(3) where !seen.contains(movie.id) {
                found.append(UpdateNotice(
                    tagID: tag.id,
                    tagName: tag.displayName,
                    movieID: movie.id,
                    number: movie.displayNumber,
                    title: movie.displayTitle,
                    coverURL: movie.coverURL ?? movie.thumbURL
                ))
                seen.insert(movie.id)
            }
        }
        notices = Array((found + notices).prefix(60))
        UserDefaults.standard.set(Array(seen.prefix(1000)), forKey: seenKey)
        LocalJSONStore.save(notices, key: key)
    }

    func dismiss(_ id: String) {
        notices.removeAll { $0.id == id }
        LocalJSONStore.save(notices, key: key)
    }
}
