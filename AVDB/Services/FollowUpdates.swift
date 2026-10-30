//
//  FollowUpdates.swift
//  AVDB
//
//  Build 280 追更提醒：本机关注 女优 / 系列 / 片商，前台 + BGAppRefreshTask 检查 JavDB 新作，
//  用本地通知（UNUserNotificationCenter）提醒。不使用 CloudKit / APNs 远程推送（自签 / 侧载包没有这些能力）。
//  关注列表只存在本机，未登录也可用；请求沿用当前 JavDB 会话（APIClient 的 token），不会发起登录。
//

import Foundation

// MARK: - Pure policy (Foundation only; executed by scripts/test-resume-follow280.py)

enum FollowKind: String, Codable, CaseIterable, Hashable {
    case actor, series, maker
    var label: String {
        switch self { case .actor: return "女优"; case .series: return "系列"; case .maker: return "片商" }
    }
    var symbol: String {
        switch self { case .actor: return "person.crop.circle"; case .series: return "square.stack"; case .maker: return "building.2" }
    }
}

struct FollowTarget: Codable, Hashable, Identifiable {
    var kind: FollowKind
    var tagID: String
    var name: String
    /// JavDB catalogue type ("0" 有码, "1" 无码, …).
    var type: String = "0"
    var addedAt: Date
    var lastChecked: Date? = nil
    /// The first successful check only records what already exists (no notification flood).
    var baselined: Bool = false
    /// Newest known movie ids, newest first (capped).
    var knownIDs: [String] = []
    var id: String { FollowTarget.makeID(kind, tagID: tagID, type: type) }
    static func makeID(_ kind: FollowKind, tagID: String, type: String) -> String { kind.rawValue + ":" + type + ":" + tagID }
}

struct ReleaseFeedItem: Codable, Hashable, Identifiable {
    var movieID: String
    var number: String
    var title: String
    var coverURL: String?
    var releaseDate: String?
    var followID: String
    var followName: String
    var kind: FollowKind
    var foundAt: Date
    var read: Bool = false
    var id: String { movieID }
}

struct FollowFetchedMovie: Equatable {
    var id: String
    var number: String
    var title: String
    var coverURL: String? = nil
    var releaseDate: String? = nil
}

enum FollowRunReason: String { case foreground, background, manual }

enum FollowUpdatePolicy {
    /// One request per followed tag at most every 6 h (manual 「检查更新」 bypasses it).
    static let minInterval: TimeInterval = 6 * 3600
    /// Foreground runs are additionally throttled app-wide.
    static let foregroundMinInterval: TimeInterval = 15 * 60
    static let knownCap = 80
    static let feedCap = 300
    static let fetchLimit = 12
    /// Gap between two JavDB requests in one run.
    static let requestSpacingSeconds = 1.2
    /// Abort a run after this many consecutive failures (offline / rate-limited / session problem).
    static let maxConsecutiveFailures = 3
    static let individualNotificationLimit = 3
    static let backgroundEarliestInterval: TimeInterval = 4 * 3600

    static func cap(_ reason: FollowRunReason) -> Int {
        switch reason { case .background: return 8; case .foreground: return 20; case .manual: return 40 }
    }

    /// Oldest-checked first, never-checked before everything.
    static func due(_ targets: [FollowTarget], now: Date, reason: FollowRunReason) -> [FollowTarget] {
        let force = reason == .manual
        let eligible = targets.filter { t in
            guard let last = t.lastChecked else { return true }
            return force || now.timeIntervalSince(last) >= minInterval
        }
        let sorted = eligible.sorted { a, b in
            switch (a.lastChecked, b.lastChecked) {
            case (nil, nil): return a.addedAt < b.addedAt
            case (nil, _): return true
            case (_, nil): return false
            case let (x?, y?): return x < y
            }
        }
        return Array(sorted.prefix(cap(reason)))
    }

    static func shouldRunForeground(lastRun: Date?, now: Date) -> Bool {
        guard let lastRun else { return true }
        return now.timeIntervalSince(lastRun) >= foregroundMinInterval
    }

    /// Merges one fetch: returns the updated target and the movies that are new since the last check.
    static func merge(_ target: FollowTarget, fetched: [FollowFetchedMovie], now: Date) -> (FollowTarget, [FollowFetchedMovie]) {
        var t = target
        t.lastChecked = now
        var seenInFetch = Set<String>()
        let unique = fetched.filter { !$0.id.isEmpty && seenInFetch.insert($0.id).inserted }
        let ids = unique.map(\.id)
        guard t.baselined else {
            t.baselined = true
            t.knownIDs = Array(ids.prefix(knownCap))
            return (t, [])
        }
        let known = Set(t.knownIDs)
        let fresh = unique.filter { !known.contains($0.id) }
        var merged: [String] = []
        var s = Set<String>()
        for id in fresh.map(\.id) + t.knownIDs where s.insert(id).inserted { merged.append(id) }
        t.knownIDs = Array(merged.prefix(knownCap))
        return (t, fresh)
    }

    /// Dedupes by movie id against the feed (a movie followed via 女优 and 系列 appears once).
    static func insert(_ new: [ReleaseFeedItem], into feed: [ReleaseFeedItem]) -> (feed: [ReleaseFeedItem], inserted: [ReleaseFeedItem]) {
        var ids = Set(feed.map(\.movieID))
        var inserted: [ReleaseFeedItem] = []
        for item in new where ids.insert(item.movieID).inserted { inserted.append(item) }
        let all = (inserted + feed).sorted { $0.foundAt > $1.foundAt }
        return (Array(all.prefix(feedCap)), inserted)
    }

    /// Notification plan: up to 3 individual notifications, otherwise one summary.
    struct NotificationPlan: Equatable { var identifier: String; var title: String; var body: String }
    static func notifications(for items: [ReleaseFeedItem]) -> [NotificationPlan] {
        guard !items.isEmpty else { return [] }
        if items.count <= individualNotificationLimit {
            return items.map { NotificationPlan(identifier: "avdb.follow." + $0.movieID,
                                                title: $0.followName + " 有新作",
                                                body: [$0.number, $0.title].filter { !$0.isEmpty }.joined(separator: " ")) }
        }
        var seenNames = Set<String>()
        let names = items.map(\.followName).filter { seenNames.insert($0).inserted }
        let head = names.prefix(3).joined(separator: "、") + (names.count > 3 ? " 等" : "")
        let numbers = items.prefix(4).map(\.number).joined(separator: "、")
        return [NotificationPlan(identifier: "avdb.follow.summary." + items.map(\.movieID).sorted().joined(separator: ",").prefix(120),
                                 title: "关注更新 \(items.count) 部",
                                 body: head + "：" + numbers + (items.count > 4 ? " …" : ""))]
    }
}

// MARK: - Store

#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

/// Device-local follow list (works signed-out). Server-side 关注 (actor page) stays best-effort extra.
@MainActor
final class FollowStore: ObservableObject {
    static let shared = FollowStore()
    static let storageKey = "avdb.follow.targets.v1"
    @Published private(set) var targets: [FollowTarget] = []
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        targets = defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode([FollowTarget].self, from: $0) } ?? []
    }
    func isFollowing(_ kind: FollowKind, tagID: String, type: String = "0") -> Bool {
        targets.contains { $0.id == FollowTarget.makeID(kind, tagID: tagID, type: type) }
    }
    /// Returns the new following state. The first follow ever asks for notification permission.
    @discardableResult
    func toggle(_ kind: FollowKind, tagID: String, name: String, type: String = "0") -> Bool {
        let id = FollowTarget.makeID(kind, tagID: tagID, type: type)
        if targets.contains(where: { $0.id == id }) {
            targets.removeAll { $0.id == id }; persist()
            return false
        }
        guard !tagID.isEmpty else { return false }
        targets.insert(FollowTarget(kind: kind, tagID: tagID, name: name.isEmpty ? tagID : name, type: type, addedAt: Date()), at: 0)
        persist()
        FollowNotifier.requestAuthorizationIfNeeded()
        FollowBackgroundRefresh.schedule()
        // Baseline the new follow soon so its first real update can notify.
        Task { await FollowUpdateChecker.shared.run(.manual, only: id) }
        return true
    }
    func remove(_ id: String) { targets.removeAll { $0.id == id }; persist() }
    func update(_ target: FollowTarget) {
        guard let i = targets.firstIndex(where: { $0.id == target.id }) else { return }
        var t = target; t.name = targets[i].name   // a rename while checking must not be lost
        targets[i] = t; persist()
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(targets) { defaults.set(data, forKey: Self.storageKey) }
    }
}

/// In-app 更新 feed with an unread badge in 我的.
@MainActor
final class ReleaseFeedStore: ObservableObject {
    static let shared = ReleaseFeedStore()
    static let storageKey = "avdb.follow.feed.v1"
    @Published private(set) var items: [ReleaseFeedItem] = []
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        items = defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode([ReleaseFeedItem].self, from: $0) } ?? []
    }
    var unreadCount: Int { items.filter { !$0.read }.count }
    @discardableResult
    func add(_ new: [ReleaseFeedItem]) -> [ReleaseFeedItem] {
        let result = FollowUpdatePolicy.insert(new, into: items)
        items = result.feed; persist()
        return result.inserted
    }
    func markAllRead() {
        guard items.contains(where: { !$0.read }) else { return }
        for i in items.indices { items[i].read = true }
        persist(); FollowNotifier.syncBadge(0)
    }
    func remove(_ id: String) { items.removeAll { $0.id == id }; persist() }
    func clear() { items = []; persist(); FollowNotifier.syncBadge(0) }
    private func persist() {
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: Self.storageKey) }
    }
}

enum FollowNotifier {
    static func requestAuthorizationIfNeeded() {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
        }
        #endif
    }
    static func post(_ items: [ReleaseFeedItem], badge: Int) {
        #if canImport(UserNotifications)
        let plans = FollowUpdatePolicy.notifications(for: items)
        guard !plans.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            for plan in plans {
                let content = UNMutableNotificationContent()
                content.title = plan.title
                content.body = plan.body
                content.sound = .default
                content.threadIdentifier = "avdb.follow"
                content.badge = NSNumber(value: badge)
                content.userInfo = ["avdb.follow": true]
                // Same identifier = same movie: iOS replaces instead of stacking duplicates.
                center.add(UNNotificationRequest(identifier: plan.identifier, content: content, trigger: nil))
            }
        }
        #endif
    }
    static func syncBadge(_ count: Int) {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().setBadgeCount(count) { _ in }
        #endif
    }
    static func authorizationText() async -> String {
        #if canImport(UserNotifications)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return "通知：已允许"
        case .denied: return "通知：已关闭（可在 设置 › 通知 中开启），仍会在这里显示更新"
        default: return "通知：首次关注时会询问"
        }
        #else
        return ""
        #endif
    }
}

/// Fetches the newest releases of each due follow through the existing JavDB API (current session).
@MainActor
final class FollowUpdateChecker: ObservableObject {
    static let shared = FollowUpdateChecker()
    static let lastRunKey = "avdb.follow.lastRun.v1"
    @Published private(set) var isRunning = false
    @Published private(set) var status: String?
    private var lastForegroundRun: Date?
    var lastRunAt: Date? { UserDefaults.standard.object(forKey: Self.lastRunKey) as? Date }

    /// Called when the scene becomes active (throttled app-wide).
    func foregroundCheck() {
        guard !FollowStore.shared.targets.isEmpty,
              FollowUpdatePolicy.shouldRunForeground(lastRun: lastForegroundRun, now: Date()) else { return }
        lastForegroundRun = Date()
        Task {
            // Let the login restore (scenePhase .active) settle first; the request uses whatever session exists.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await run(.foreground)
        }
    }

    /// Returns the number of new feed items. Re-entrant calls return 0.
    @discardableResult
    func run(_ reason: FollowRunReason, only: String? = nil) async -> Int {
        guard !isRunning else { return 0 }
        isRunning = true
        defer { isRunning = false }
        let all = FollowStore.shared.targets.filter { only == nil || $0.id == only }
        let due = FollowUpdatePolicy.due(all, now: Date(), reason: reason)
        guard !due.isEmpty else { status = all.isEmpty ? nil : "暂无需要检查的关注（每个关注 6 小时最多检查一次）"; return 0 }
        status = "正在检查 \(due.count) 个关注…"
        var found: [ReleaseFeedItem] = []
        var failures = 0, checked = 0
        for (index, target) in due.enumerated() {
            if Task.isCancelled { break }
            if index > 0 { try? await Task.sleep(nanoseconds: UInt64(FollowUpdatePolicy.requestSpacingSeconds * 1_000_000_000)) }
            do {
                let movies = try await Self.fetch(target)
                failures = 0; checked += 1
                let fetched = movies.map { FollowFetchedMovie(id: $0.id, number: $0.displayNumber, title: $0.title ?? "",
                                                              coverURL: $0.coverURL ?? $0.thumbURL, releaseDate: $0.releaseDate) }
                let (updated, fresh) = FollowUpdatePolicy.merge(target, fetched: fetched, now: Date())
                // A follow removed during the run is not resurrected (update() ignores unknown ids).
                FollowStore.shared.update(updated)
                found += fresh.map { ReleaseFeedItem(movieID: $0.id, number: $0.number, title: $0.title, coverURL: $0.coverURL,
                                                     releaseDate: $0.releaseDate, followID: target.id, followName: target.name,
                                                     kind: target.kind, foundAt: Date()) }
            } catch {
                failures += 1
                if failures >= FollowUpdatePolicy.maxConsecutiveFailures { break }
            }
        }
        let inserted = ReleaseFeedStore.shared.add(found)
        UserDefaults.standard.set(Date(), forKey: Self.lastRunKey)
        if !inserted.isEmpty { FollowNotifier.post(inserted, badge: ReleaseFeedStore.shared.unreadCount) }
        status = failures >= FollowUpdatePolicy.maxConsecutiveFailures && checked == 0
            ? "检查失败（网络或 JavDB 会话问题），稍后自动重试"
            : (inserted.isEmpty ? "已检查 \(checked) 个关注，没有新作" : "发现 \(inserted.count) 部新作")
        return inserted.count
    }

    private static func fetch(_ target: FollowTarget) async throws -> [Movie] {
        let limit = FollowUpdatePolicy.fetchLimit
        switch target.kind {
        case .actor: return try await JavDBSDK.shared.actorMovies(target.tagID, page: 1, limit: limit, type: target.type, sortBy: "release")
        case .series: return try await JavDBSDK.shared.seriesMovies(target.tagID, type: target.type, page: 1, limit: limit)
        case .maker: return try await JavDBSDK.shared.makerMovies(target.tagID, type: target.type, page: 1, limit: limit)
        }
    }
}

/// BGAppRefreshTask. iOS decides when (or whether) it runs; the foreground check is the reliable path.
enum FollowBackgroundRefresh {
    static let identifier = "org.avdb.follow.refresh"
    static func register() {
        #if canImport(BackgroundTasks) && os(iOS)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            handle(task)
        }
        #endif
    }
    static func schedule() {
        #if canImport(BackgroundTasks) && os(iOS)
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: FollowUpdatePolicy.backgroundEarliestInterval)
        try? BGTaskScheduler.shared.submit(request)
        #endif
    }
    #if canImport(BackgroundTasks) && os(iOS)
    private static func handle(_ task: BGAppRefreshTask) {
        schedule()
        let work = Task { @MainActor in
            guard !FollowStore.shared.targets.isEmpty else { task.setTaskCompleted(success: true); return }
            _ = await FollowUpdateChecker.shared.run(.background)
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }
    #endif
}
