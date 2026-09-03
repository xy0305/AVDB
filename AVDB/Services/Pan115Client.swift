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
public final class Pan115Settings: ObservableObject, @unchecked Sendable {
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

    // MARK: - 离线任务 / 原画播放

    public struct OfflineTask {
        public let name: String
        public let status: Int
        public let percent: Double
        public let infoHash: String
        public let fileID: String
        public let dirID: String
        public let url: String

        public var isDone: Bool { status == 2 }
        public var isFailed: Bool { status == -1 }
        public var isRunning: Bool { status == 0 || status == 1 }
    }

    public struct FileItem {
        public let name: String
        public let pickCode: String
        public let fileID: String
        public let cid: String
        public let isDir: Bool
        public let size: Int64

        public var isVideo: Bool {
            let n = name.lowercased()
            return [".mp4", ".mkv", ".avi", ".mov", ".wmv", ".flv", ".ts", ".m2ts", ".webm", ".m4v", ".iso"].contains { n.hasSuffix($0) }
        }
    }

    public struct PlayStream {
        public let name: String
        public let url: String
        public let bandwidth: Int
    }

    /// 轮询离线任务直到完成（默认 90 秒）
    public func waitOfflineReady(
        keyword: String,
        cookie: String,
        timeout: TimeInterval = 90
    ) async throws -> OfflineTask {
        let cookie = Pan115Settings.normalizeCookie(cookie)
        let needle = keyword.lowercased()
        let start = Date()
        var last: OfflineTask?
        while Date().timeIntervalSince(start) < timeout {
            let tasks = (try? await listOfflineTasks(cookie: cookie)) ?? []
            if let hit = tasks.first(where: { task in
                task.name.lowercased().contains(needle)
                    || task.url.lowercased().contains(needle)
                    || needle.contains(task.infoHash.lowercased())
            }) {
                last = hit
                if hit.isDone { return hit }
                if hit.isFailed { throw Pan115Error.taskFailed(hit.name) }
            }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        if let last, last.isDone { return last }
        throw Pan115Error.timeout
    }

    public func listOfflineTasks(cookie: String, page: Int = 1) async throws -> [OfflineTask] {
        let url = URL(string: "https://115.com/web/lixian/?ct=lixian&ac=task_lists&page=\(page)")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        appendCommonHeaders(&req, cookie: cookie)
        let obj = try await json(for: req)
        let raw = (obj["tasks"] as? [[String: Any]])
            ?? ((obj["data"] as? [String: Any])?["tasks"] as? [[String: Any]])
            ?? []
        return raw.map { item in
            OfflineTask(
                name: (item["name"] as? String) ?? "",
                status: intValue(item["status"]),
                percent: doubleValue(item["percentDone"] ?? item["percent"]),
                infoHash: (item["info_hash"] as? String) ?? (item["hash"] as? String) ?? "",
                fileID: stringValue(item["file_id"] ?? item["delete_file_id"]),
                dirID: stringValue(item["wp_path_id"] ?? item["file_id"]),
                url: (item["url"] as? String) ?? ""
            )
        }
    }

    public func listFiles(cid: String, cookie: String, limit: Int = 115) async throws -> [FileItem] {
        let q = "aid=1&cid=\(cid.formEncoded)&o=user_ptime&asc=0&offset=0&show_dir=1&limit=\(limit)&natsort=1&record_open_time=1&format=json"
        let urls = [
            "https://webapi.115.com/files?\(q)",
            "https://aps.115.com/natsort/files.php?\(q)",
            "https://proapi.115.com/android/2.0/ufile/files?\(q)",
        ]
        var lastError: Error = Pan115Error.fileNotFound
        for u in urls {
            guard let url = URL(string: u) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            appendCommonHeaders(&req, cookie: cookie)
            do {
                let obj = try await json(for: req)
                let files = extractFileList(obj)
                let ok = boolState(obj["state"]) || !files.isEmpty
                if ok { return files }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// 在离线目录中找最大的视频（必要时进一层文件夹）
    public func findLatestVideo(in cid: String, cookie: String, keyword: String? = nil) async throws -> FileItem {
        let files = try await listFiles(cid: cid, cookie: cookie)
        if let video = pickVideo(from: files, keyword: keyword) { return video }
        let dirs = files.filter(\.isDir)
        for dir in dirs.prefix(8) {
            let nested = try await listFiles(cid: dir.cid.isEmpty ? dir.fileID : dir.cid, cookie: cookie)
            if let video = pickVideo(from: nested, keyword: keyword) { return video }
        }
        throw Pan115Error.fileNotFound
    }

    /// 原画：优先 m3u8 master 最高码率，失败再走 video 直链
    public func originalPlayURL(pickCode: String, cookie: String, filename: String = "") async throws -> URL {
        let streams = try await streamsForVideo(pickCode: pickCode, cookie: cookie, filename: filename)
        guard let best = streams.first, let url = URL(string: best.url) else {
            throw Pan115Error.playURLNotFound
        }
        return url
    }

    public func streamsForVideo(pickCode: String, cookie: String, filename: String) async throws -> [PlayStream] {
        let m3u8URL = URL(string: "https://115.com/api/video/m3u8/\(pickCode.formEncoded).m3u8")!
        var req = URLRequest(url: m3u8URL)
        req.httpMethod = "GET"
        appendCommonHeaders(&req, cookie: cookie)
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        let (data, _) = try await session.data(for: req)
        if let text = String(data: data, encoding: .utf8), text.contains("#EXTM3U") {
            let parsed = parseMaster(text)
            if !parsed.isEmpty { return parsed }
            if !text.contains("#EXT-X-STREAM-INF") {
                return [PlayStream(name: "原画", url: m3u8URL.absoluteString, bandwidth: 0)]
            }
        }
        let candidates = [
            "https://115vod.com/webapi/files/video?pickcode=\(pickCode.formEncoded)&local=1",
            "https://webapi.115.com/files/video?pickcode=\(pickCode.formEncoded)&local=1",
        ]
        for u in candidates {
            guard let url = URL(string: u) else { continue }
            var r = URLRequest(url: url)
            r.httpMethod = "GET"
            appendCommonHeaders(&r, cookie: cookie)
            if let obj = try? await json(for: r) {
                let data = obj["data"] as? [String: Any] ?? [:]
                let direct = stringValue(obj["download_url"] ?? obj["video_url"] ?? obj["url"]
                    ?? data["download_url"] ?? data["video_url"] ?? data["url"])
                if direct.hasPrefix("http"), URL(string: direct) != nil {
                    return [PlayStream(name: "原文件", url: direct, bandwidth: 0)]
                }
            }
        }
        throw Pan115Error.playURLNotFound
    }

    /// 推送磁力并等到可播，返回原画 URL
    public func pushAndPlay(magnet: String, cookie: String, folderCID: String, keyword: String) async throws -> URL {
        _ = try await addOfflineTask(url: magnet, cookie: cookie, folderCID: folderCID)
        let task = try await waitOfflineReady(keyword: keyword, cookie: cookie)
        let cid = task.dirID.isEmpty ? folderCID : task.dirID
        let file = try await findLatestVideo(in: cid, cookie: cookie, keyword: keyword)
        return try await originalPlayURL(pickCode: file.pickCode, cookie: cookie, filename: file.name)
    }

    private func pickVideo(from files: [FileItem], keyword: String?) -> FileItem? {
        var videos = files.filter { !$0.isDir && $0.isVideo && !$0.pickCode.isEmpty }
        if videos.isEmpty {
            videos = files.filter { !$0.isDir && !$0.pickCode.isEmpty && $0.size > 10_000_000 }
        }
        if let keyword, !keyword.isEmpty {
            let n = keyword.lowercased()
            if let hit = videos.first(where: { $0.name.lowercased().contains(n) }) { return hit }
        }
        return videos.max(by: { $0.size < $1.size })
    }

    private func extractFileList(_ obj: [String: Any]) -> [FileItem] {
        var raw: [[String: Any]] = []
        if let data = obj["data"] as? [[String: Any]] { raw = data }
        else if let list = obj["list"] as? [[String: Any]] { raw = list }
        else if let data = obj["data"] as? [String: Any] {
            if let list = data["list"] as? [[String: Any]] { raw = list }
            else {
                raw = data.values.compactMap { $0 as? [String: Any] }
            }
        }
        return raw.map { item in
            let name = (item["n"] as? String) ?? (item["name"] as? String) ?? (item["file_name"] as? String) ?? ""
            let pc = (item["pc"] as? String) ?? (item["pick_code"] as? String) ?? (item["pickcode"] as? String) ?? ""
            let fid = stringValue(item["fid"] ?? item["file_id"] ?? item["id"])
            let cid = stringValue(item["cid"])
            let isDir = (item["fid"] == nil && item["pc"] == nil && item["sha"] == nil && !cid.isEmpty)
                || intValue(item["fc"]) == 0
            return FileItem(name: name, pickCode: pc, fileID: fid, cid: cid, isDir: isDir, size: Int64(doubleValue(item["s"] ?? item["size"])))
        }
    }

    private func parseMaster(_ text: String) -> [PlayStream] {
        let lines = text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
        var streams: [PlayStream] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                let bw = Int(line.split(separator: "BANDWIDTH=").last?.split(separator: ",").first ?? "0") ?? 0
                if i + 1 < lines.count {
                    var u = lines[i + 1]
                    if !u.hasPrefix("http"), let abs = URL(string: u, relativeTo: URL(string: "https://115.com/")) {
                        u = abs.absoluteString
                    }
                    let name = bw > 0 ? "\(bw / 1000)k" : "原画"
                    streams.append(PlayStream(name: "115 \(name)", url: u, bandwidth: bw))
                }
            }
            i += 1
        }
        return streams.sorted { $0.bandwidth > $1.bandwidth }
    }

    private func json(for req: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw Pan115Error.http(http.statusCode)
        }
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            throw Pan115Error.playURLNotFound
        }
        if text.lowercased().contains("<html") || text.contains("登录") {
            throw Pan115Error.cookieInvalid
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Pan115Error.playURLNotFound
        }
        return obj
    }

    private func boolState(_ v: Any?) -> Bool {
        if let b = v as? Bool { return b }
        if let i = v as? Int { return i == 1 }
        if let s = v as? String { return s == "1" || s.lowercased() == "true" }
        return false
    }
    private func intValue(_ v: Any?) -> Int {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let s = v as? String { return Int(s) ?? 0 }
        return 0
    }
    private func doubleValue(_ v: Any?) -> Double {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s) ?? 0 }
        return 0
    }
    private func stringValue(_ v: Any?) -> String {
        if let s = v as? String { return s }
        if let i = v as? Int { return String(i) }
        if let d = v as? Double { return String(Int(d)) }
        return ""
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
    case timeout
    case taskFailed(String)
    case fileNotFound
    case playURLNotFound

    public var errorDescription: String? {
        switch self {
        case .emptyLink: return "磁力链接为空"
        case .cookieInvalid: return "115 Cookie 无效或已过期，请重新填写 UID/CID/SEID"
        case .missingFolder: return "请先填写 115 离线目录 CID"
        case .signFailed: return "获取 115 签名失败"
        case .http(let code): return "115 接口 HTTP \(code)"
        case .timeout: return "等待 115 离线完成超时"
        case .taskFailed(let msg): return "115 离线失败：\(msg)"
        case .fileNotFound: return "离线目录里没找到视频文件"
        case .playURLNotFound: return "无法获取 115 原画播放地址"
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
