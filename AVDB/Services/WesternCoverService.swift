import Foundation
import Security
import Combine
import SwiftUI

extension Notification.Name { static let westernCoverChanged = Notification.Name("avdb.westernCoverChanged") }

struct WesternTokenStore: ExternalTokenStore {
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.avdb.theporndb", kSecAttrAccount as String: "bearer", kSecAttrSynchronizable as String: false] }
    func read() throws -> String? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?; let s = SecItemCopyMatching(q as CFDictionary, &item)
        if s == errSecItemNotFound { return nil }
        guard s == errSecSuccess, let d = item as? Data, let t = String(data: d, encoding: .utf8) else { throw ExternalLibraryError.keychain(s) }; return t
    }
    func write(_ token: String) throws {
        let a: [String: Any] = [kSecValueData as String: Data(token.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var s = SecItemUpdate(query as CFDictionary, a as CFDictionary)
        if s == errSecItemNotFound { s = SecItemAdd(query.merging(a) { _, new in new } as CFDictionary, nil) }
        guard s == errSecSuccess else { throw ExternalLibraryError.keychain(s) }
    }
    func clear() throws { let s = SecItemDelete(query as CFDictionary); guard s == errSecSuccess || s == errSecItemNotFound else { throw ExternalLibraryError.keychain(s) } }
}
final class WesternCoverSettings: ObservableObject, @unchecked Sendable {
    static let shared = WesternCoverSettings()
    struct Snapshot: Sendable { let enabled: Bool; let namespace: UUID; let token: String? }
    let objectWillChange = ObservableObjectPublisher()
    private let lock = NSLock(); private let store: ExternalTokenStore; private let defaults: UserDefaults
    private var epoch = UUID(); private var active: Bool
    init(store: ExternalTokenStore = WesternTokenStore(), defaults: UserDefaults = .standard) { self.store = store; self.defaults = defaults; active = defaults.bool(forKey: "avdb.westernCovers.enabled") }
    func snapshot() -> Snapshot { lock.lock(); defer { lock.unlock() }; return Snapshot(enabled: active, namespace: epoch, token: (try? store.read()) ?? nil) }
    var enabled: Bool { snapshot().enabled }; var hasToken: Bool { snapshot().token?.isEmpty == false }; var namespace: UUID { snapshot().namespace }
    func save(enabled: Bool, replacement: String) throws {
        guard replacement.count <= 4096, replacement.utf8.allSatisfy({ (33...126).contains($0) }) else { throw ExternalLibraryError.invalidToken }
        lock.lock()
        do { if !replacement.isEmpty { try store.write(replacement) }; active = enabled; epoch = UUID(); defaults.set(enabled, forKey: "avdb.westernCovers.enabled"); lock.unlock() }
        catch { lock.unlock(); throw error }
        changed()
    }
    func clear() throws { lock.lock(); do { try store.clear(); epoch = UUID(); lock.unlock() } catch { lock.unlock(); throw error }; changed() }
    private func changed() {
        DetailPosterResolver.clearWesternCaches(); WesternCoverService.clear()
        objectWillChange.send(); NotificationCenter.default.post(name: .westernCoverChanged, object: nil)
    }
}
struct WesternCoverSettingsView: View {
    @ObservedObject var settings: WesternCoverSettings = .shared
    @State private var enabled = false; @State private var token = ""; @State private var status = ""; @State private var testing = false
    var body: some View {
        Form {
            Section("欧美封面 / ThePornDB") {
                Toggle("启用欧美外源择优", isOn: $enabled).accessibilityIdentifier("western-enabled")
                Text("开关和 Token 修改后需点“保存”才会生效。留空保存会保留已配置 Token。").font(.caption)
                SecureField("TPDB Token（不回显）", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("tpdb-token")
                Text(settings.hasToken ? "TPDB 已配置（不显示内容）" : "TPDB 未配置；保存启用后仍可尝试 Data18").accessibilityIdentifier("tpdb-configuration")
                Button("保存") {
                    do { try settings.save(enabled: enabled, replacement: token); token = ""; status = "设置已保存，旧请求和缓存已失效" }
                    catch { token = ""; status = "保存失败，请检查令牌格式或解锁设备" }
                }.accessibilityIdentifier("tpdb-save")
                Button("清除 Token", role: .destructive) {
                    do { try settings.clear(); token = ""; status = "令牌已清除，旧请求和缓存已失效" }
                    catch { token = ""; status = "清除失败，请解锁设备" }
                }.accessibilityIdentifier("tpdb-clear")
                Button(testing ? "连接测试中…" : "测试已保存 Token 的连接") {
                    testing = true; let namespace = settings.namespace
                    Task {
                        let result = await WesternCoverService.testConnection()
                        if namespace == settings.namespace { status = result }
                        testing = false
                    }
                }.disabled(testing).accessibilityIdentifier("tpdb-test")
                if !status.isEmpty { Text(status).font(.caption).accessibilityIdentifier("tpdb-status") }
            }
            Section("隐私与覆盖") {
                Text("默认关闭。启用后仅在欧美详情发送原始标题、品牌、日期、时长或官网地址。列表不搜索外源。支持经实测的 Blacked Raw、Blacked、Vixen、Tushy 场景；未知品牌、电影、重名或冲突不猜。")
                Text("Token 仅存本机钥匙串，仅 Bearer 发给 api.theporndb.net，不跟随重定向、不发图片 CDN。安装后自行填写个人 Token；App 不内置凭据。")
                Text("Data18 年龄确认、验证码、访问限制会显示诊断，不伪造 Cookie。MGStage 本次实站返回年龄页，未启用未经验证的新规则；既有 MGS 图源保持不变。")
                Text("最多 6 张、2 路图片、12 秒总预算，按成功解码的原生有效像素择优。保留横原图，不接受智能竖裁/upscale，不保证全网最高清或压缩最佳。")
            }
        }.navigationTitle("欧美封面").onAppear { enabled = settings.enabled }.onDisappear { token = "" }
    }
}

/// Never follows redirects: Authorization cannot leave the API origin.
final class WesternRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
enum WesternCoverService {
    struct Discovery: Sendable { let images: [String]; let diagnostic: String }
    private static let pages = DetailPosterCache<Discovery>(positiveTTL: 1800, negativeTTL: 45)
    static func clear() { pages.invalidate() }
    static func diagnostic(movie: Movie, namespace: String) -> String {
        if !WesternCoverSettings.shared.enabled { return "外源未启用（未请求）" }
        if identity(movie) == nil { return "品牌未支持或同片信息不足（未请求）" }
        return pages.snapshot(key: namespace).artwork?.diagnostic ?? "外源请求尚未完成或已取消"
    }
    static func identity(_ movie: Movie) -> WesternCoverPolicy.Identity? {
        WesternCoverPolicy.identity(type: movie.type, number: movie.number, title: movie.originTitle ?? movie.title, date: movie.releaseDate, minutes: movie.duration, officialURL: movie.originalURL)
    }
    static func discover(movie: Movie, namespace: String, timeout: TimeInterval) async -> Discovery {
        let s = WesternCoverSettings.shared.snapshot()
        guard s.enabled else { return Discovery(images: [], diagnostic: "外源未启用（未请求）") }
        guard let i = identity(movie) else { return Discovery(images: [], diagnostic: "品牌未支持或同片信息不足（未请求）") }
        return await pages.value(key: namespace) {
            let deadline = ProcessInfo.processInfo.systemUptime + min(5, timeout)
            async let a = tpdb(i, settings: s, deadline: deadline)
            async let b = data18(i, deadline: deadline)
            let (x, y) = await (a, b)
            guard !Task.isCancelled, WesternCoverSettings.shared.namespace == s.namespace else { return nil }
            return Discovery(images: Array(Set(x.images + y.images)).sorted(), diagnostic: x.diagnostic + "；" + y.diagnostic)
        } ?? Discovery(images: [], diagnostic: "外源请求取消或超时")
    }
    struct Reply: Sendable { let data: Data; let status: Int; let timedOut: Bool }
    static func request(_ url: URL, token: String? = nil, deadline: TimeInterval) async -> Reply {
        let remaining = min(2.5, deadline - ProcessInfo.processInfo.systemUptime)
        guard !Task.isCancelled, remaining > 0, token == nil || WesternCoverPolicy.apiAllowed(url), WesternCoverPolicy.apiAllowed(url) || WesternCoverPolicy.dataPageAllowed(url) else { return Reply(data: Data(), status: 0, timedOut: true) }
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil; c.httpShouldSetCookies = false; c.urlCredentialStorage = nil; c.urlCache = nil
        c.timeoutIntervalForRequest = remaining; c.timeoutIntervalForResource = remaining
        let session = URLSession(configuration: c, delegate: WesternRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            var r = URLRequest(url: url); r.timeoutInterval = remaining
            r.setValue("application/json, text/html", forHTTPHeaderField: "Accept")
            if let token { r.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
            let (bytes, response) = try await session.bytes(for: r)
            guard let http = response as? HTTPURLResponse, response.url == url, response.expectedContentLength <= 1024 * 1024 else { return Reply(data: Data(), status: 0, timedOut: false) }
            if http.statusCode != 200 { return Reply(data: Data(), status: http.statusCode, timedOut: false) }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 1024 * 1024, ProcessInfo.processInfo.systemUptime < deadline else { return Reply(data: Data(), status: 0, timedOut: true) }; data.append(byte)
            }
            return Reply(data: data, status: 200, timedOut: false)
        } catch { return Reply(data: Data(), status: 0, timedOut: (error as? URLError)?.code == .timedOut) }
    }
    static func failure(_ r: Reply) -> String {
        if r.status == 401 || r.status == 403 { return "鉴权/访问被拒（HTTP \(r.status)）" }
        if (300...399).contains(r.status) { return "重定向/年龄确认未完成" }
        if r.timedOut { return "请求超时" }
        return r.status > 0 ? "请求失败（HTTP \(r.status)）" : "网络不可用或请求取消"
    }
    static func testConnection() async -> String {
        let s = WesternCoverSettings.shared.snapshot()
        guard let t = s.token, !t.isEmpty else { return "无 Token（未请求）" }
        let r = await request(URL(string: "https://api.theporndb.net/scenes?per_page=1")!, token: t, deadline: ProcessInfo.processInfo.systemUptime + 5)
        guard r.status == 200, let j = try? JSONSerialization.jsonObject(with: r.data) as? [String: Any], j["data"] is [[String: Any]] else { return "TPDB：" + failure(r) }
        return "TPDB 连接成功（已请求 HTTP 200）" + (s.enabled ? "" : "；封面开关尚未启用")
    }
    private static func tpdb(_ i: WesternCoverPolicy.Identity, settings s: WesternCoverSettings.Snapshot, deadline: TimeInterval) async -> Discovery {
        guard let t = s.token, !t.isEmpty else { return Discovery(images: [], diagnostic: "TPDB：无 Token（未请求）") }
        var c = URLComponents(string: "https://api.theporndb.net/scenes")!
        if let id = i.tpdbID { c.path += "/" + id }
        else if let url = i.officialURL { c.queryItems = [URLQueryItem(name: "url", value: url), URLQueryItem(name: "per_page", value: "20")] }
        else { c.queryItems = [URLQueryItem(name: "title", value: i.title), URLQueryItem(name: "site", value: i.site.name), URLQueryItem(name: "date", value: i.date), URLQueryItem(name: "per_page", value: "20")] }
        guard let url = c.url else { return Discovery(images: [], diagnostic: "TPDB：身份不足（未请求）") }
        let r = await request(url, token: t, deadline: deadline)
        guard r.status == 200 else { return Discovery(images: [], diagnostic: "TPDB：" + failure(r)) }
        guard let j = try? JSONSerialization.jsonObject(with: r.data) as? [String: Any] else { return Discovery(images: [], diagnostic: "TPDB：响应格式不可用（已请求）") }
        let record: [String: Any]?
        if i.tpdbID != nil { record = j["data"] as? [String: Any] }
        else {
            let meta = j["meta"] as? [String: Any]
            // Incomplete pages cannot establish uniqueness.
            guard (meta?["last_page"] as? Int ?? 1) <= 1 else { return Discovery(images: [], diagnostic: "TPDB：候选过多，拒绝猜测（已请求）") }
            record = WesternCoverPolicy.uniqueRecord(j["data"] as? [[String: Any]] ?? [], identity: i)
        }
        guard let record, WesternCoverPolicy.recordMatches(record, identity: i) else { return Discovery(images: [], diagnostic: "TPDB：未匹配或候选冲突（已请求）") }
        let images = WesternCoverPolicy.tpdbImages(record)
        return Discovery(images: images, diagnostic: images.isEmpty ? "TPDB：同片无可用原图（已请求）" : "TPDB：同片原图已发现（已请求，按实解像素比较）")
    }
    private static func data18(_ i: WesternCoverPolicy.Identity, deadline: TimeInterval) async -> Discovery {
        guard !i.title.isEmpty, i.minutes != nil else { return Discovery(images: [], diagnostic: "Data18：原始标题/时长不足（未请求）") }
        var c = URLComponents(string: "https://www.data18.com/sys/live.php")!
        c.queryItems = ["index":"", "key":i.title, "key2":i.title, "keyfull":i.title, "t":"0", "b":"0", "page":"1", "back":"0"].sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        let r = await request(c.url!, deadline: deadline)
        guard r.status == 200 else { return Discovery(images: [], diagnostic: "Data18：" + failure(r)) }
        guard let html = String(data: r.data, encoding: .utf8) else { return Discovery(images: [], diagnostic: "Data18：响应不可用（已请求）") }
        guard !WesternCoverPolicy.restricted(html) else { return Discovery(images: [], diagnostic: "Data18：年龄确认/验证或访问受限（已请求）") }
        let links = WesternCoverPolicy.dataLinks(html, title: i.title)
        guard links.count == 1, let url = URL(string: links[0]) else { return Discovery(images: [], diagnostic: "Data18：未匹配或多场景冲突（已请求）") }
        let page = await request(url, deadline: deadline)
        guard page.status == 200, let html = String(data: page.data, encoding: .utf8) else { return Discovery(images: [], diagnostic: "Data18：" + failure(page)) }
        guard !WesternCoverPolicy.restricted(html) else { return Discovery(images: [], diagnostic: "Data18：年龄确认/验证或访问受限（已请求）") }
        guard let match = WesternCoverPolicy.dataMatch(html, identity: i) else { return Discovery(images: [], diagnostic: "Data18：场景身份冲突或无真实封面（已请求）") }
        var images = match.images
        if let raw = match.gallery, let u = URL(string: raw) {
            let gallery = await request(u, deadline: deadline)
            if let text = String(data: gallery.data, encoding: .utf8), !WesternCoverPolicy.restricted(text), let image = WesternCoverPolicy.primaryImage(text) { images.append(image) }
        }
        return Discovery(images: images, diagnostic: "Data18：同片原图已发现（已请求，按实解像素比较）")
    }
}
