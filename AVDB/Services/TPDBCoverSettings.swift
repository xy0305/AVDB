import Foundation
import Security
import Combine
import SwiftUI

extension Notification.Name { static let tpdbCoverChanged = Notification.Name("avdb.tpdbCoverChanged") }

struct TPDBTokenStore: ExternalTokenStore {
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
final class TPDBCoverSettings: ObservableObject, @unchecked Sendable {
    static let shared = TPDBCoverSettings()
    struct Snapshot: Sendable { let enabled: Bool; let namespace: UUID; let token: String? }
    let objectWillChange = ObservableObjectPublisher()
    private let lock = NSLock()
    private let store: ExternalTokenStore
    private let defaults: UserDefaults
    private var epoch = UUID()
    private var active: Bool
    private var lastDiagnostic = "尚未请求"
    var diagnostic: String { lock.lock(); defer { lock.unlock() }; return lastDiagnostic }
    func record(_ message: String, generation: UUID) {
        lock.lock(); guard epoch == generation else { lock.unlock(); return }; lastDiagnostic = message; lock.unlock()
        DispatchQueue.main.async { self.objectWillChange.send() }
    }
    init(store: ExternalTokenStore = TPDBTokenStore(), defaults: UserDefaults = .standard) {
        self.store = store; self.defaults = defaults
        active = defaults.bool(forKey: "avdb.tpdbCovers.enabled") // Opt-in; sends work metadata.
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
            active = enabled; epoch = UUID(); defaults.set(enabled, forKey: "avdb.tpdbCovers.enabled")
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
        lock.lock(); lastDiagnostic = "设置已改变，旧请求与缓存已清除"; lock.unlock()
        TPDBArtworkService.clear()
        objectWillChange.send()
        NotificationCenter.default.post(name: .tpdbCoverChanged, object: nil)
    }
}

struct TPDBCoverSettingsView: View {
    @ObservedObject var settings: TPDBCoverSettings = .shared
    @State private var enabled = false
    @State private var token = ""
    @State private var status = ""
    var body: some View {
        Form {
            Section("欧美封面 / ThePornDB") {
                Toggle("启用 TPDB 欧美封面", isOn: $enabled).accessibilityIdentifier("tpdb-enabled")
                SecureField("TPDB Token（不回显）", text: $token)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("tpdb-token")
                Text(settings.hasToken ? "TPDB 已配置（不显示内容）" : "TPDB 未配置；保留 JavDB 原封面")
                    .accessibilityIdentifier("tpdb-configuration")
                Button("保存") {
                    do { try settings.save(enabled: enabled, replacement: token); token = ""; status = "设置已保存" }
                    catch { token = ""; status = "保存失败，请检查令牌格式或解锁设备后重试" }
                }.accessibilityIdentifier("tpdb-save")
                Button("清除 Token", role: .destructive) {
                    do { try settings.clear(); token = ""; status = "令牌及旧封面缓存已清除" }
                    catch { token = ""; status = "清除失败，请解锁设备后重试" }
                }.accessibilityIdentifier("tpdb-clear")
                Text(settings.diagnostic).font(.caption).foregroundStyle(.secondary)
                if !status.isEmpty { Text(status).accessibilityIdentifier("tpdb-status") }
            }
            Section("隐私与覆盖") {
                Text("默认关闭。启用后，仅在欧美详情页按需发送作品标题、品牌、发行日期和已有原片商网页地址。不会发送视频播放地址、115 Cookie 或 pickcode。列表不搜索第三方。")
                Text("仅尝试 Blacked Raw / Blacked / Vixen / Tushy 单场景；不把电影正封与场景混用。身份不完整、重名、日期冲突、年龄确认、验证码或访问受限均保留 JavDB。")
                Text("Token 仅存本机钥匙串，仅发送到 https://api.theporndb.net；不会发送图片 CDN，也不跟随重定向。安装后请自行填写个人 Token，App 不内置测试凭据。")
                Text("仅使用已验证作品的 image / background.full 横图，按实际原生像素择优；不保证大于 JavDB 或覆盖整个欧美库。图片独立无鉴权请求，横图不裁成竖版。")
            }
        }.navigationTitle("欧美封面 / ThePornDB")
            .onAppear { enabled = settings.enabled }
            .onDisappear { token = "" }
    }
}

