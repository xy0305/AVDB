import Foundation

public struct ExternalLink: Decodable, Identifiable, Hashable {
    public let id: Int
    public let title: String?
    public let downloadURL: String
    public let sizeMB: Double?
    public let seeders: Int?
    public let chinese: Bool?
    public let uncensored: Bool?
    public let uhd: Bool?

    enum CodingKeys: String, CodingKey {
        case id, title
        case downloadURL = "download_url"
        case sizeMB = "size_mb"
        case seeders, chinese
        case uncensored = "uc"
        case uhd
    }

    var isED2K: Bool { downloadURL.lowercased().hasPrefix("ed2k:") }
    var isMagnet: Bool { downloadURL.lowercased().hasPrefix("magnet:") }
}

final class ExternalLibraryClient {
    @MainActor static let shared = ExternalLibraryClient()
    private var session: URLSession?
    private let makeConfiguration: () -> URLSessionConfiguration
    init(configuration: @escaping () -> URLSessionConfiguration = { .ephemeral }) {
        makeConfiguration = configuration
    }
    @MainActor func cancelRequests() {
        session?.invalidateAndCancel()
        session = nil
    }
    @MainActor private func transport() -> URLSession {
        if let session { return session }
        let config = makeConfiguration()
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        let created = URLSession(configuration: config, delegate: ExternalRedirectBlocker(), delegateQueue: nil)
        session = created
        return created
    }
    // Compatibility for older callers: [] plus lastError distinguishes failure from success.
    // Shipping detail uses the throwing fetchLinks API directly.
    @MainActor private(set) var lastError: String?
    @MainActor func links(for number: String, settings configured: ExternalLibrarySettings? = nil) async -> [ExternalLink] {
        let settings = configured ?? .shared
        let generation = settings.revision
        do {
            let result = try await fetchLinks(for: number, settings: settings)
            guard generation == settings.revision else { return [] }
            lastError = nil
            return result
        } catch is CancellationError {
            return []
        } catch {
            guard generation == settings.revision else { return [] }
            lastError = error.localizedDescription
            return []
        }
    }
    @MainActor func fetchRankingData(kind: String, settings configured: ExternalLibrarySettings? = nil) async throws -> Data {
        let settings = configured ?? .shared
        guard settings.enabled, let token = try settings.token(), !token.isEmpty else {
            throw ExternalLibraryError.rankingNotConfigured
        }
        let generation = settings.revision
        let base = try ExternalLibrarySettings.normalizedURL(settings.baseURL)
        var parts = URLComponents(string: base + "/api/v1/javlibrary/rankings")
        parts?.queryItems = [URLQueryItem(name: "kind", value: kind)]
        guard let url = parts?.url else { throw ExternalLibraryError.invalidURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue(token, forHTTPHeaderField: "X-API-Key")
        do {
            let (data, response) = try await transport().data(for: request)
            try Task.checkCancellation()
            guard generation == settings.revision else { throw CancellationError() }
            guard let http = response as? HTTPURLResponse else { throw ExternalLibraryError.transport }
            guard http.statusCode == 200 else { throw ExternalLibraryError.http(http.statusCode) }
            return data
        } catch {
            if Task.isCancelled || generation != settings.revision || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            if let safe = error as? ExternalLibraryError { throw safe }
            throw ExternalLibraryError.transport
        }
    }
    @MainActor func fetchLinks(for number: String, settings configured: ExternalLibrarySettings? = nil) async throws -> [ExternalLink] {
        let settings = configured ?? .shared
        let keyword = number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard settings.enabled, !keyword.isEmpty else { return [] }
        guard let token = try settings.token(), !token.isEmpty else { return [] }
        let generation = settings.revision
        let base = try ExternalLibrarySettings.normalizedURL(settings.baseURL)
        var parts = URLComponents(string: base + "/api/v1/articles/torrents")
        parts?.queryItems = [URLQueryItem(name: "keyword", value: keyword)]
        guard let url = parts?.url else { throw ExternalLibraryError.invalidURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue(token, forHTTPHeaderField: "X-API-Key")
        do {
            let (data, response) = try await transport().data(for: request)
            try Task.checkCancellation()
            guard generation == settings.revision else { throw CancellationError() }
            guard let http = response as? HTTPURLResponse else { throw ExternalLibraryError.transport }
            guard http.statusCode == 200 else { throw ExternalLibraryError.http(http.statusCode) }
            guard let envelope = try? JSONDecoder().decode(ExternalLinkEnvelope.self, from: data),
                  let links = envelope.data else { throw ExternalLibraryError.schema }
            return links
        } catch {
            if Task.isCancelled || generation != settings.revision || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            if let error = error as? ExternalLibraryError { throw error }
            // Do not expose localized transport errors: they may contain URLs or server-provided content.
            throw ExternalLibraryError.transport
        }
    }
}

private struct ExternalLinkEnvelope: Decodable {
    let data: [ExternalLink]?
}

import Foundation
import Combine
import Security

protocol ExternalTokenStore {
    func read() throws -> String?
    func write(_ token: String) throws
    func clear() throws
}

struct ExternalKeychainStore: ExternalTokenStore {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "app.avdb.external-library",
         kSecAttrAccount as String: "api-token",
         kSecAttrSynchronizable as String: false]
    }
    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw ExternalLibraryError.keychain(status) }
    }
    func read() throws -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let bytes = item as? Data, let value = String(data: bytes, encoding: .utf8) else {
            throw ExternalLibraryError.invalidStoredToken
        }
        return value
    }
    func write(_ token: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            try check(SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil))
        } else { try check(status) }
    }
    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
}

enum ExternalLibraryError: LocalizedError {
    case keychain(OSStatus), invalidStoredToken, invalidURL, invalidToken, endpointNeedsToken
    case rankingNotConfigured
    case http(Int), transport, schema
    var errorDescription: String? {
        switch self {
        case .keychain(let status): return "钥匙串操作失败（\(status)），请解锁设备后重试。"
        case .invalidStoredToken: return "钥匙串令牌无法读取，请重新保存或清除。"
        case .invalidURL: return "地址只能是 http/https 根域名或 IP 加端口，不能包含账号、路径、查询或片段。"
        case .invalidToken: return "令牌不能包含空格、换行或非 ASCII 字符。"
        case .endpointNeedsToken: return "更换服务器时请重新输入令牌，避免将原令牌发送给其他服务器。"
        case .http(let code): return "外部数据库请求失败（HTTP \(code)）；重定向不被允许。"
        case .transport: return "外部数据库连接失败，请检查网络及服务器地址。"
        case .rankingNotConfigured: return "请在外部数据库设置中启用服务并保存现有 API 令牌。"
        case .schema: return "外部数据库响应格式无效。"
        }
    }
}

@MainActor
final class ExternalLibrarySettings: ObservableObject {
    static let shared = ExternalLibrarySettings()
    static let defaultBaseURL = "http://163.47.40.207:8000"
    @Published private(set) var baseURL: String
    @Published private(set) var enabled: Bool
    @Published private(set) var hasToken = false
    @Published private(set) var storageError: String?
    @Published private(set) var revision: UInt = 0
    private let store: ExternalTokenStore
    private let defaults: UserDefaults
    private let prefix = "avdb.externalLibrary."

    init(store: ExternalTokenStore = ExternalKeychainStore(), defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        baseURL = defaults.string(forKey: "avdb.externalLibrary.baseURL") ?? Self.defaultBaseURL
        enabled = defaults.bool(forKey: "avdb.externalLibrary.enabled")
        refreshStatus()
    }
    static func normalizedURL(_ raw: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let p = URLComponents(string: value),
              let scheme = p.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = p.host, !host.isEmpty,
              p.user == nil, p.password == nil, p.query == nil, p.fragment == nil,
              p.path.isEmpty || p.path == "/", p.port.map({ (1...65535).contains($0) }) ?? true,
              let url = p.url, url.host != nil else { throw ExternalLibraryError.invalidURL }
        var normalized = p
        normalized.scheme = scheme
        normalized.path = ""
        guard let result = normalized.url?.absoluteString else { throw ExternalLibraryError.invalidURL }
        return result
    }
    func refreshStatus() {
        do { hasToken = !(try store.read() ?? "").isEmpty; storageError = nil }
        catch { hasToken = false; storageError = error.localizedDescription }
    }
    func token() throws -> String? { try store.read() }
    func save(baseURL raw: String, enabled: Bool, replacementToken: String) throws {
        let url = try Self.normalizedURL(raw)
        if !replacementToken.isEmpty {
            guard replacementToken.utf8.allSatisfy({ (33...126).contains($0) }) else {
                throw ExternalLibraryError.invalidToken
            }
        }
        if url != baseURL && replacementToken.isEmpty {
            if try store.read() != nil { throw ExternalLibraryError.endpointNeedsToken }
        }
        // Only commit preferences after a successful Keychain write. Empty input retains the stored value.
        if !replacementToken.isEmpty { try store.write(replacementToken) }
        self.baseURL = url
        self.enabled = enabled
        defaults.set(url, forKey: prefix + "baseURL")
        defaults.set(enabled, forKey: prefix + "enabled")
        changed()
    }
    func clearToken() throws {
        try store.clear()
        changed()
    }
    private func changed() {
        revision &+= 1
        ExternalLibraryClient.shared.cancelRequests()
        refreshStatus()
    }
}

final class ExternalRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Reject ALL redirects, including same-origin ones: credentials never leave the configured endpoint.
        completionHandler(nil)
    }
}
