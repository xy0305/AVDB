import Foundation
import Combine
import SwiftUI
import Security
import CryptoKit

// Build 351: on-device translation of movie plots and titles through the
// user's own xAI API key. The key is entered in 设置 → AI 翻译（xAI）, is
// stored only in the device keychain, and requests go from this device
// straight to api.x.ai — no other server, account token or request
// signature is involved, and nothing here touches the metadata APIs.
// Without a key the feature is invisible: the detail page simply never
// shows the translate button.
//
// The prompt assembly and the cache design follow the enrichment
// pipeline's translation spec (Amane): instruction + per-field note +
// a fixed "output only the translation" constraint; cache key =
// sha256(source text) + target language + field + sha256(system prompt),
// so editing the prompt invalidates old translations automatically and
// the same plot is never translated twice.

/// Device-only API key. Never logged, bundled, or echoed back into the field.
struct XAITranslationKeyStore: ExternalTokenStore {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "app.avdb.xai-translation",
         kSecAttrAccount as String: "api-key",
         kSecAttrSynchronizable as String: false]
    }
    func read() throws -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
            throw ExternalLibraryError.keychain(status)
        }
        return token
    }
    func write(_ token: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ExternalLibraryError.keychain(status) }
    }
    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ExternalLibraryError.keychain(status) }
    }
}

@MainActor final class XAISettings: ObservableObject {
    static let shared = XAISettings()
    static let defaultModel = "grok-4-1-fast-non-reasoning"
    private let store: ExternalTokenStore
    private let defaults: UserDefaults
    private let modelKey = "avdb.xai.model"
    @Published private(set) var configured = false
    @Published private(set) var model: String
    init(store: ExternalTokenStore = XAITranslationKeyStore(), defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        model = defaults.string(forKey: modelKey) ?? Self.defaultModel
        configured = ((try? store.read()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
    func currentKey() -> String? {
        let value = ((try? store.read()) ?? nil)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
    /// Empty key input keeps the stored key. Only the clear action deletes it.
    func save(replacementKey: String, model rawModel: String) throws {
        let trimmed = replacementKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 4096, trimmed.utf8.allSatisfy({ (33...126).contains($0) }) else { throw ExternalLibraryError.invalidToken }
        if !trimmed.isEmpty { try store.write(trimmed) }
        let newModel = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
        model = newModel.isEmpty ? Self.defaultModel : newModel
        defaults.set(model, forKey: modelKey)
        configured = currentKey() != nil
    }
    func clear() throws {
        try store.clear()
        configured = false
    }
}

struct XAISettingsView: View {
    @ObservedObject private var settings = XAISettings.shared
    @State private var key = ""
    @State private var model = ""
    @State private var status = ""
    var body: some View {
        Form {
            Section("AI 翻译（xAI）") {
                SecureField("xAI API Key（不回显）", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("xai-api-key")
                TextField("模型", text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("xai-model")
                Text(settings.configured ? "已设置（不显示内容）" : "未设置")
                    .accessibilityIdentifier("xai-configuration")
                Button("保存") {
                    do {
                        try settings.save(replacementKey: key, model: model)
                        key = ""
                        model = settings.model
                        status = settings.configured ? "已保存到本机钥匙串" : "未填写 Key，已保留原设置"
                    } catch {
                        key = ""
                        status = "保存失败，请检查 Key 格式或解锁设备后重试"
                    }
                }.accessibilityIdentifier("xai-save")
                Button("清除 Key", role: .destructive) {
                    do { try settings.clear(); key = ""; status = "已清除本机 Key" }
                    catch { key = ""; status = "清除失败，请解锁设备后重试" }
                }.accessibilityIdentifier("xai-clear")
                if !status.isEmpty { Text(status).accessibilityIdentifier("xai-status") }
            }
            Section("说明") {
                Text("Key 只存本机钥匙串，翻译请求由本机直连 https://api.x.ai，不经过任何其他服务器。不写入日志，不进入 IPA。留空保存不会清除已有 Key。")
                Text("未设置 Key 时翻译功能整体停用：详情页不显示「翻译成中文」按钮，也不会发出任何翻译请求。")
            }
        }
        .navigationTitle("AI 翻译（xAI）")
        .onAppear { model = settings.model }
        .onDisappear { key = "" }
    }
}

enum XAITranslationError: LocalizedError {
    case notConfigured, empty, http(Int), schema
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "未设置 xAI API Key"
        case .empty: return "翻译结果为空，请重试"
        case .http(let code): return "翻译失败（HTTP \(code)），请重试"
        case .schema: return "翻译响应格式无效，请重试"
        }
    }
}

/// Content-addressed translation cache in Caches: one JSON object keyed
/// by XAITranslationService.cacheKey. Pure cache — deleting the file
/// only costs re-translation.
final class XAITranslationCache {
    static let shared = XAITranslationCache()
    private let lock = NSLock()
    private var entries: [String: String]
    private static func fileURL() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("XAITranslation351/translations.json")
    }
    private init() {
        if let data = try? Data(contentsOf: Self.fileURL()),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }
    func value(forKey key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return entries[key]
    }
    func store(_ value: String, forKey key: String) {
        lock.lock()
        entries[key] = value
        let snapshot = entries
        lock.unlock()
        let url = Self.fileURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

enum XAITranslationService {
    static let promptVersion = "amane351-v1"
    static let targetLanguage = "简体中文"

    /// Japanese text (contains kana) is what gets translated; text that
    /// is already Chinese (kanji only) or empty is left alone.
    static func needsTranslation(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3040...0x30FF).contains(Int($0.value)) }
    }

    static func systemPrompt(field: String) -> String {
        let note = field == "title"
            ? "翻译应简洁自然, 保留专有名词、番号与人名"
            : "完整通顺地翻译全部内容, 保留番号、人名与片假名术语"
        return "你是专业的影视元数据翻译. 将用户提供的文本翻译为\(targetLanguage). \(note) 只输出译文本身, 不要解释、不要引号、不要附加任何内容."
    }

    static func cacheKey(text: String, field: String) -> String {
        sha256(text) + "|" + targetLanguage + "|" + field + "|" + sha256(systemPrompt(field: field)) + "|" + promptVersion
    }
    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    @MainActor
    static func translate(text: String, field: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw XAITranslationError.empty }
        let key = cacheKey(text: trimmed, field: field)
        if let hit = XAITranslationCache.shared.value(forKey: key) { return hit }
        guard let apiKey = XAISettings.shared.currentKey() else { throw XAITranslationError.notConfigured }
        var request = URLRequest(url: URL(string: "https://api.x.ai/v1/chat/completions")!, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": XAISettings.shared.model,
            "temperature": 0.3,
            "messages": [
                ["role": "system", "content": systemPrompt(field: field)],
                ["role": "user", "content": trimmed]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw XAITranslationError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = payload["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else { throw XAITranslationError.schema }
        var result = content
        if let start = result.range(of: "<think>"), let end = result.range(of: "</think>") {
            result.removeSubrange(start.lowerBound..<end.upperBound)
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw XAITranslationError.empty }
        XAITranslationCache.shared.store(result, forKey: key)
        return result
    }
}
