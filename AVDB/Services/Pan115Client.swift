//
//  Pan115Client.swift
//  AVDB
//
//  115 网盘离线下载：Cookie + 目录 CID，磁力/ed2k 一键推送。
//  接口对齐参考脚本：sign = /?ct=offline&ac=space，add = /web/lixian/?ct=lixian&ac=add_task_url
//

import Foundation
import Combine

/// 115 离线推送结果
public enum Pan115PushResult: Equatable {
    case success
    case exists
    case failed(String)

    public var message: String {
        switch self {
        case .success: return "已推送到 115"
        case .exists: return "115 任务已存在"
        case .failed(let msg): return msg
        }
    }
}

/// 115 Cookie / 目录 CID 本地配置
@MainActor
public final class Pan115Settings: ObservableObject {
    public static let shared = Pan115Settings()

    @Published public var cookie: String {
        didSet { UserDefaults.standard.set(Self.normalizeCookie(cookie), forKey: Keys.cookie) }
    }
    @Published public var folderCID: String {
        didSet { UserDefaults.standard.set(folderCID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.folderCID) }
    }

    private enum Keys {
        static let cookie = "avdb.115.cookie"
        static let folderCID = "avdb.115.folderCID"
    }

    private init() {
        cookie = UserDefaults.standard.string(forKey: Keys.cookie) ?? ""
        folderCID = UserDefaults.standard.string(forKey: Keys.folderCID) ?? ""
    }

    public var isConfigured: Bool {
        let c = Self.normalizeCookie(cookie)
        return c.contains("UID=") && c.contains("CID=") && c.contains("SEID=") && !folderCID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var missingHint: String {
        let c = Self.normalizeCookie(cookie)
        var miss: [String] = []
        if !c.contains("UID=") { miss.append("UID") }
        if !c.contains("CID=") { miss.append("Cookie 里的 CID") }
        if !c.contains("SEID=") { miss.append("SEID") }
        if folderCID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { miss.append("离线目录 CID") }
        if miss.isEmpty { return "" }
        return "请先在「我的 → 115 离线」填写：" + miss.joined(separator: "、")
    }

    public static func normalizeCookie(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s*;\\s*", with: "; ", options: .regularExpression)
            .replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func extractUID(from cookie: String) -> String? {
        let c = normalizeCookie(cookie)
        guard let r = try? NSRegularExpression(pattern: "(?:^|;\\s*)UID=(\\d+)", options: .caseInsensitive),
              let m = r.firstMatch(in: c, range: NSRange(c.startIndex..., in: c)),
              let range = Range(m.range(at: 1), in: c) else { return nil }
        return String(c[range])
    }
}

/// 115 离线任务客户端
public final class Pan115Client: @unchecked Sendable {
    public static let shared = Pan115Client()

    private let session: URLSession
    private let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 40
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        session = URLSession(configuration: config)
    }

    /// 推送一条磁力 / ed2k / http 链接到 115 离线
    public func addOfflineTask(url magnet: String, cookie: String, folderCID: String) async throws -> Pan115PushResult {
        let cookie = Pan115Settings.normalizeCookie(cookie)
        let folder = folderCID.trimmingCharacters(in: .whitespacesAndNewlines)
        let link = magnet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !link.isEmpty else { throw Pan115Error.emptyLink }
        guard cookie.contains("UID="), cookie.contains("CID="), cookie.contains("SEID=") else {
            throw Pan115Error.cookieInvalid
        }
        guard !folder.isEmpty else { throw Pan115Error.missingFolder }

        let uid = Pan115Settings.extractUID(from: cookie) ?? ""
        var sign = ""
        var time = "\(Int(Date().timeIntervalSince1970 * 1000))"
        if let s = try? await fetchSign(cookie: cookie) {
            sign = s.sign
            time = s.time
        }

        var parts: [String] = [
            "url=\(link.formEncoded)",
            "wp_path_id=\(folder.formEncoded)",
        ]
        if !uid.isEmpty { parts.append("uid=\(uid.formEncoded)") }
        if !sign.isEmpty {
            parts.append("sign=\(sign.formEncoded)")
            parts.append("time=\(time.formEncoded)")
        }
        let body = parts.joined(separator: "&")

        let endpoint = URL(string: "https://115.com/web/lixian/?ct=lixian&ac=add_task_url")!
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.httpBody = body.data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        appendCommonHeaders(&req, cookie: cookie)

        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw Pan115Error.http(http.statusCode)
        }
        return parseResult(data)
    }

    private func fetchSign(cookie: String) async throws -> (sign: String, time: String) {
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let url = URL(string: "https://115.com/?ct=offline&ac=space&_=\(ts)")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        appendCommonHeaders(&req, cookie: cookie)
        let (data, _) = try await session.data(for: req)
        guard let text = String(data: data, encoding: .utf8), !text.lowercased().contains("<html") else {
            throw Pan115Error.cookieInvalid
        }
        struct SignResp: Decodable {
            let sign: String?
            let time: FlexibleIntOrString?
        }
        let decoded = try JSONDecoder().decode(SignResp.self, from: data)
        guard let sign = decoded.sign, !sign.isEmpty else {
            throw Pan115Error.signFailed
        }
        return (sign, decoded.time?.stringValue ?? "\(ts)")
    }

    private func parseResult(_ data: Data) -> Pan115PushResult {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return .failed("接口无返回")
        }
        if text.lowercased().contains("<html") || text.contains("登录") {
            return .failed("Cookie 无效或已过期")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failed("接口返回不是 JSON")
        }
        let state = obj["state"]
        let ok = (state as? Bool) == true || (state as? Int) == 1 || (state as? String) == "1"
        if ok { return .success }
        let msg = (obj["error_msg"] as? String)
            ?? (obj["error"] as? String)
            ?? (obj["msg"] as? String)
            ?? ""
        let errcode = (obj["errcode"] as? Int) ?? (obj["errno"] as? Int) ?? 0
        if errcode == 10008 || msg.contains("已存在") || msg.contains("重复") {
            return .exists
        }
        return .failed(msg.isEmpty ? "添加失败" : msg)
    }

    private func appendCommonHeaders(_ req: inout URLRequest, cookie: String) {
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue("https://115.com", forHTTPHeaderField: "Origin")
        req.setValue("https://115.com/", forHTTPHeaderField: "Referer")
        req.setValue(cookie, forHTTPHeaderField: "Cookie")
    }
}

public enum Pan115Error: Error, LocalizedError {
    case emptyLink
    case cookieInvalid
    case missingFolder
    case signFailed
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .emptyLink: return "磁力链接为空"
        case .cookieInvalid: return "115 Cookie 无效或已过期，请重新填写 UID/CID/SEID"
        case .missingFolder: return "请先填写 115 离线目录 CID"
        case .signFailed: return "获取 115 签名失败"
        case .http(let code): return "115 接口 HTTP \(code)"
        }
    }
}

private enum FlexibleIntOrString: Decodable {
    case int(Int)
    case string(String)
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        self = .string("")
    }
    var stringValue: String {
        switch self {
        case .int(let i): return "\(i)"
        case .string(let s): return s
        }
    }
}

private extension String {
    var formEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
