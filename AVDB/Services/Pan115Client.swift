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
    /// 删除接口专用 session：webapi.115.com/rb/delete 在 iOS 上 HTTP/2 会 SSL EOF，
    /// 用独立 ephemeral session + 强制关闭连接复用，尽量走 HTTP/1.1。
    private let deleteSession: URLSession
    /// 必须与播放器 UA 一致，否则 115 按 UA 绑定的 m3u8 会 403。
    static let safariUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Safari/605.1.15"

    private var userAgent: String { Self.safariUA }

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 40
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        session = URLSession(configuration: config)

        let delConfig = URLSessionConfiguration.ephemeral
        delConfig.timeoutIntervalForRequest = 20
        delConfig.timeoutIntervalForResource = 40
        delConfig.httpShouldSetCookies = false
        delConfig.httpCookieAcceptPolicy = .never
        delConfig.httpShouldUsePipelining = false
        deleteSession = URLSession(configuration: delConfig)
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
            "https://aps.115.com/natsort/files.php?\(q)",
            "https://proapi.115.com/android/2.0/ufile/files?\(q)",
            "https://webapi.115.com/files?\(q)",
        ]
        var lastError: Error = Pan115Error.fileNotFound
        for u in urls {
            guard let url = URL(string: u) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            appendCommonHeaders(&req, cookie: cookie)
            do {
                let obj = try await json(for: req, retries: 1)
                let files = extractFileList(obj)
                let ok = boolState(obj["state"]) || !files.isEmpty
                if ok { return files }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// 获取离线父目录当前的子文件夹 ID，必须在推送磁力之前调用。
    public func folderSnapshot(cid: String, cookie: String) async -> Set<String> {
        guard let files = try? await listFiles(cid: cid, cookie: cookie, limit: 500) else { return [] }
        return Set(files.filter { $0.isDir }
            .map { $0.fileID.isEmpty ? $0.cid : $0.fileID }
            .filter { !$0.isEmpty })
    }

    /// 全盘按番号搜索。
    /// 注意：`webapi.115.com` 在部分网络/客户端下会稳定触发 SSL EOF（UNEXPECTED_EOF_WHILE_READING），
    /// 而 `proapi.115.com` / `aps.115.com` 通常正常。把可用的域名排前面，webapi 降级为后备。
    public func searchFiles(keyword: String, cookie: String, limit: Int = 30) async throws -> [FileItem] {
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let encoded = (kw.isEmpty ? ".mp4" : kw).formEncoded
        let urls = [
            "https://proapi.115.com/android/2.0/ufile/search?search_value=\(encoded)&limit=\(limit)&offset=0&type=4&format=json",
            "https://aps.115.com/natsort/files.php?search_value=\(encoded)&type=4&limit=\(limit)&offset=0&format=json",
            "https://webapi.115.com/files/search?search_value=\(encoded)&limit=\(limit)&offset=0&type=4&format=json",
            "https://webapi.115.com/files/search?search_value=\(encoded)&limit=\(limit)&offset=0&format=json",
        ]
        var lastError: Error = Pan115Error.fileNotFound
        for u in urls {
            guard let url = URL(string: u) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            appendCommonHeaders(&req, cookie: cookie)
            do {
                let obj = try await json(for: req, retries: 1)
                let files = extractFileList(obj)
                if !files.isEmpty { return files }
                if boolState(obj["state"]) { return [] }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// 按番号匹配 115 文件：全盘番号搜索优先命中，目录列举与浅层递归兜底。
    public func findMatchedVideo(
        keyword: String,
        cookie: String,
        folderCID: String? = nil,
        requireMatch: Bool = true
    ) async throws -> FileItem {
        let needle = normalizedKey(keyword)
        guard !needle.isEmpty else { throw Pan115Error.fileNotFound }

        // 1) 全盘番号搜索（多关键词变体，命中立即返回）。
        //    这是唯一可靠且快速的路径：115 的「目录内 search_value」不递归子目录，
        //    而「全盘 .mp4」返回全站几十万条，无法定位具体番号——两者都不可用。
        let variants = searchKeywords(from: keyword)
        var lastSearchError: Error = Pan115Error.fileNotFound
        for kw in variants {
            do {
                let files = try await searchFiles(keyword: kw, cookie: cookie)
                if let hit = pickVideo(from: files, keyword: keyword, requireMatch: true) {
                    return hit
                }
            } catch {
                lastSearchError = error
            }
        }

        // 2) 离线目录内全量列举（limit 拉满），在当前目录层面再匹配一次。
        //    不再递归遍历子目录——深嵌套目录（如 263 条 ED2K 大目录）递归会发
        //    起数千次请求，是「一直搜索」的直接元凶。
        if let cid = folderCID, !cid.isEmpty {
            let files = (try? await listFiles(cid: cid, cookie: cookie, limit: 500)) ?? []
            if let hit = pickVideo(from: files, keyword: keyword, requireMatch: requireMatch) {
                return hit
            }
        }

        // 3) 兜底：离线目录浅层递归（深度 2，带超时），仅覆盖「番号压在下一层子目录」的常见场景。
        if let cid = folderCID, !cid.isEmpty {
            if let hit = try? await findLatestVideo(in: cid, cookie: cookie, keyword: keyword, requireMatch: requireMatch) {
                return hit
            }
        }

        // 兜底：优先抛出番号搜索途中遇到的具体错误（如 SSL EOF / cookie 失效），
        // 避免上层把「网络错误」误判成「一直搜索」而卡住不提示。
        throw lastSearchError
    }

    /// 在目录中递归找与番号匹配的视频（遍历所有子目录，不限层数）。
    public func findLatestVideo(
        in cid: String,
        cookie: String,
        keyword: String? = nil,
        requireMatch: Bool = false
    ) async throws -> FileItem {
        var visited = Set<String>()
        func walk(_ dirID: String, depth: Int) async throws -> FileItem? {
            guard depth < 2, !visited.contains(dirID) else { return nil }
            visited.insert(dirID)
            let files = try await listFiles(cid: dirID, cookie: cookie, limit: 500)
            let videos = files.filter { !$0.isDir && $0.isVideo && !$0.pickCode.isEmpty }
            if let hit = pickVideo(from: videos, keyword: keyword, requireMatch: requireMatch) {
                return hit
            }
            let dirs = files.filter(\.isDir)
            let needle = normalizedKey(keyword)
            let preferred = dirs.filter { dir in
                needle.isEmpty || normalizedKey(dir.name).contains(needle) || needle.contains(normalizedKey(dir.name))
            }
            for dir in (preferred + dirs).uniquedFiles.prefix(40) {
                let childID = dir.cid.isEmpty ? dir.fileID : dir.cid
                if let hit = try await walk(childID, depth: depth + 1) {
                    return hit
                }
            }
            return nil
        }
        if let hit = try await walk(cid, depth: 0) { return hit }
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
        let file = try await findMatchedVideo(keyword: keyword, cookie: cookie, folderCID: cid, requireMatch: true)
        return try await originalPlayURL(pickCode: file.pickCode, cookie: cookie, filename: file.name)
    }

    /// 推送磁力 → 等离线完成 → 删除离线目录内 <115MB 的小文件。
    /// 返回 (离线任务, 删除的小文件数)。
    public func pushAndCleanSmallFiles(
        magnet: String,
        cookie: String,
        folderCID: String,
        keyword: String,
        thresholdBytes: Int64 = 115 * 1024 * 1024
    ) async throws -> (OfflineTask, Int) {
        _ = try await addOfflineTask(url: magnet, cookie: cookie, folderCID: folderCID)
        let task = try await waitOfflineReady(keyword: keyword, cookie: cookie)
        let cid = task.dirID.isEmpty ? folderCID : task.dirID
        let deleted = try await deleteSmallFiles(in: cid, cookie: cookie, thresholdBytes: thresholdBytes)
        return (task, deleted)
    }

    /// 等待离线任务完成（已推送过），然后进入离线产物（新建文件夹）删除 <115MB 的小文件。
    ///
    /// 关键事实（实测）：115 离线完成后，视频落在「离线目录 wp_path_id 下新建的文件夹」里，
    /// 夹带一堆 <115MB 的垃圾文件（广告图 / txt / url / 封面图）。而 task_lists 只返回
    /// 「进行中/失败」的任务，已完成任务会立刻消失，无法用 file_id 定位产物。
    ///
    /// 定位策略：
    /// 1. 记录推送前的文件夹集合；
    /// 2. 轮询离线目录，找「新出现的文件夹」（离线产物必然是推送后才创建的）；
    /// 3. 找不到新文件夹时，退而用「名字含 keyword」的文件夹兜底；
    /// 4. 再不行，删父目录内 <115MB 文件（覆盖单文件磁力直接落根的场景）。
    ///
    /// 返回删除数量。供「推送成功后后台清理」复用，不重复推送。
    public func waitAndCleanSmallFiles(
        keyword: String,
        cookie: String,
        folderCID: String,
        existingFolderIDs: Set<String>? = nil,
        timeout: TimeInterval = 90,
        thresholdBytes: Int64 = 115 * 1024 * 1024
    ) async throws -> Int {
        let needle = normalizedKey(keyword)
        let start = Date()
        var knownFolders = existingFolderIDs ?? []

        // 兼容旧调用；新推送入口应在 addOfflineTask 前传入目录快照，避免新目录被误记为旧目录。
        if existingFolderIDs == nil,
           let initial = try? await listFiles(cid: folderCID, cookie: cookie, limit: 500) {
            knownFolders = Set(initial.filter { $0.isDir }.map { $0.fileID.isEmpty ? $0.cid : $0.fileID }.filter { !$0.isEmpty })
        }

        while Date().timeIntervalSince(start) < timeout {
            // 按参考脚本：递归扫描父目录及两层子目录，按名称/扩展名删除垃圾。
            let junkDeleted = try await deleteJunkFiles(in: folderCID, cookie: cookie, maxDepth: 2)
            if junkDeleted > 0 { return junkDeleted }

            let files = try await listFiles(cid: folderCID, cookie: cookie, limit: 500)
            let dirs = files.filter { $0.isDir }

            // 1) 只在用户配置的离线父目录中匹配番号目录。
            //    同一番号可能在网盘其他位置有多个副本；全盘挑最大视频会误清旧目录并提前返回 0。
            if !needle.isEmpty {
                let matchedDirs = dirs.filter { dir in
                    let nameKey = normalizedKey(dir.name)
                    return nameKey.contains(needle) || needle.contains(nameKey)
                }
                for dir in matchedDirs {
                    let key = dir.fileID.isEmpty ? dir.cid : dir.fileID
                    guard !key.isEmpty,
                          let children = try? await listFiles(cid: key, cookie: cookie, limit: 500),
                          children.contains(where: { !$0.isDir && $0.isVideo && $0.size >= thresholdBytes })
                    else { continue }
                    return try await deleteSmallFiles(in: key, cookie: cookie, thresholdBytes: thresholdBytes)
                }
            }

            // 2) 新出现的文件夹（磁力链接没有可用番号时的兜底）
            for dir in dirs {
                let key = dir.fileID.isEmpty ? dir.cid : dir.fileID
                if key.isEmpty || knownFolders.contains(key) { continue }
                knownFolders.insert(key)
                let deleted = try await deleteSmallFiles(in: key, cookie: cookie, thresholdBytes: thresholdBytes)
                if deleted >= 0 { return deleted }
            }

            // 3) 名字含 keyword 的文件夹兜底
            if !needle.isEmpty {
                for dir in dirs {
                    let key = dir.fileID.isEmpty ? dir.cid : dir.fileID
                    if key.isEmpty { continue }
                    let nameKey = normalizedKey(dir.name)
                    if nameKey.contains(needle) || needle.contains(nameKey) {
                        let deleted = try await deleteSmallFiles(in: key, cookie: cookie, thresholdBytes: thresholdBytes)
                        if deleted >= 0 { return deleted }
                    }
                }
            }

            try await Task.sleep(nanoseconds: 3_000_000_000)
        }

        // 兜底：删父目录内 <115MB 文件（单文件磁力直接落根，或 keyword 匹配不到文件夹名）
        return try await deleteSmallFiles(in: folderCID, cookie: cookie, thresholdBytes: thresholdBytes)
    }

    // MARK: - 删除文件（推送后清理垃圾文件）

    private func isJunkFile(_ file: FileItem) -> Bool {
        guard !file.isDir, !file.fileID.isEmpty else { return false }
        let name = file.name.lowercased()
        if file.isVideo { return false }
        return [".txt", ".html", ".htm", ".url", ".nfo", ".xml", ".mht", ".chm", ".exe", ".apk", ".torrent", ".js", ".css"].contains { name.hasSuffix($0) }
            || file.size < 115 * 1024 * 1024
    }

    private func deleteJunkFiles(in cid: String, cookie: String, maxDepth: Int) async throws -> Int {
        let files = try await listFiles(cid: cid, cookie: cookie, limit: 1150)
        var deleted = 0
        let junk = files.filter { isJunkFile($0) }
        if !junk.isEmpty {
            deleted += try await deleteFiles(cid: cid, fileIDs: junk.map(\.fileID), cookie: cookie)
        }
        guard maxDepth > 0 else { return deleted }
        for dir in files where dir.isDir {
            let child = dir.cid.isEmpty ? dir.fileID : dir.cid
            if !child.isEmpty {
                deleted += try await deleteJunkFiles(in: child, cookie: cookie, maxDepth: maxDepth - 1)
            }
        }
        return deleted
    }

    /// 删除目录内指定文件（对齐参考脚本 POST webapi.115.com/rb/delete，form pid + fid[N]）。
    /// 返回实际删除数量。
    /// 注意：只有 webapi.115.com/rb/delete 能成功删除，但该域名在 iOS 上 SSL EOF 偶发，
    /// 用独立 session + 多次退避重试。
    @discardableResult
    public func deleteFiles(cid: String, fileIDs: [String], cookie: String) async throws -> Int {
        let ids = fileIDs.filter { !$0.isEmpty }
        guard !ids.isEmpty else { return 0 }

        var body = URLComponents()
        var items = [URLQueryItem(name: "pid", value: cid), URLQueryItem(name: "ignore_warn", value: "1")]
        for (i, fid) in ids.enumerated() {
            items.append(URLQueryItem(name: "fid[\(i)]", value: fid))
        }
        body.queryItems = items

        let url = URL(string: "https://webapi.115.com/rb/delete")!
        var lastError: Error = Pan115Error.playURLNotFound
        // 多次退避重试：SSL EOF 是偶发的，多试几次大概率成功
        for attempt in 0..<6 {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.httpBody = body.percentEncodedQuery?.data(using: .utf8)
            req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            appendCommonHeaders(&req, cookie: cookie)
            do {
                let (data, response) = try await deleteSession.data(for: req)
                if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                    throw Pan115Error.http(http.statusCode)
                }
                guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
                    throw Pan115Error.playURLNotFound
                }
                if text.lowercased().contains("<html") || text.contains("登录") {
                    throw Pan115Error.cookieInvalid
                }
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if boolState(obj["state"]) || (obj["state"] as? Int) == 1 {
                        return ids.count
                    }
                }
            } catch {
                lastError = error
                // 退避：0.5s, 1s, 1.5s, 2s, 2.5s
                if attempt < 5 {
                    try? await Task.sleep(nanoseconds: UInt64(500_000_000 * (attempt + 1)))
                }
            }
        }
        throw lastError
    }

    /// 删除目录内所有小于给定字节数的文件（用于清理离线完成后夹带的小文件）。
    /// 只删非目录、有 fid 的文件；返回删除数量。
    @discardableResult
    public func deleteSmallFiles(in cid: String, cookie: String, thresholdBytes: Int64 = 115 * 1024 * 1024) async throws -> Int {
        var deleted = 0
        var lastRemaining = 0
        for attempt in 0..<3 {
            let files = try await listFiles(cid: cid, cookie: cookie, limit: 500)
            let small = files.filter { !$0.isDir && $0.size > 0 && $0.size < thresholdBytes && !$0.fileID.isEmpty }
            guard !small.isEmpty else { return deleted }
            deleted += try await deleteFiles(cid: cid, fileIDs: small.map(\.fileID), cookie: cookie)

            // 115 返回成功后仍可能有短暂延迟，必须复查实际目录。
            let remainingFiles = try await listFiles(cid: cid, cookie: cookie, limit: 500)
            let remaining = remainingFiles.filter { !$0.isDir && $0.size > 0 && $0.size < thresholdBytes && !$0.fileID.isEmpty }
            lastRemaining = remaining.count
            if remaining.isEmpty { return deleted }
            if attempt < 2 {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        throw Pan115Error.cleanupFailed(lastRemaining)
    }

    private func pickVideo(from files: [FileItem], keyword: String?, requireMatch: Bool) -> FileItem? {
        var videos = files.filter { !$0.isDir && $0.isVideo && !$0.pickCode.isEmpty }
        if videos.isEmpty {
            videos = files.filter { !$0.isDir && !$0.pickCode.isEmpty && $0.size > 10_000_000 }
        }
        let scored: [FileItem]
        if let keyword, !keyword.isEmpty {
            let n = normalizedKey(keyword)
            let hits = videos.filter { file in
                let name = normalizedKey(file.name)
                return name.contains(n)
            }
            scored = hits.isEmpty && !requireMatch ? videos : hits
        } else {
            if requireMatch { return nil }
            scored = videos
        }
        return scored.max(by: { score($0) < score($1) })
    }

    /// 排除 trailer/sample/preview，大文件优先（对齐 Forward 模块 scoreWesternFile）
    private func score(_ file: FileItem) -> Int {
        var s = 0
        let n = file.name.lowercased()
        for bad in ["trailer", "sample", "preview", "behind", "bts"] {
            if n.contains(bad) { s -= 50 }
        }
        if file.size >= 2_000_000_000 { s += 30 }
        else if file.size >= 1_000_000_000 { s += 20 }
        else if file.size >= 500_000_000 { s += 10 }
        else if file.size > 0 && file.size < 100_000_000 { s -= 20 }
        if n.count > 30 { s += 5 }
        s += Int(min(file.size / 50_000_000, 40))
        return s
    }

    /// 多个搜索关键词变体：115 搜索对「-」敏感，务必保留连字符。
    private func searchKeywords(from raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let upper = trimmed.uppercased()

        // FC2 特判
        if let r = try? NSRegularExpression(pattern: #"FC2(?:[- ]?PPV)?[- ]?(\d{5,8})"#, options: .caseInsensitive),
           let m = r.firstMatch(in: upper, range: NSRange(upper.startIndex..., in: upper)),
           let range = Range(m.range(at: 1), in: upper) {
            let digits = String(upper[range])
            return ["FC2-\(digits)", "FC2\(digits)"]
        }

        // 保留连字符，只做大小写两种变体（去连字符会搜索失败）
        var variants: [String] = []
        variants.append(trimmed)   // 原样（小写 + 连字符）
        if upper != trimmed {
            variants.append(upper) // 大写 + 连字符
        }
        return variants.uniqued
    }

    private func normalizedKey(_ raw: String?) -> String {
        guard let raw else { return "" }
        return raw.lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
            // 115 常将 FC2-PPV 写成 FC2PPV，视为同一番号。
            .replacingOccurrences(of: "fc2ppv", with: "fc2")
    }

    private func extractFileList(_ obj: [String: Any]) -> [FileItem] {
        var raw: [[String: Any]] = []
        // 兼容 search 接口双层 data 嵌套（data.data / data.list / data.files 等）
        func collect(_ value: Any?) {
            guard let value else { return }
            if let arr = value as? [[String: Any]] { raw = arr; return }
            if let dict = value as? [String: Any] {
                for key in ["data", "list", "files", "items", "videos"] {
                    if let arr = dict[key] as? [[String: Any]] { raw = arr; return }
                }
                // 兜底：dict 里第一个数组
                if raw.isEmpty {
                    for (_, v) in dict {
                        if let arr = v as? [[String: Any]] { raw = arr; break }
                    }
                    if raw.isEmpty { raw = [dict] }
                }
            }
        }
        collect(obj["data"])
        if raw.isEmpty { collect(obj["list"]) }
        if raw.isEmpty { collect(obj["files"]) }
        if raw.isEmpty { collect(obj) }
        return raw.map { item in
            let name = (item["n"] as? String) ?? (item["fn"] as? String) ?? (item["name"] as? String) ?? (item["file_name"] as? String) ?? (item["filename"] as? String) ?? ""
            let pc = (item["pc"] as? String) ?? (item["pick_code"] as? String) ?? (item["pickcode"] as? String) ?? (item["pickCode"] as? String) ?? ""
            let fid = stringValue(item["fid"] ?? item["file_id"] ?? item["id"])
            let cid = stringValue(item["cid"] ?? item["pid"])
            let isDir = (item["pc"] == nil && item["pick_code"] == nil && item["pickcode"] == nil && item["sha"] == nil && item["sha1"] == nil && !cid.isEmpty && pc.isEmpty)
                || intValue(item["fc"]) == 0
            return FileItem(name: name, pickCode: pc, fileID: fid, cid: cid.isEmpty ? fid : cid, isDir: isDir, size: Int64(doubleValue(item["s"] ?? item["fs"] ?? item["size"])))
        }
    }

    private func parseMaster(_ text: String) -> [PlayStream] {
        let lines = text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
        var streams: [PlayStream] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.contains("#EXT-X-STREAM-INF") {
                let name = capture(line, #"NAME="([^"]+)""#)
                let height = Int(capture(line, #"RESOLUTION=\d+x(\d+)"#) ?? "") ?? 0
                let bw = Int(capture(line, #"BANDWIDTH=(\d+)"#) ?? "") ?? 0
                let label = qualityLabel(name: name, height: height, bandwidth: bw)
                if i + 1 < lines.count {
                    var u = lines[i + 1]
                    if u.hasPrefix("https: //") { u = u.replacingOccurrences(of: "https: //", with: "https://") }
                    if !u.hasPrefix("http"), let abs = URL(string: u, relativeTo: URL(string: "https://115.com/")) {
                        u = abs.absoluteString
                    }
                    if u.hasPrefix("http") {
                        streams.append(PlayStream(name: label, url: u, bandwidth: bw + qualityPriority(name: name, height: height) * 10_000_000))
                    }
                }
            }
            i += 1
        }
        return streams.sorted { $0.bandwidth > $1.bandwidth }
    }

    private func capture(_ line: String, _ pattern: String) -> String? {
        guard let r = try? NSRegularExpression(pattern: pattern),
              let m = r.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              m.numberOfRanges > 1,
              let range = Range(m.range(at: 1), in: line) else { return nil }
        return String(line[range])
    }

    private func qualityLabel(name: String?, height: Int, bandwidth: Int) -> String {
        let n = (name ?? "").uppercased()
        switch n {
        case "BD": return "4K"
        case "UD": return "1080P"
        case "HD": return "720P"
        case "SD": return "480P"
        case "LD": return "360P"
        default: break
        }
        if height >= 2160 { return "4K" }
        if height >= 1080 { return "1080P" }
        if height >= 720 { return "720P" }
        if height >= 480 { return "480P" }
        if height >= 360 { return "360P" }
        if bandwidth > 0 { return "\(bandwidth / 1000)k" }
        return "原画"
    }

    private func qualityPriority(name: String?, height: Int) -> Int {
        let n = (name ?? "").uppercased()
        switch n {
        case "BD": return 4
        case "UD": return 3
        case "HD": return 2
        case "SD": return 1
        case "LD": return 0
        default: break
        }
        if height >= 2160 { return 4 }
        if height >= 1080 { return 3 }
        if height >= 720 { return 2 }
        if height >= 480 { return 1 }
        return 0
    }

    private func json(for req: URLRequest, retries: Int = 2) async throws -> [String: Any] {
        var lastErr: Error = Pan115Error.playURLNotFound
        for attempt in 0...retries {
            do {
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
            } catch {
                lastErr = error
                if attempt < retries {
                    try? await Task.sleep(nanoseconds: 400_000_000 * UInt64(attempt + 1))
                }
            }
        }
        throw lastErr
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

    static func playHeaders(cookie: String) -> [String: String] {
        [
            "User-Agent": safariUA,
            "Accept": "*/*",
            "Origin": "https://115.com",
            "Referer": "https://115.com/",
            "Cookie": Pan115Settings.normalizeCookie(cookie),
        ]
    }

    private func appendCommonHeaders(_ req: inout URLRequest, cookie: String) {
        let h = Self.playHeaders(cookie: cookie)
        req.setValue(h["User-Agent"], forHTTPHeaderField: "User-Agent")
        req.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue(h["Origin"], forHTTPHeaderField: "Origin")
        req.setValue(h["Referer"], forHTTPHeaderField: "Referer")
        req.setValue(h["Cookie"], forHTTPHeaderField: "Cookie")
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
    case cleanupFailed(Int)

    public var errorDescription: String? {
        switch self {
        case .emptyLink: return "磁力链接为空"
        case .cookieInvalid: return "115 Cookie 无效或已过期，请重新填写 UID/CID/SEID"
        case .missingFolder: return "请先填写 115 离线目录 CID"
        case .signFailed: return "获取 115 签名失败"
        case .http(let code): return "115 接口 HTTP \(code)"
        case .timeout: return "等待 115 离线完成超时"
        case .taskFailed(let msg): return "115 离线失败：\(msg)"
        case .fileNotFound: return "离线目录里没找到与当前番号匹配的视频"
        case .playURLNotFound: return "无法获取 115 原画播放地址"
        case .cleanupFailed(let count): return "115 垃圾文件仍剩余 \(count) 个"
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

private extension Array where Element == Pan115Client.FileItem {
    var uniquedFiles: [Pan115Client.FileItem] {
        var seen = Set<String>()
        return filter { item in
            let key = item.fileID.isEmpty ? item.cid : item.fileID
            return seen.insert(key).inserted
        }
    }
}

private extension Array where Element == String {
    var uniqued: [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
