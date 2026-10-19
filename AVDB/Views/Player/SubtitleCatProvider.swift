import Foundation

// Native, inert DOM adapter. No scripts, translation, uploads or challenge solvers.
enum OnlineSubtitleSource: String, CaseIterable, Hashable {
    case xunlei, subtitleCat
    var title: String { self == .xunlei ? "迅雷" : "SubtitleCat" }
}
enum OnlineSubtitleRequestKind: Equatable {
    case xunleiSearch, catSearch, catDetail, download
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
    // JRHTML has already decoded attribute entities exactly once. Foundation resolves raw spaces,
    // Unicode and existing percent escapes without rebuilding or guessing the download path.
    static func resolve(_ href: String, page: URL, kind: OnlineSubtitleRequestKind) -> URL? {
        guard href.utf8.count <= 4096, let u = URL(string: href, relativeTo: page)?.absoluteURL,
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

// Shared by shipping model and native regression harness. Each source has an independent
// terminal state. Epochs invalidate even a transport which ignores cooperative cancellation.
struct OnlineSubtitleSearchState {
    private(set) var generation = 0
    private(set) var rows: [OnlineSubtitleSource: [OnlineSubtitleCandidate]] = [:]
    private(set) var states: [OnlineSubtitleSource: String] = [:]
    private(set) var pending = Set<OnlineSubtitleSource>()
    mutating func invalidate() { generation += 1; pending = [] }
    mutating func begin() -> Int {
        invalidate(); rows = [:]; pending = Set(OnlineSubtitleSource.allCases)
        states = Dictionary(uniqueKeysWithValues: OnlineSubtitleSource.allCases.map { ($0, "搜索中…") })
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
    static func run(query: String, cached: [OnlineSubtitleSource: [OnlineSubtitleCandidate]], fetch: @escaping Fetch,
                    receive: @escaping (OnlineSubtitleSearchOutcome) async -> Void) async {
        await withTaskGroup(of: OnlineSubtitleSearchOutcome.self) { group in
            for source in OnlineSubtitleSource.allCases {
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        if let rows = cached[source] { return .init(source: source, result: .success(rows)) }
                        let u = try source == .xunlei ? OnlineSubtitlePolicy.searchURL(query) : SubtitleCatProvider.searchURL(query)
                        let data = try await fetch(u, source == .xunlei ? .xunleiSearch : .catSearch)
                        try Task.checkCancellation()
                        let rows = try source == .xunlei ? OnlineSubtitlePolicy.candidates(data) : SubtitleCatProvider.candidates(data, page: u)
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
