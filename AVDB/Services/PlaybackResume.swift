//
//  PlaybackResume.swift
//  AVDB
//
//  Build 280 续播：按「番号 + 来源」记住播放位置。在线会话 id 每次都会变，所以续播是
//  重新解析同一来源的线路，再 seek 到记录位置。从不保存流地址、请求头、Cookie 或 token。
//

import Foundation

// MARK: - Pure policy (Foundation only; executed by scripts/test-resume-follow280.py)

enum PlaybackResumeKey {
    /// "missav|IPX-697". Nil when either side is empty.
    static func make(number: String?, source: String?) -> String? {
        guard let number, let source else { return nil }
        let n = normalize(number)
        let s = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !n.isEmpty, !s.isEmpty, !s.contains("|"), s.count <= 32 else { return nil }
        return s + "|" + n
    }
    /// Upper-case, full-width → ASCII, "_"/" " → "-", collapse repeated dashes.
    static func normalize(_ number: String) -> String {
        var out = ""
        for scalar in number.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars {
            var v = scalar.value
            if v >= 0xFF01 && v <= 0xFF5E { v -= 0xFEE0 }
            guard let s = Unicode.Scalar(v) else { continue }
            let c = Character(s)
            if c == "_" || c == " " || c == "\u{3000}" { out.append("-") } else { out.append(c) }
        }
        while out.contains("--") { out = out.replacingOccurrences(of: "--", with: "-") }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-")).uppercased()
    }
}

struct PlaybackResumeEntry: Codable, Equatable {
    var position: Double
    var length: Double
    var updatedAt: Date
}

enum PlaybackResumePolicy {
    static let minimumPosition = 5.0
    /// Items watched beyond 95 % start from the beginning.
    static let completedFraction = 0.95
    /// Start position for a new session, nil = from the beginning.
    static func startPosition(position: Double?, length: Double?, fromBeginning: Bool) -> Double? {
        guard !fromBeginning, let p = position, p.isFinite, p >= minimumPosition else { return nil }
        if let l = length, l.isFinite, l > 1 {
            if p / l > completedFraction || p >= l - 15 { return nil }
        }
        return p
    }
    static func isCompleted(position: Double?, length: Double?) -> Bool {
        guard let p = position, let l = length, p.isFinite, l.isFinite, l > 1 else { return false }
        return p / l > completedFraction || p >= l - 15
    }
    static func clock(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "00:00" }
        let s = Int(t); let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }
    /// 从 12:30 继续播放
    static func toast(_ position: Double) -> String { "从 " + clock(position) + " 继续播放" }
    /// Detail-page button title, nil when there is nothing to resume.
    static func buttonTitle(position: Double?, length: Double?, source: String?) -> String? {
        guard let start = startPosition(position: position, length: length, fromBeginning: false) else { return nil }
        let label = (source?.isEmpty == false) ? " · " + source! : ""
        return "续播 " + clock(start) + label
    }
    /// Build 288: compact pill title (same footprint as 「播放」); the source goes to the caption / menu.
    static func compactTitle(position: Double?, length: Double?) -> String? {
        guard let start = startPosition(position: position, length: length, fromBeginning: false) else { return nil }
        return "续播 " + clock(start)
    }
    /// 0…1 watched fraction for the pill's progress underline (nil without a usable length).
    static func progress(position: Double?, length: Double?) -> Double? {
        guard let p = position, let l = length, p.isFinite, l.isFinite, l > 1 else { return nil }
        return min(1, max(0, p / l))
    }
}

/// Keyed position book with throttle + cap. Pure value type so CI executes it with plain swiftc.
struct PlaybackResumeBook: Equatable {
    static let capacity = 600
    private(set) var entries: [String: PlaybackResumeEntry] = [:]
    init(entries: [String: PlaybackResumeEntry] = [:]) { self.entries = entries }
    func entry(_ key: String) -> PlaybackResumeEntry? { entries[key] }
    /// Returns true when worth persisting: forced, first value, or ≥5 s moved.
    @discardableResult
    mutating func save(_ key: String, position: Double, length: Double, at date: Date, force: Bool) -> Bool {
        guard !key.isEmpty, position.isFinite, position >= 0 else { return false }
        let old = entries[key]
        if !force, let old, abs(old.position - position) < 5 { return false }
        let len = (length.isFinite && length > 0) ? length : (old?.length ?? 0)
        entries[key] = PlaybackResumeEntry(position: position, length: len, updatedAt: date)
        if entries.count > Self.capacity {
            let drop = entries.sorted { $0.value.updatedAt < $1.value.updatedAt }.prefix(entries.count - Self.capacity)
            for (k, _) in drop { entries.removeValue(forKey: k) }
        }
        return true
    }
    /// Seed from an older 观看历史 entry without overwriting a newer per-source position.
    @discardableResult
    mutating func seed(_ key: String, position: Double?, length: Double?, at date: Date) -> Bool {
        guard entries[key] == nil, let position, position.isFinite, position > 0 else { return false }
        return save(key, position: position, length: length ?? 0, at: date, force: true)
    }
    mutating func remove(_ key: String) { entries.removeValue(forKey: key) }
    mutating func removeAll(number: String) {
        let n = "|" + PlaybackResumeKey.normalize(number)
        entries = entries.filter { !$0.key.hasSuffix(n) }
    }
}

/// What a 观看历史 tap does. Default tap = 续播.
enum PlaybackHistoryLaunch: String, Equatable {
    case resume, fromStart, details
}

/// Which player a history entry reopens (from its display source label).
enum PlaybackHistoryRoute: Equatable {
    case pan115, online(String), javdb, tangxin, detailsOnly
    static let onlineLabels = ["Jable", "MissAV", "123AV", "MemoJav", "JavDay"]
    static func route(source: String?, isTangxin: Bool) -> PlaybackHistoryRoute {
        if isTangxin { return .tangxin }
        guard let source else { return .detailsOnly }
        if source == "115" { return .pan115 }
        if source == "JavDB" { return .javdb }
        if let match = onlineLabels.first(where: { $0.caseInsensitiveCompare(source) == .orderedSame }) { return .online(match) }
        return .detailsOnly
    }
}

/// A resume request carried from 观看历史 / the detail play button into the detail page.
struct PlaybackAutoLaunch: Equatable {
    var route: PlaybackHistoryRoute
    var fromBeginning: Bool
    /// 观看历史 position, used to seed the 番号+来源 book for entries recorded before Build 280.
    var position: Double? = nil
    var length: Double? = nil
}

/// Online re-resolve: choose the line of the same 番号 from a fresh discovery (first exact code match).
enum OnlineResumeLinePolicy {
    static func pick(codes: [String], number: String) -> Int? {
        let want = PlaybackResumeKey.normalize(number)
        guard !want.isEmpty else { return nil }
        return codes.firstIndex { PlaybackResumeKey.normalize($0) == want }
    }
}

// MARK: - Store

/// Account-scoped like 观看历史 (same scope string); device-only UserDefaults.
@MainActor
final class PlaybackResumeStore {
    static let shared = PlaybackResumeStore()
    private var book = PlaybackResumeBook()
    private var scope: String?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private func key(_ scope: String) -> String { "avdb.play.resume.v1." + scope }
    private func ensure(_ expected: String?) -> Bool {
        guard let expected else { return false }
        if scope != expected {
            scope = expected
            let stored = defaults.data(forKey: key(expected)).flatMap { try? JSONDecoder().decode([String: PlaybackResumeEntry].self, from: $0) } ?? [:]
            book = PlaybackResumeBook(entries: stored)
        }
        return true
    }
    func entry(_ resumeKey: String, scope expected: String?) -> PlaybackResumeEntry? {
        guard ensure(expected) else { return nil }
        return book.entry(resumeKey)
    }
    func save(_ resumeKey: String, position: Double, length: Double, scope expected: String?, force: Bool) {
        guard ensure(expected), book.save(resumeKey, position: position, length: length, at: Date(), force: force) else { return }
        persist()
    }
    func seed(_ resumeKey: String, position: Double?, length: Double?, scope expected: String?) {
        guard ensure(expected), book.seed(resumeKey, position: position, length: length, at: Date()) else { return }
        persist()
    }
    func clear(number: String, scope expected: String?) {
        guard ensure(expected) else { return }
        book.removeAll(number: number); persist()
    }
    private func persist() {
        guard let scope, let data = try? JSONEncoder().encode(book.entries) else { return }
        defaults.set(data, forKey: key(scope))
    }
}
