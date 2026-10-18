import Foundation
import Security
import Combine
import SwiftUI

extension Notification.Name { static let westernCoverChanged = Notification.Name("avdb.westernCoverChanged") }

struct WesternTokenStore: ExternalTokenStore {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.avdb.theporndb",
         kSecAttrAccount as String: "bearer", kSecAttrSynchronizable as String: false]
    }
    func read() throws -> String? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let s = SecItemCopyMatching(q as CFDictionary, &item)
        if s == errSecItemNotFound { return nil }
        guard s == errSecSuccess, let d = item as? Data, let t = String(data: d, encoding: .utf8) else { throw ExternalLibraryError.keychain(s) }
        return t
    }
    func write(_ token: String) throws {
        let a: [String: Any] = [kSecValueData as String: Data(token.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var s = SecItemUpdate(query as CFDictionary, a as CFDictionary)
        if s == errSecItemNotFound { s = SecItemAdd(query.merging(a) { _, new in new } as CFDictionary, nil) }
        guard s == errSecSuccess else { throw ExternalLibraryError.keychain(s) }
    }
    func clear() throws {
        let s = SecItemDelete(query as CFDictionary)
        guard s == errSecSuccess || s == errSecItemNotFound else { throw ExternalLibraryError.keychain(s) }
    }
}

/// Lock-backed snapshot: the resolver needs a synchronous cache namespace before
/// SwiftUI's first frame. No token/hash is ever used as a namespace or logged.
final class WesternCoverSettings: ObservableObject, @unchecked Sendable {
    static let shared = WesternCoverSettings()
    struct Snapshot: Sendable { let enabled: Bool; let namespace: UUID; let token: String? }
    let objectWillChange = ObservableObjectPublisher()
    private let lock = NSLock()
    private let store: ExternalTokenStore
    private let defaults: UserDefaults
    private var epoch = UUID()
    private var active: Bool
    init(store: ExternalTokenStore = WesternTokenStore(), defaults: UserDefaults = .standard) {
        self.store = store; self.defaults = defaults
        active = defaults.bool(forKey: "avdb.westernCovers.enabled") // Opt-in; sends work metadata.
    }
    func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return Snapshot(enabled: active, namespace: epoch, token: (try? store.read()) ?? nil)
    }
    var enabled: Bool { snapshot().enabled }
    var hasToken: Bool { snapshot().token?.isEmpty == false }
    var namespace: UUID { snapshot().namespace }
    func save(enabled: Bool, replacement: String) throws {
        guard replacement.count <= 4096, replacement.utf8.allSatisfy({ (33...126).contains($0) }) else { throw ExternalLibraryError.invalidToken }
        lock.lock()
        do {
            if !replacement.isEmpty { try store.write(replacement) }
            active = enabled; epoch = UUID(); defaults.set(enabled, forKey: "avdb.westernCovers.enabled")
            lock.unlock()
        } catch { lock.unlock(); throw error }
        changed()
    }
    func clear() throws {
        lock.lock()
        do { try store.clear(); epoch = UUID(); lock.unlock() }
        catch { lock.unlock(); throw error }
        changed()
    }
    private func changed() {
        DetailPosterResolver.clearWesternCaches()
        WesternCoverService.clear()
        objectWillChange.send()
        NotificationCenter.default.post(name: .westernCoverChanged, object: nil)
    }
}

struct WesternCoverSettingsView: View {
    @ObservedObject var settings: WesternCoverSettings = .shared
    @State private var enabled = false
    @State private var token = ""
    @State private var status = ""
    var body: some View {
        Form {
            Section("欧美封面 / ThePornDB") {
                Toggle("启用欧美外源择优", isOn: $enabled).accessibilityIdentifier("western-enabled")
                SecureField("TPDB Token（不回显）", text: $token)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("tpdb-token")
                Text(settings.hasToken ? "TPDB 已配置（不显示内容）" : "TPDB 未配置；启用后仍可使用 Data18")
                    .accessibilityIdentifier("tpdb-configuration")
                Button("保存") {
                    do { try settings.save(enabled: enabled, replacement: token); token = ""; status = "设置已保存" }
                    catch { token = ""; status = "保存失败，请检查令牌格式或解锁设备后重试" }
                }.accessibilityIdentifier("tpdb-save")
                Button("清除 Token", role: .destructive) {
                    do { try settings.clear(); token = ""; status = "令牌及旧封面缓存已清除" }
                    catch { token = ""; status = "清除失败，请解锁设备后重试" }
                }.accessibilityIdentifier("tpdb-clear")
                if !status.isEmpty { Text(status).accessibilityIdentifier("tpdb-status") }
            }
            Section("隐私与覆盖") {
                Text("默认关闭。启用后，仅在欧美详情页按需发送作品标题、品牌、发行日期、时长和已有原片商网页地址。不会发送视频播放地址、115 Cookie 或 pickcode。列表不搜索第三方。")
                Text("初期严格覆盖 Blacked Raw 单场景；不把电影正封与场景混用。身份不完整、重名、日期冲突、年龄确认、验证码或访问受限均保留 JavDB。")
                Text("Token 仅存本机钥匙串，仅发送到 https://api.theporndb.net；不会发送图片 CDN，也不跟随重定向。安装后请自行填写个人 Token，App 不内置测试凭据。")
                Text("最高指本次预算内成功验证图片的原生有效像素面积；不保证全网最大或无压缩。横图保持原比例，不裁成竖版。")
            }
        }.navigationTitle("欧美封面 / ThePornDB")
            .onAppear { enabled = settings.enabled }
            .onDisappear { token = "" }
    }
}

/// No redirect is followed. Data18's official link is inspected as identity
/// evidence only, without fetching a video or carrying headers to that target.
final class WesternRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var captured: String?
    let inspectOfficial: Bool
    init(inspectOfficial: Bool = false) { self.inspectOfficial = inspectOfficial }
    var official: String? { lock.lock(); defer { lock.unlock() }; return captured }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        if inspectOfficial, let url = request.url, let canonical = WesternCoverPolicy.canonicalOfficial(url.absoluteString) {
            lock.lock(); captured = canonical; lock.unlock()
        }
        completionHandler(nil)
    }
}

enum WesternCoverService {
    private static let pages = DetailPosterCache<[String]>(positiveTTL: 1800, negativeTTL: 60)
    // Across visible detail screens at most two metadata discovery jobs run.
    private static let limiter = WesternDiscoveryLimiter()
    static func clear() { pages.invalidate() }
    static func identity(_ movie: Movie) -> WesternCoverPolicy.Identity? {
        WesternCoverPolicy.identity(type: movie.type, number: movie.number, title: movie.originTitle ?? movie.title,
                                    date: movie.releaseDate, minutes: movie.duration, officialURL: movie.originalURL)
    }
    static func discover(movie: Movie, namespace: String, timeout: TimeInterval) async -> [String] {
        let settings = WesternCoverSettings.shared.snapshot()
        guard settings.enabled, let identity = identity(movie), timeout > 0 else { return [] }
        return await pages.value(key: namespace) {
            guard await limiter.acquire() else { return nil }
            let deadline = ProcessInfo.processInfo.systemUptime + min(4, timeout)
            async let a = tpdb(identity, settings: settings, deadline: deadline)
            async let b = data18(identity, deadline: deadline)
            let result = await a + b
            await limiter.release()
            guard !Task.isCancelled, WesternCoverSettings.shared.namespace == settings.namespace else { return nil }
            return Array(Set(result)).sorted()
        } ?? []
    }
    private static func remaining(_ deadline: TimeInterval) -> TimeInterval { max(0, min(1.3, deadline - ProcessInfo.processInfo.systemUptime)) }
    static func request(_ url: URL, token: String? = nil, deadline: TimeInterval, inspectOfficial: Bool = false) async -> (Data, String?)? {
        guard !Task.isCancelled, remaining(deadline) > 0,
              token == nil || WesternCoverPolicy.apiAllowed(url),
              WesternCoverPolicy.apiAllowed(url) || WesternCoverPolicy.dataPageAllowed(url) else { return nil }
        let guarder = WesternRedirectGuard(inspectOfficial: inspectOfficial)
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil; c.httpShouldSetCookies = false; c.urlCredentialStorage = nil; c.urlCache = nil
        c.timeoutIntervalForRequest = remaining(deadline); c.timeoutIntervalForResource = remaining(deadline)
        let session = URLSession(configuration: c, delegate: guarder, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            var r = URLRequest(url: url); r.timeoutInterval = remaining(deadline)
            r.setValue("application/json, text/html", forHTTPHeaderField: "Accept")
            if let token { r.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
            let (bytes, response) = try await session.bytes(for: r)
            guard let http = response as? HTTPURLResponse else { return nil }
            if inspectOfficial, (300...399).contains(http.statusCode), let official = guarder.official { return (Data(), official) }
            guard http.statusCode == 200, response.url == url, response.expectedContentLength <= 1024 * 1024 else { return nil }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 1024 * 1024, ProcessInfo.processInfo.systemUptime < deadline else { return nil }
                data.append(byte)
            }
            return (data, nil)
        } catch { return nil }
    }
    private static func tpdb(_ identity: WesternCoverPolicy.Identity, settings: WesternCoverSettings.Snapshot, deadline: TimeInterval) async -> [String] {
        guard let token = settings.token, !token.isEmpty else { return [] }
        var c = URLComponents(string: "https://api.theporndb.net/scenes")!
        c.queryItems = identity.officialURL.map { [URLQueryItem(name: "url", value: $0)] } ?? [
            URLQueryItem(name: "title", value: identity.title), URLQueryItem(name: "site", value: "202"),
            URLQueryItem(name: "date", value: identity.date), URLQueryItem(name: "per_page", value: "10")]
        guard let u = c.url, let (data, _) = await request(u, token: token, deadline: deadline),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = json["data"] as? [[String: Any]],
              let record = WesternCoverPolicy.uniqueRecord(records, identity: identity), let uuid = record["id"] as? String,
              let detailURL = URL(string: "https://api.theporndb.net/scenes/" + uuid),
              let (detail, _) = await request(detailURL, token: token, deadline: deadline),
              let object = try? JSONSerialization.jsonObject(with: detail) as? [String: Any],
              let verified = object["data"] as? [String: Any], verified["id"] as? String == uuid,
              WesternCoverPolicy.recordMatches(verified, identity: identity) else { return [] }
        return WesternCoverPolicy.tpdbImages(verified)
    }
    private static func data18(_ identity: WesternCoverPolicy.Identity, deadline: TimeInterval) async -> [String] {
        var c = URLComponents(string: "https://www.data18.com/sys/live.php")!
        c.queryItems = ["index":"", "key":identity.title, "key2":identity.title, "keyfull":identity.title, "t":"0", "b":"0", "page":"1", "back":"0"].sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let u = c.url, let (search, _) = await request(u, deadline: deadline), let html = String(data: search, encoding: .utf8) else { return [] }
        let links = WesternCoverPolicy.dataLinks(html, title: identity.title)
        guard links.count == 1, let raw = links.first, let page = URL(string: raw),
              let (bytes, _) = await request(page, deadline: deadline), let html = String(data: bytes, encoding: .utf8),
              let match = WesternCoverPolicy.dataMatch(html, identity: identity), let external = URL(string: match.officialLink),
              let (_, official) = await request(external, deadline: deadline, inspectOfficial: true), let official,
              identity.officialURL == nil || identity.officialURL == official else { return [] }
        var images = [match.image]
        if let raw = match.gallery, let gallery = URL(string: raw), let (bytes, _) = await request(gallery, deadline: deadline),
           let html = String(data: bytes, encoding: .utf8), let primary = WesternCoverPolicy.primaryImage(html) { images.append(primary) }
        return images
    }
}

private actor WesternDiscoveryLimiter {
    private var count = 0
    func acquire() -> Bool { guard count < 2, !Task.isCancelled else { return false }; count += 1; return true }
    func release() { count = max(0, count - 1) }
}
