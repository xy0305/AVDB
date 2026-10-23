//
//  FeatureStores.swift
//  AVDB
//
//  抽签历史、稍后再看、播放进度和新作提醒的本地记录。
//

import Foundation
import UIKit

/// Device-only, account-isolated history. Never stores a stream, cookie or token.
struct PlaybackHistoryItem: Codable, Identifiable, Hashable {
    let movieID: String
    let number: String
    let title: String
    let type: String?
    let coverURL: String?
    let playedAt: Date
    var id: String { movieID }
    var movie: Movie { Movie(id: movieID, type: type, number: number, title: title, coverURL: coverURL) }
}

@MainActor
final class PlaybackHistoryStore: ObservableObject {
    static let shared = PlaybackHistoryStore()
    @Published private(set) var items: [PlaybackHistoryItem] = []
    private(set) var scope: String?
    private let defaults: UserDefaults
    private let directory: URL
    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PlaybackHistory", isDirectory: true)
    }
    private var key: String? { scope.map { "avdb.play.history.v1." + $0 } }

    func activate(accountID: Int?) {
        let next = accountID.map { "user-\($0)" }
        guard scope != next else { return }
        scope = next
        items = key.flatMap { defaults.data(forKey: $0) }.flatMap { try? JSONDecoder().decode([PlaybackHistoryItem].self, from: $0) } ?? []
        items.sort { $0.playedAt > $1.playedAt }
    }
    /// Public unsigned artwork only. Reject rather than strip signed URLs.
    static func safeCoverURL(_ value: String?) -> String? {
        guard let value, let u = URLComponents(string: value), u.scheme == "https",
              let host = u.host?.lowercased(), !host.isEmpty,
              u.user == nil, u.password == nil, u.query == nil, u.fragment == nil,
              !host.contains("115"), !host.contains("localhost"), !host.contains(":") else { return nil }
        let ext = (u.path as NSString).pathExtension.lowercased()
        guard ["jpg", "jpeg", "png", "webp", "avif"].contains(ext) else { return nil }
        return value
    }
    private func imageURL(_ movieID: String) -> URL? {
        guard let scope else { return nil }
        // UTF8 hex is reversible identity, not a secret; no path traversal.
        let name = movieID.utf8.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(scope, isDirectory: true).appendingPathComponent(name + ".jpg")
    }
    func artwork(for movieID: String) -> UIImage? {
        guard let url = imageURL(movieID) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
    func record(_ movie: Movie, artwork: UIImage?, scope expected: String?, at date: Date = Date()) {
        guard let expected, scope == expected, !movie.id.isEmpty else { return }
        if let artwork, let url = imageURL(movie.id) {
            let size = artwork.size
            if size.width > 0, size.height > 0 {
                let ratio = min(1, 480 / max(size.width, size.height))
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let image = UIGraphicsImageRenderer(size: CGSize(width: size.width * ratio, height: size.height * ratio), format: format).image { _ in
                    artwork.draw(in: CGRect(origin: .zero, size: CGSize(width: size.width * ratio, height: size.height * ratio)))
                }
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? image.jpegData(compressionQuality: 0.85)?.write(to: url, options: .atomic)
            }
        }
        items.removeAll { $0.movieID == movie.id }
        items.insert(PlaybackHistoryItem(movieID: movie.id, number: movie.displayNumber, title: movie.displayTitle,
                                        type: movie.type, coverURL: Self.safeCoverURL(movie.coverURL ?? movie.thumbURL), playedAt: date), at: 0)
        for item in items.dropFirst(300) { removeImage(item.movieID) }
        items = Array(items.prefix(300))
        persist()
    }
    private func persist() {
        guard let key, let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: key)
    }
    private func removeImage(_ id: String) { if let url = imageURL(id) { try? FileManager.default.removeItem(at: url) } }
    func remove(_ id: String) { removeImage(id); items.removeAll { $0.id == id }; persist() }
    func clear() { for item in items { removeImage(item.id) }; items = []; persist() }
}

/// A ready event is not playback. Require an active engine and forward media-time movement.
struct PlaybackHistoryStartGate {
    private var previous: TimeInterval?
    private(set) var recorded = false
    mutating func sample(time: TimeInterval, playing: Bool, seeking: Bool, failed: Bool) -> Bool {
        guard !recorded else { return false }
        guard playing, !seeking, !failed, time.isFinite, time >= 0 else { previous = nil; return false }
        defer { previous = time }
        guard let previous, time > previous, time - previous < 2 else { return false }
        recorded = true
        return true
    }
}

struct DrawRecord: Codable, Identifiable, Hashable {
    let movieID: String
    let number: String
    let title: String
    let coverURL: String?
    let thumbURL: String?
    let type: String?
    let day: String
    var id: String { "\(day)-\(movieID)" }
}

struct WatchLaterItem: Codable, Identifiable, Hashable {
    let movieID: String
    let number: String
    let title: String
    let coverURL: String?
    let thumbURL: String?
    let type: String?
    let addedAt: Date
    var id: String { movieID }

    var movie: Movie {
        Movie(id: movieID, type: type, number: number, title: title, thumbURL: thumbURL ?? coverURL, coverURL: coverURL)
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
    let thumbURL: String?
    let type: String?
    var id: String { "\(tagID)-\(movieID)" }

    var movie: Movie {
        Movie(id: movieID, type: type, number: number, title: title, thumbURL: thumbURL ?? coverURL, coverURL: coverURL)
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
            thumbURL: movie.thumbURL,
            type: movie.type,
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
            thumbURL: movie.thumbURL,
            type: movie.type,
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
                    coverURL: movie.coverURL ?? movie.thumbURL,
                    thumbURL: movie.thumbURL,
                    type: movie.type
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
