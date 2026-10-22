import Foundation
import CoreFoundation
import CryptoKit

// Native, inert DOM adapter. No scripts, translation, uploads or challenge solvers.
enum OnlineSubtitleSource: String, CaseIterable, Hashable {
    case xunlei, subtitleCat, chickenRice
    var title: String {
        switch self { case .xunlei: return "迅雷"; case .subtitleCat: return "SubtitleCat"; case .chickenRice: return "海南鸡字幕池" }
    }
}
enum OnlineSubtitleRequestKind: Equatable {
    case xunleiSearch, catSearch, catDetail, chickenSearch, download
    var html: Bool { self == .catSearch || self == .catDetail }
    var metadata: Bool { self != .download }
    var accept: String { html ? "text/html" : (metadata ? "application/json" : "text/plain, application/octet-stream") }
}
enum SubtitleCatProvider {
    static func searchURL(_ query: String) throws -> URL {
        _ = try OnlineSubtitlePolicy.searchURL(query)
        var c = URLComponents(string: "https://www.subtitlecat.com/index.php")!
        c.queryItems = [URLQueryItem(name: "search", value: query.trimmingCharacters(in: .whitespacesAndNewlines))]
        return c.url!
    }
    static func allowed(_ u: URL, kind: OnlineSubtitleRequestKind) -> Bool {
        guard u.scheme?.lowercased() == "https", u.host?.lowercased() == "www.subtitlecat.com",
              u.user == nil, u.password == nil, u.fragment == nil, u.port == nil || u.port == 443,
              let c = URLComponents(url: u, resolvingAgainstBaseURL: false) else { return false }
        // Reject ambiguous path separators, residual encoding and control characters; never repeatedly decode.
        let p = c.percentEncodedPath.lowercased()
        guard !["%2f", "%5c", "%25", "%00", "%0a", "%0d"].contains(where: p.contains),
              !u.path.contains("\\"), !u.path.unicodeScalars.contains(where: { $0.value < 32 }) else { return false }
        if kind == .catSearch {
            let items = c.queryItems ?? []
            return u.path == "/index.php" && items.count == 1 && items[0].name == "search" &&
                !(items[0].value ?? "").isEmpty && (items[0].value ?? "").count <= 200
        }
        guard u.query == nil else { return false }
        let ext = kind == .catDetail ? "html" : "srt"
        return [.catDetail, .download].contains(kind) &&
            u.path.range(of: "^/subs/[0-9]+/[^/]+\\." + ext + "$", options: .regularExpression) != nil
    }
    // JRHTML decoded attribute entities once. Encode only invalid URL characters, preserving
    // existing %HH escapes even in a mixed Unicode/%20 href; never decode or guess paths.
    private static let hrefCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=%")
    static func resolve(_ href: String, page: URL, kind: OnlineSubtitleRequestKind) -> URL? {
        guard href.utf8.count <= 4096,
              !href.unicodeScalars.contains(where: { $0.value < 32 }),
              href.range(of: #"%(?![0-9A-Fa-f]{2})"#, options: .regularExpression) == nil,
              let encoded = href.addingPercentEncoding(withAllowedCharacters: hrefCharacters),
              let u = URL(string: encoded, relativeTo: page)?.absoluteURL,
              allowed(u, kind: kind) else { return nil }
        return u
    }
    static func document(_ data: Data) throws -> JRNode {
        guard data.count <= OnlineSubtitlePolicy.searchLimit, let html = String(data: data, encoding: .utf8) else {
            throw OnlineSubtitleError.invalid("SubtitleCat 页面大小或编码异常")
        }
        let lower = html.lowercased()
        guard !["cf-chl-", "challenge-platform", "just a moment", "attention required", "g-recaptcha", "hcaptcha"].contains(where: lower.contains) else {
            throw OnlineSubtitleError.invalid("SubtitleCat 访问验证/限制，请在原站查看；不会绕过验证")
        }
        return try JRHTML.tree(html)
    }
    static func candidates(_ data: Data, page: URL) throws -> [OnlineSubtitleCandidate] {
        let root = try document(data)
        guard let table = root.all({ $0.tag == "table" && $0.cls("sub-table") }).first else {
            // Distinguish an explicitly empty page from unknown markup/challenge.
            let text = root.text.lowercased()
            if text.contains("no subtitles found") || text.contains("no results found") { return [] }
            throw OnlineSubtitleError.invalid("SubtitleCat 页面结构已变化或访问受限")
        }
        var seen = Set<String>(); var rows: [OnlineSubtitleCandidate] = []
        for a in table.all({ $0.tag == "a" && $0.has("href") }).prefix(1000) {
            guard let u = resolve(a.attrs["href"]!, page: page, kind: .catDetail), seen.insert(u.absoluteString).inserted else { continue }
            rows.append(.init(id: "subtitleCat:" + u.absoluteString, name: String(a.text.prefix(240)), language: "待选语言", ext: "html", url: u, source: .subtitleCat))
            if rows.count == 80 { break }
        }
        return rows
    }
    static func languages(_ data: Data, row: OnlineSubtitleCandidate) throws -> [OnlineSubtitleCandidate] {
        let root = try document(data)
        let sections = root.all { $0.cls("sub-single") }
        guard !sections.isEmpty else { throw OnlineSubtitleError.invalid("SubtitleCat 语言页面结构异常") }
        var seen = Set<String>(); var rows: [OnlineSubtitleCandidate] = []
        for section in sections.prefix(300) {
            for a in section.all({ $0.tag == "a" && ($0.attrs["id"] ?? "").hasPrefix("download_") }) {
                let code = String(a.attrs["id"]!.dropFirst(9))
                guard code.range(of: #"^[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})?$"#, options: .regularExpression) != nil,
                      let href = a.attrs["href"], let url = resolve(href, page: row.url, kind: .download),
                      seen.insert(code + ":" + url.absoluteString).inserted else { continue }
                let language = code == "zh-CN" ? "简体中文 (zh-CN)" : (code == "zh-TW" ? "繁体中文 (zh-TW)" : code)
                rows.append(.init(id: "subtitleCat:" + code + ":" + url.absoluteString, name: row.name, language: language, ext: "srt", url: url, source: .subtitleCat, parentID: row.id))
            }
        }
        func rank(_ r: OnlineSubtitleCandidate) -> Int { r.language.hasPrefix("简体") ? 0 : (r.language.hasPrefix("繁体") ? 1 : 2) }
        return Array(rows.sorted { rank($0) == rank($1) ? $0.language < $1.language : rank($0) < rank($1) }.prefix(120))
    }
}

// Independent HTTP mapping of the user-supplied public origin, not DLL code.
// Origin is deliberately fixed. A different deployment requires a reviewed app update.
enum ChickenRiceProvider {
    static let origin = "https://chickenrice-subtitle-pool.jzdxjk.workers.dev"
    static let host = "chickenrice-subtitle-pool.jzdxjk.workers.dev"
    static func searchURL(_ query: String) throws -> URL {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.rangeOfCharacter(from: .whitespacesAndNewlines) == nil, CatalogueIdentity.key(q) != nil else { throw OnlineSubtitleError.invalid("海南鸡仅支持完整公开番号；不支持此查询") }
        var c = URLComponents(string: origin + "/api/v1/subtitles/search")!
        c.queryItems = [URLQueryItem(name: "code", value: q)]
        return c.url!
    }
    static func safeID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 512 && id != "." && id != ".." &&
        !id.contains("/") && !id.contains("\\") && !id.contains("%") &&
        !id.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
    }
    static func downloadURL(_ id: String) throws -> URL {
        guard safeID(id), let part = id.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")),
              let u = URL(string: origin + "/api/v1/subtitles/" + part + "/download") else { throw OnlineSubtitleError.invalid("字幕池 ID 不安全") }
        return u
    }
    static func allowed(_ u: URL, search: Bool) -> Bool {
        guard u.scheme == "https", u.host?.lowercased() == host, u.user == nil, u.password == nil,
              u.port == nil || u.port == 443, u.fragment == nil,
              let c = URLComponents(url: u, resolvingAgainstBaseURL: false) else { return false }
        let p = c.percentEncodedPath.lowercased()
        guard !["%2f", "%5c", "%25", "%00", "%0a", "%0d"].contains(where: p.contains) else { return false }
        if search {
            let items = c.queryItems ?? []
            return u.path == "/api/v1/subtitles/search" && items.count == 1 && items[0].name == "code" &&
                items[0].value.flatMap { try? searchURL($0) } == u
        }
        let parts = u.path.split(separator: "/", omittingEmptySubsequences: false)
        guard u.query == nil, parts.count == 6, parts[0].isEmpty, parts[1] == "api", parts[2] == "v1",
              parts[3] == "subtitles", parts[5] == "download", safeID(String(parts[4])) else { return false }
        return (try? downloadURL(String(parts[4]))) == u
    }
    private static func number(_ row: [String: Any], _ key: String, max: Double) throws -> Double? {
        guard let value = row[key], !(value is NSNull) else { return nil }
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite,
              n.doubleValue >= 0, n.doubleValue <= max else { throw OnlineSubtitleError.invalid("字幕池数值元数据异常") }
        return n.doubleValue
    }
    static func candidates(_ data: Data, query: String) throws -> [OnlineSubtitleCandidate] {
        guard data.count <= OnlineSubtitlePolicy.searchLimit, CatalogueIdentity.key(query) != nil,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["items"] as? [[String: Any]], rows.count <= 500 else { throw OnlineSubtitleError.invalid("字幕池响应格式异常") }
        var output: [OnlineSubtitleCandidate] = []; var seen = Set<String>()
        for row in rows {
            guard let id = row["id"] as? String, let code = row["code"] as? String,
                  CatalogueIdentity.key(code) == CatalogueIdentity.key(query),
                  let format = row["format"] as? String else { continue }
            let ext = format.lowercased()
            guard ["srt", "vtt", "ass", "ssa"].contains(ext) else { continue }
            let u = try downloadURL(id)
            let duration = try number(row, "duration_seconds", max: 604800)
            let size = try number(row, "size_bytes", max: Double(OnlineSubtitlePolicy.downloadLimit))
            guard size == nil || size!.rounded() == size else { throw OnlineSubtitleError.invalid("字幕池大小不是整数") }
            var sha: String?
            if let value = row["sha256"], !(value is NSNull) {
                guard let hash = value as? String, hash.range(of: #"^[a-fA-F0-9]{64}$"#, options: .regularExpression) != nil else { throw OnlineSubtitleError.invalid("字幕池 SHA-256 格式异常") }
                sha = hash.lowercased()
            }
            // No language field in the documented schema: do not invent Chinese detection.
            let uploaded = (row["uploaded_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
            guard seen.insert(id).inserted else { continue }
            output.append(.init(id: "chickenRice:" + id, name: code, language: "未知", ext: ext, url: u, source: .chickenRice,
                                durationSeconds: duration, sizeBytes: size.map(Int.init), expectedSHA256: sha, uploadedAt: uploaded))
            if output.count == 80 { break }
        }
        return output
    }
    static func verify(_ data: Data, row: OnlineSubtitleCandidate) throws {
        guard data.count <= OnlineSubtitlePolicy.downloadLimit else { throw OnlineSubtitleError.invalid("字幕超过大小限制") }
        if let expected = row.expectedSHA256 {
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actual == expected else { throw OnlineSubtitleError.invalid("字幕 SHA-256 校验失败") }
        }
    }
}

// Shared by shipping model and native regression harness. Each source has an independent
// terminal state. Epochs invalidate even a transport which ignores cooperative cancellation.
struct OnlineSubtitleSearchState {
    private(set) var generation = 0
    private(set) var rows: [OnlineSubtitleSource: [OnlineSubtitleCandidate]] = [:]
    private(set) var states: [OnlineSubtitleSource: String] = [:]
    private(set) var pending = Set<OnlineSubtitleSource>()
    mutating func invalidate() { generation += 1; pending = [] }
    mutating func begin(sources: [OnlineSubtitleSource] = OnlineSubtitleSource.allCases) -> Int {
        invalidate(); rows = [:]; pending = Set(sources)
        states = Dictionary(uniqueKeysWithValues: OnlineSubtitleSource.allCases.map { ($0, sources.contains($0) ? "搜索中…" : "已关闭") })
        return generation
    }
    @discardableResult mutating func receive(_ source: OnlineSubtitleSource, token: Int, result: Result<[OnlineSubtitleCandidate], Error>) -> Bool {
        guard token == generation, pending.contains(source) else { return false }
        pending.remove(source)
        switch result {
        case .success(let list): rows[source] = list; states[source] = list.isEmpty ? "无结果" : "找到 \(list.count) 条"
        case .failure(let error): rows[source] = []; states[source] = "失败：\(error.localizedDescription)"
        }
        return true
    }
    var results: [OnlineSubtitleCandidate] { OnlineSubtitleSource.allCases.flatMap { rows[$0] ?? [] } }
}
struct OnlineSubtitleSearchOutcome: @unchecked Sendable {
    let source: OnlineSubtitleSource
    let result: Result<[OnlineSubtitleCandidate], Error>
}
enum OnlineSubtitleParallelSearch {
    typealias Fetch = (URL, OnlineSubtitleRequestKind) async throws -> Data
    static func sorted(_ rows: [OnlineSubtitleCandidate], query: String) -> [OnlineSubtitleCandidate] {
        let pattern = "(?<![A-Za-z0-9])" + NSRegularExpression.escapedPattern(for: query) + "(?![A-Za-z0-9])"
        func exact(_ row: OnlineSubtitleCandidate) -> Bool { row.name.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil }
        return rows.sorted {
            if exact($0) != exact($1) { return exact($0) }
            let order = $0.name.compare($1.name, options: .caseInsensitive)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
    static func run(query: String, cached: [OnlineSubtitleSource: [OnlineSubtitleCandidate]], sources: [OnlineSubtitleSource] = OnlineSubtitleSource.allCases, fetch: @escaping Fetch,
                    receive: @escaping (OnlineSubtitleSearchOutcome) async -> Void) async {
        await withTaskGroup(of: OnlineSubtitleSearchOutcome.self) { group in
            for source in sources {
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        if let rows = cached[source] { return .init(source: source, result: .success(rows)) }
                        let u: URL; let kind: OnlineSubtitleRequestKind
                        switch source {
                        case .xunlei: u = try OnlineSubtitlePolicy.searchURL(query); kind = .xunleiSearch
                        case .subtitleCat: u = try SubtitleCatProvider.searchURL(query); kind = .catSearch
                        case .chickenRice: u = try ChickenRiceProvider.searchURL(query); kind = .chickenSearch
                        }
                        let data = try await fetch(u, kind)
                        try Task.checkCancellation()
                        let rows: [OnlineSubtitleCandidate]
                        switch source {
                        case .xunlei: rows = try OnlineSubtitlePolicy.candidates(data)
                        case .subtitleCat: rows = try SubtitleCatProvider.candidates(data, page: u)
                        case .chickenRice: rows = try ChickenRiceProvider.candidates(data, query: query)
                        }
                        return .init(source: source, result: .success(sorted(rows, query: query)))
                    } catch { return .init(source: source, result: .failure(error)) }
                }
            }
            for await outcome in group {
                if !Task.isCancelled { await receive(outcome) }
            }
        }
    }
}
