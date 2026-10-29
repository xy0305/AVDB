//
//  FeatureStores.swift
//  AVDB
//
//  抽签历史、稍后再看、播放进度和新作提醒的本地记录。
//

import Foundation
import UIKit

/// Device-only, account-isolated history. Never stores a stream, cookie or token.
/// Build 277: optional source/position/duration/Tangxin page fields; old v1 JSON decodes unchanged.
struct PlaybackHistoryItem: Codable, Identifiable, Hashable {
    let movieID: String
    let number: String
    let title: String
    let type: String?
    let coverURL: String?
    var playedAt: Date
    /// Display label only (JavDB / 115 / MissAV / 糖心 …). Never a URL.
    var source: String? = nil
    /// Last watched media time / duration in seconds (updated on pause, exit and background).
    var position: Double? = nil
    var length: Double? = nil
    /// Public Tangxin video page + poster (https, no query) so the entry can reopen its own detail.
    var pageURL: String? = nil
    var posterURL: String? = nil
    var id: String { movieID }
    var movie: Movie { Movie(id: movieID, type: type, number: number, title: title, coverURL: coverURL) }
    var isTangxin: Bool { movieID.hasPrefix(PlaybackHistoryList.tangxinPrefix) }
    /// 0…1 when both values are meaningful; nil hides the bar.
    var fraction: Double? {
        guard let position, let length, length > 1, position.isFinite, length.isFinite, position > 0 else { return nil }
        return min(1, max(0, position / length))
    }
}

/// Pure ordering/dedupe/cap/progress policy. Foundation-only so CI can execute it with plain swiftc.
struct PlaybackHistoryList: Equatable {
    static let capacity = 500
    static let tangxinPrefix = "tangxin:"
    private(set) var items: [PlaybackHistoryItem] = []

    init(items: [PlaybackHistoryItem] = []) {
        self.items = items.sorted { $0.playedAt > $1.playedAt }
    }

    /// Dedupe by id and move to top; keep the previous resume point until new progress arrives.
    /// Returns ids evicted by the cap.
    @discardableResult
    mutating func record(_ entry: PlaybackHistoryItem) -> [String] {
        var next = entry
        if let old = items.first(where: { $0.movieID == entry.movieID }) {
            if next.position == nil { next.position = old.position; next.length = old.length }
            if next.source == nil { next.source = old.source }
            if next.pageURL == nil { next.pageURL = old.pageURL }
            if next.posterURL == nil { next.posterURL = old.posterURL }
        }
        items.removeAll { $0.movieID == entry.movieID }
        items.insert(next, at: 0)
        guard items.count > Self.capacity else { return [] }
        let evicted = items.dropFirst(Self.capacity).map(\.movieID)
        items = Array(items.prefix(Self.capacity))
        return evicted
    }

    /// Returns true when the change is worth persisting (forced, ≥10 s moved, or first value).
    @discardableResult
    mutating func updateProgress(_ id: String, position: Double, length: Double, at date: Date, force: Bool) -> Bool {
        guard position.isFinite, position >= 0, let index = items.firstIndex(where: { $0.movieID == id }) else { return false }
        var item = items[index]
        let moved = abs((item.position ?? -100) - position)
        guard force || moved >= 10 else { return false }
        item.position = position
        if length.isFinite, length > 0 { item.length = length }
        item.playedAt = date
        items[index] = item
        return true
    }

    mutating func remove(_ id: String) { items.removeAll { $0.movieID == id } }
    mutating func clear() { items = [] }
}

enum PlaybackHistoryFormat {
    /// 今天 21:05 / 昨天 08:30 / 10月3日 / 2025年12月1日
    static func relative(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = DateFormatter(); time.calendar = calendar; time.timeZone = calendar.timeZone
        time.locale = Locale(identifier: "zh_CN"); time.dateFormat = "HH:mm"
        if calendar.isDate(date, inSameDayAs: now) { return "今天 " + time.string(from: date) }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) {
            return "昨天 " + time.string(from: date)
        }
        let day = DateFormatter(); day.calendar = calendar; day.timeZone = calendar.timeZone
        day.locale = Locale(identifier: "zh_CN")
        day.dateFormat = calendar.component(.year, from: date) == calendar.component(.year, from: now) ? "M月d日" : "yyyy年M月d日"
        return day.string(from: date)
    }

    static func clock(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "00:00" }
        let s = Int(t); let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    /// 看到 12:30 / 共 2:00:00 · 已看完
    static func progressText(_ item: PlaybackHistoryItem) -> String? {
        guard let position = item.position, position > 0 else { return nil }
        if let length = item.length, length > 1 {
            if position >= length - 15 { return "已看完" }
            return "看到 " + clock(position) + " / " + clock(length)
        }
        return "看到 " + clock(position)
    }
}

@MainActor
final class PlaybackHistoryStore: ObservableObject {
    static let shared = PlaybackHistoryStore()
    static let guestScope = "guest"
    @Published private(set) var items: [PlaybackHistoryItem] = []
    private(set) var scope: String?
    private var list = PlaybackHistoryList()
    private let artworkCache = NSCache<NSString, UIImage>()
    private let defaults: UserDefaults
    private let directory: URL
    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PlaybackHistory", isDirectory: true)
    }
    private var key: String? { scope.map { "avdb.play.history.v1." + $0 } }

    /// Logged-out playback is kept in a separate device-only "guest" scope; accounts never see each other's history.
    func activate(accountID: Int?) {
        let next = accountID.map { "user-\($0)" } ?? Self.guestScope
        guard scope != next else { return }
        scope = next
        let stored = key.flatMap { defaults.data(forKey: $0) }.flatMap { try? JSONDecoder().decode([PlaybackHistoryItem].self, from: $0) } ?? []
        list = PlaybackHistoryList(items: stored)
        items = list.items
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
    /// Public https page/poster without credentials, query or fragment (Tangxin entries only).
    static func safePublicURL(_ value: URL?) -> String? {
        guard let value, let u = URLComponents(url: value, resolvingAgainstBaseURL: false), u.scheme == "https",
              let host = u.host?.lowercased(), !host.isEmpty, !host.contains("localhost"),
              u.user == nil, u.password == nil, u.query == nil, u.fragment == nil else { return nil }
        return value.absoluteString
    }
    private func imageURL(_ movieID: String) -> URL? {
        guard let scope else { return nil }
        // UTF8 hex is reversible identity, not a secret; no path traversal.
        let name = movieID.utf8.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(scope, isDirectory: true).appendingPathComponent(name + ".jpg")
    }
    func artwork(for movieID: String) -> UIImage? {
        guard let url = imageURL(movieID) else { return nil }
        if let cached = artworkCache.object(forKey: url.path as NSString) { return cached }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        artworkCache.setObject(image, forKey: url.path as NSString)
        return image
    }
    func record(_ movie: Movie, artwork: UIImage?, scope expected: String?, at date: Date = Date(),
                source: String? = nil, page: URL? = nil, poster: URL? = nil) {
        guard let expected, scope == expected, !movie.id.isEmpty else { return }
        if let artwork, let url = imageURL(movie.id) {
            let size = artwork.size
            if size.width > 0, size.height > 0 {
                let ratio = min(1, 640 / max(size.width, size.height))
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let image = UIGraphicsImageRenderer(size: CGSize(width: size.width * ratio, height: size.height * ratio), format: format).image { _ in
                    artwork.draw(in: CGRect(origin: .zero, size: CGSize(width: size.width * ratio, height: size.height * ratio)))
                }
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? image.jpegData(compressionQuality: 0.85)?.write(to: url, options: .atomic)
                artworkCache.removeObject(forKey: url.path as NSString)
            }
        }
        let entry = PlaybackHistoryItem(movieID: movie.id, number: movie.displayNumber, title: movie.displayTitle,
                                        type: movie.type, coverURL: Self.safeCoverURL(movie.coverURL ?? movie.thumbURL), playedAt: date,
                                        source: source, pageURL: Self.safePublicURL(page), posterURL: Self.safePublicURL(poster))
        for id in list.record(entry) { removeImage(id) }
        items = list.items
        persist()
    }
    /// Pause / exit / background force a write; periodic ticks write only after ≥10 s of movement.
    func updateProgress(_ movieID: String, position: Double, duration: Double, scope expected: String?, force: Bool = false, at date: Date = Date()) {
        guard let expected, scope == expected else { return }
        guard list.updateProgress(movieID, position: position, length: duration, at: date, force: force) else { return }
        items = list.items
        persist()
    }
    private func persist() {
        guard let key, let data = try? JSONEncoder().encode(list.items) else { return }
        defaults.set(data, forKey: key)
    }
    private func removeImage(_ id: String) {
        guard let url = imageURL(id) else { return }
        artworkCache.removeObject(forKey: url.path as NSString)
        try? FileManager.default.removeItem(at: url)
    }
    func remove(_ id: String) { removeImage(id); list.remove(id); items = list.items; persist() }
    func clear() { for item in list.items { removeImage(item.id) }; list.clear(); items = []; persist() }
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
