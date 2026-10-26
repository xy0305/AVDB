import Foundation

// Native, source-scoped port. Uploaded JS is reference data, never evaluated.
struct TangxinAuthor: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    var id: URL { url }
}
struct TangxinVideo: Identifiable, Hashable, Sendable {
    let url: URL
    let title: String
    let poster: URL?
    let author: TangxinAuthor?
    var id: URL { url } // Not a JavDB/Movie identifier.
}
enum TangxinPageState: String, Sendable {
    case content, sourceEmpty, filtered, structureChanged
}
// Counts only: never persist titles, accounts, URLs or blocked metadata in diagnostics.
struct TangxinPageReport: Sendable {
    let cards: Int
    let extracted: Int
    let blocked: Int
    let malformed: Int
    let duplicates: Int
}
struct TangxinPage: Sendable {
    let videos: [TangxinVideo]
    let next: URL?
    let heading: String?
    let state: TangxinPageState
    let report: TangxinPageReport
}
struct TangxinTag: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    var id: URL { url }
}
struct TangxinDetail: Sendable {
    let video: TangxinVideo
    let summary: String
    let tags: [String]
    var tagLinks: [TangxinTag] = []
    let stream: URL
}
struct TangxinPlayback: Identifiable, Sendable {
    let url: URL
    let headers: [String:String]
    var id: URL { url }
}
enum TangxinError: LocalizedError {
    case structure, blocked, unsafe
    var errorDescription: String? {
        switch self {
        case .structure: return "来源页面结构变化或没有可用视频，请重试。"
        case .blocked: return "此内容因年龄或同意风险不可显示。"
        case .unsafe: return "来源地址或媒体范围不符合安全要求。"
        }
    }
}
enum TangxinPolicy {
    static let origin = URL(string: "https://tangxinvlog.app/")!
    static let featured = origin.appendingPathComponent("featured/")
    static let cdn = "t.5gcdn.xyz"
    static let headers = ["User-Agent": OnlinePolicy.ua, "Referer": origin.absoluteString]
    // Nicknames are deliberately NOT inspected. Generic 黑料 alone is not a verdict.
    static func permitted(_ metadata: String) -> Bool {
        let s = metadata.folding(options: [.widthInsensitive], locale: nil).lowercased().replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        if s.range(of: #"(?:^|[^0-9])(?:[0-9]|1[0-7])(?:岁|歲|years?old|yo)(?:[^0-9]|$)"#, options: .regularExpression) != nil { return false }
        return !["未成年", "未满18", "未滿18", "幼女", "幼童", "儿童", "兒童", "小学生", "小學生", "初中", "高中生", "中学生", "中學生", "萝莉", "蘿莉", "偷拍", "偷录", "偷錄", "盜攝", "盗摄", "泄露", "洩露", "流出", "外流", "非自愿", "非自願", "迷奸", "强奸", "強姦", "下药", "下藥", "醉奸", "rape", "underage", "hidden camera", "revenge porn"].contains { s.contains($0.replacingOccurrences(of: " ", with: "")) }
    }
    static func page(_ url: URL) -> Bool {
        guard OnlinePolicy.secure(url), url.host == origin.host, url.query == nil, url.fragment == nil else { return false }
        let encoded = URLComponents(url:url,resolvingAgainstBaseURL:false)?.percentEncodedPath.lowercased() ?? ""
        guard !encoded.contains("%2f"), !encoded.contains("%5c"), !encoded.contains("%25") else { return false }
        let p = url.path.split(separator: "/").map(String.init)
        if p.first == "featured" { return p.count == 1 || (p.count == 2 && Int(p[1]).map { $0 > 1 } == true) }
        return ["a", "tag"].contains(p.first ?? "") && (p.count == 2 || (p.count == 3 && Int(p[2]).map { $0 > 1 } == true)) && slug(p[1]) && (p.first != "tag" || permitted(p[1]))
    }
    // Live GET (2026-10-26): collection routes without a terminal slash return
    // HTTP 307 to the identical HTTPS path plus '/'. Normalize only validated
    // collection URLs; transport still refuses every redirect and rechecks DNS.
    static func canonicalPage(_ url: URL) -> URL? {
        guard page(url) else { return nil }
        if url.absoluteString.hasSuffix("/") { return url }
        guard let canonical = URL(string: url.absoluteString + "/"), page(canonical) else { return nil }
        return canonical
    }
    static func slug(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 150 && s != "." && s != ".." && !s.contains(where: { $0 == "/" || $0 == "\\" || $0.isNewline || $0.asciiValue.map { $0 < 32 } == true })
    }
    static func video(_ url: URL) -> Bool {
        let p = url.path.split(separator: "/")
        return OnlinePolicy.secure(url) && url.host == origin.host && url.query == nil && url.fragment == nil && p.count == 2 && p[0] == "v" && p[1].count <= 64 && p[1].utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }
    }
    static func image(_ url: URL) -> Bool { OnlinePolicy.secure(url) && [origin.host!, cdn].contains(url.host ?? "") && url.fragment == nil }
    static func stream(_ url: URL) -> Bool { OnlinePolicy.secure(url) && url.host == cdn && url.path.hasPrefix("/videos/") && url.path.hasSuffix(".m3u8") && url.fragment == nil }
    static func resolve(_ raw: String, at page: URL) -> URL? {
        guard !raw.contains("\\"), !raw.contains(where: { $0.isWhitespace || $0.asciiValue.map { $0 < 32 } == true }), let u = URL(string: raw, relativeTo: page)?.absoluteURL, OnlinePolicy.secure(u) else { return nil }
        return u
    }
    static func next(_ candidate: URL, from current: URL) -> Bool {
        guard page(current), page(candidate) else { return false }
        func parts(_ u: URL) -> ([String], Int) {
            var p = u.path.split(separator: "/").map(String.init)
            if let n = p.last.flatMap(Int.init), p.count > (["a", "tag"].contains(p.first ?? "") ? 2 : 1) { p.removeLast(); return (p,n) }
            return (p,1)
        }
        let a = parts(current), b = parts(candidate)
        return a.0 == b.0 && b.1 == a.1 + 1
    }
}

// Bounded HTML extraction; attributes are order-independent. No webpage script runs.
enum TangxinParser {
    static func matches(_ pattern: String, _ html: String) -> [[String]] {
        guard let r = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        return r.matches(in: html, range: NSRange(html.startIndex..., in: html)).map { m in
            (0..<m.numberOfRanges).map { Range(m.range(at: $0), in: html).map { String(html[$0]) } ?? "" }
        }
    }
    static func clean(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
        for (a,b) in [("&amp;","&"),("&quot;","\""),("&#39;","'"),("&lt;","<"),("&gt;",">"),("&nbsp;"," ")] { s = s.replacingOccurrences(of: a, with: b) }
        for m in matches("&#(x[0-9a-f]+|[0-9]+);", s) {
            let n = m[1].lowercased(); let value = n.hasPrefix("x") ? UInt32(n.dropFirst(), radix:16) : UInt32(n)
            if let value, let scalar = UnicodeScalar(value) { s = s.replacingOccurrences(of:m[0], with:String(scalar)) }
        }
        return s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func attrs(_ tag: String) -> [String:String] {
        var result: [String:String] = [:]
        for m in matches("([a-zA-Z][a-zA-Z0-9_-]*)\\s*=\\s*([\"'])(.*?)\\2", tag) { result[m[1].lowercased()] = clean(m[3]) }
        return result
    }
    static func links(_ html: String) -> [([String:String],String)] {
        matches("<a\\b([^>]*)>(.*?)</a\\s*>",html).map { (attrs($0[1]), $0[2]) }
    }
    static func detailTags(_ html: String, at page: URL) -> (names:[String], links:[TangxinTag]) {
        var names: [String] = [], result: [TangxinTag] = []
        var seenNames = Set<String>(), seenURLs = Set<URL>()
        for (attributes, body) in links(html) {
            let raw = attributes["href"] ?? ""
            let url = TangxinPolicy.resolve(raw,at:page)
            guard raw.hasPrefix("/tag/") || url?.path.hasPrefix("/tag/") == true ||
                    (attributes["class"] ?? "").split(separator:" ").contains("tag") else { continue }
            let name = clean(body)
            guard !name.isEmpty else { continue }
            if seenNames.insert(name).inserted { names.append(name) }
            guard !raw.isEmpty, let url, url.path.hasPrefix("/tag/"),
                  TangxinPolicy.page(url), TangxinPolicy.permitted(name),
                  let canonical = TangxinPolicy.canonicalPage(url),
                  seenURLs.insert(canonical).inserted else { continue }
            result.append(TangxinTag(url:canonical,name:name))
        }
        return (names,result)
    }
    static func author(_ html: String, at page: URL) -> TangxinAuthor? {
        for (a,body) in links(html) where (a["class"] ?? "").split(separator:" ").contains("nickname") {
            guard let raw = a["href"], let u = TangxinPolicy.resolve(raw,at:page), TangxinPolicy.page(u), u.path.split(separator:"/").count == 2, u.path.hasPrefix("/a/") else { continue }
            let name = clean(body).trimmingCharacters(in: CharacterSet(charactersIn:"@ "))
            if !name.isEmpty, let canonical = TangxinPolicy.canonicalPage(u) { return TangxinAuthor(url:canonical,name:name) }
        }
        return nil
    }
    static func list(_ html: String, at page: URL) throws -> TangxinPage {
        guard TangxinPolicy.page(page) else { throw TangxinError.unsafe }
        var videos: [TangxinVideo] = []; var seen = Set<URL>()
        var extracted = 0, blocked = 0, malformed = 0, duplicates = 0
        let cards = matches("<article\\b([^>]*)>(.*?)</article\\s*>",html).filter { (attrs($0[1])["class"] ?? "").split(separator:" ").contains("card") }
        for card in cards {
            // Scope title/tags to this card; never inspect global tag navigation or nicknames.
            let covers = links(card[2]).filter { ($0.0["class"] ?? "").split(separator:" ").contains("cover-link") }
            guard covers.count == 1, let (a,body) = covers.first,
                  let raw = a["href"], let u = TangxinPolicy.resolve(raw,at:page), TangxinPolicy.video(u) else { malformed += 1; continue }
            let imageTag = matches("<img\\b([^>]*)>",body).first.map { attrs($0[1]) } ?? [:]
            let candidates = [a["aria-label"], imageTag["alt"]].compactMap { $0 }.map(clean).filter { !$0.isEmpty }
            let headings = matches("<h3\\b([^>]*)>(.*?)</h3\\s*>",card[2]).filter { (attrs($0[1])["class"] ?? "").split(separator:" ").contains("title") }
            // Real source uses a separate h3.title link as well as the image alt.
            let titles = headings.flatMap { links($0[2]) }.filter { link in
                link.0["href"].flatMap { TangxinPolicy.resolve($0,at:page) } == u
            }.map { clean($0.1) }.filter { !$0.isEmpty }
            guard let title = (candidates + titles).first else { malformed += 1; continue }
            extracted += 1
            let tags = links(card[2]).filter { ($0.0["href"] ?? "").hasPrefix("/tag/") }.map { clean($0.1) }
            // Check every available video title; a benign alt cannot mask a risky heading.
            guard TangxinPolicy.permitted((candidates + titles + tags).joined(separator:" ")) else { blocked += 1; continue }
            guard seen.insert(u).inserted else { duplicates += 1; continue }
            let poster = imageTag["src"].flatMap { TangxinPolicy.resolve($0,at:page) }.flatMap { TangxinPolicy.image($0) ? $0 : nil }
            videos.append(TangxinVideo(url:u,title:title,poster:poster,author:author(card[2],at:page)))
        }
        let next = links(html).compactMap { a,body -> URL? in
            guard a["rel"] == "next" || clean(body).contains("下一页") else { return nil }
            guard let href = a["href"], let url = TangxinPolicy.resolve(href,at:page), TangxinPolicy.next(url,from:page) else { return nil }
            return TangxinPolicy.canonicalPage(url)
        }.first
        // A recognized empty grid is not proof that the policy blocked anything.
        // Unknown/partial markup keeps an independently validated next link for manual advance.
        let emptyGrid = matches("<div\\b([^>]*)>\\s*</div\\s*>",html).contains { (attrs($0[1])["class"] ?? "").split(separator:" ").contains("grid") }
        let state: TangxinPageState
        if !videos.isEmpty { state = .content }
        else if malformed > 0 || (cards.isEmpty && !emptyGrid) { state = .structureChanged }
        else if blocked > 0 { state = .filtered }
        else { state = .sourceEmpty }
        return TangxinPage(videos:videos,next:next,heading:matches("<h1\\b[^>]*>(.*?)</h1>",html).first.map { clean($0[1]) },state:state,
                           report:TangxinPageReport(cards:cards.count,extracted:extracted,blocked:blocked,malformed:malformed,duplicates:duplicates))
    }
    static func detail(_ html: String, at page: URL) throws -> TangxinDetail {
        guard TangxinPolicy.video(page), let info = matches("<article\\b([^>]*)>(.*?)</article\\s*>",html).first(where: { (attrs($0[1])["class"] ?? "").split(separator:" ").contains("info") }) else { throw TangxinError.structure }
        let primary = info[2]
        guard let title = matches("<h1\\b[^>]*>(.*?)</h1>",primary).first.map({ clean($0[1]) }), !title.isEmpty else { throw TangxinError.structure }
        let parsedTags = detailTags(primary,at:page)
        let tags = parsedTags.names
        // Do not scan unrelated recommendations or the author's nickname as video metadata.
        let summary = matches("<p\\b([^>]*)>(.*?)</p>",primary).filter { (attrs($0[1])["class"] ?? "").contains("desc") }.map { clean($0[2]) }.joined(separator:"\n")
        guard TangxinPolicy.permitted(([title,summary]+tags).joined(separator:" ")) else { throw TangxinError.blocked }
        // Only an actually issued player source is accepted. Never guess CDN /<id>/index.m3u8.
        let candidates = matches("https://[^\\s\"'<>]+\\.m3u8[^\\s\"'<>]*",html).compactMap { TangxinPolicy.resolve(clean($0[0]),at:page) }.filter(TangxinPolicy.stream)
        guard let stream = candidates.first, Set(candidates).count == 1 else { throw TangxinError.structure }
        let poster = matches("<video\\b([^>]*)>",html).first.flatMap { attrs($0[1])["poster"] }.flatMap { TangxinPolicy.resolve($0,at:page) }.flatMap { TangxinPolicy.image($0) ? $0 : nil }
        return TangxinDetail(video:TangxinVideo(url:page,title:title,poster:poster,author:author(primary,at:page)),summary:summary,tags:tags,tagLinks:parsedTags.links,stream:stream)
    }
}

struct TangxinClient: Sendable {
    // Own transport: ephemeral, no cookies/cache/credentials, no redirects or TLS exceptions.
    let transport: OnlineTransport
    init(transport: OnlineTransport = OnlineTransport()) { self.transport = transport }
    func withDNSMode(_ mode: OnlineDNSMode) -> TangxinClient { TangxinClient(transport: transport.withDNSMode(mode)) }
    func document(_ url: URL) async throws -> String {
        guard TangxinPolicy.page(url) || TangxinPolicy.video(url) else { throw TangxinError.unsafe }
        let requestURL = TangxinPolicy.page(url) ? TangxinPolicy.canonicalPage(url)! : url
        let bytes = try await transport.fetch(requestURL,cap:2*1024*1024,headers:TangxinPolicy.headers,scope:OnlineMediaScope(root:TangxinPolicy.origin),context:TangxinPolicy.video(requestURL) ? .document : .discovery)
        guard let html = String(data:bytes,encoding:.utf8) else { throw TangxinError.structure }
        return html
    }
    func list(_ url: URL) async throws -> TangxinPage {
        guard let canonical = TangxinPolicy.canonicalPage(url) else { throw TangxinError.unsafe }
        // Relative links must resolve against the actual fetched directory URL.
        return try TangxinParser.list(await document(canonical),at:canonical)
    }
    func detail(_ url: URL) async throws -> TangxinDetail { try TangxinParser.detail(await document(url),at:url) }
    func image(_ url: URL) async throws -> Data {
        guard TangxinPolicy.image(url) else { throw TangxinError.unsafe }
        return try await transport.fetch(url,cap:8*1024*1024,headers:TangxinPolicy.headers,scope:OnlineMediaScope(root:url),context:.image)
    }
    func playback(_ detail: TangxinDetail) async throws -> TangxinPlayback {
        guard TangxinPolicy.stream(detail.stream), TangxinPolicy.permitted(([detail.video.title,detail.summary]+detail.tags).joined(separator:" ")) else { throw TangxinError.unsafe }
        let scope = OnlineMediaScope(root:detail.stream)
        var pending: [(URL,Int)] = [(detail.stream,0)]; var seen = Set<URL>(); var keys = Set<URL>(); var leaf = false
        while !pending.isEmpty {
            try Task.checkCancellation()
            let (url,depth) = pending.removeFirst()
            if seen.contains(url) { continue }
            guard seen.count < 12, depth <= 3 else { throw TangxinError.unsafe }
            seen.insert(url)
            let data = try await transport.fetch(url,cap:512*1024,headers:TangxinPolicy.headers,scope:scope,context:.manifest)
            let manifest = try OnlineManifest.parse(data,at:url,root:detail.stream)
            for key in manifest.keys { keys.insert(key) }
            if manifest.variants.isEmpty { leaf = true }
            pending += manifest.variants.map { ($0,depth+1) }
        }
        guard leaf, keys.count <= 12 else { throw TangxinError.unsafe }
        for key in keys {
            let bytes = try await transport.fetch(key,cap:32,headers:TangxinPolicy.headers,scope:scope,context:.key)
            guard bytes.count == 16 else { throw TangxinError.unsafe }
        }
        return TangxinPlayback(url:detail.stream,headers:TangxinPolicy.headers)
    }
}
