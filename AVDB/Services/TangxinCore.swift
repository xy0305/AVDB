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
struct TangxinPage: Sendable {
    let videos: [TangxinVideo]
    let next: URL?
    let heading: String?
}
struct TangxinDetail: Sendable {
    let video: TangxinVideo
    let summary: String
    let tags: [String]
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
        let p = url.path.split(separator: "/").map(String.init)
        if p.first == "featured" { return p.count == 1 || (p.count == 2 && Int(p[1]).map { $0 > 1 } == true) }
        return p.first == "a" && (p.count == 2 || (p.count == 3 && Int(p[2]).map { $0 > 1 } == true)) && slug(p[1])
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
            if let n = p.last.flatMap(Int.init), p.count > (p.first == "a" ? 2 : 1) { p.removeLast(); return (p,n) }
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
    static func author(_ html: String, at page: URL) -> TangxinAuthor? {
        for (a,body) in links(html) where (a["class"] ?? "").split(separator:" ").contains("nickname") {
            guard let raw = a["href"], let u = TangxinPolicy.resolve(raw,at:page), TangxinPolicy.page(u), u.path.split(separator:"/").count == 2, u.path.hasPrefix("/a/") else { continue }
            let name = clean(body).trimmingCharacters(in: CharacterSet(charactersIn:"@ "))
            if !name.isEmpty { return TangxinAuthor(url:u,name:name) }
        }
        return nil
    }
    static func list(_ html: String, at page: URL) throws -> TangxinPage {
        guard TangxinPolicy.page(page) else { throw TangxinError.unsafe }
        var videos: [TangxinVideo] = []; var seen = Set<URL>()
        let cards = matches("<article\\b([^>]*)>(.*?)</article\\s*>",html).filter { (attrs($0[1])["class"] ?? "").split(separator:" ").contains("card") }
        for card in cards {
            for (a,body) in links(card[2]) where (a["class"] ?? "").split(separator:" ").contains("cover-link") {
                guard let raw = a["href"], let u = TangxinPolicy.resolve(raw,at:page), TangxinPolicy.video(u), seen.insert(u).inserted else { continue }
                let imageTag = matches("<img\\b([^>]*)>",body).first.map { attrs($0[1]) } ?? [:]
                let title = clean(a["aria-label"] ?? imageTag["alt"] ?? "")
                let tags = links(card[2]).filter { ($0.0["href"] ?? "").hasPrefix("/tag/") }.map { clean($0.1) }
                guard !title.isEmpty, TangxinPolicy.permitted(([title] + tags).joined(separator:" ")) else { continue }
                let poster = imageTag["src"].flatMap { TangxinPolicy.resolve($0,at:page) }.flatMap { TangxinPolicy.image($0) ? $0 : nil }
                videos.append(TangxinVideo(url:u,title:title,poster:poster,author:author(card[2],at:page)))
            }
        }
        let next = links(html).compactMap { a,body -> URL? in
            guard a["rel"] == "next" || clean(body).contains("下一页") else { return nil }
            guard let href = a["href"], let url = TangxinPolicy.resolve(href,at:page), TangxinPolicy.next(url,from:page) else { return nil }
            return url
        }.first
        // Empty known grids are legitimate; challenge/changed markup is not a silent end.
        guard !cards.isEmpty || html.contains("class=\"grid\"") else { throw TangxinError.structure }
        return TangxinPage(videos:videos,next:next,heading:matches("<h1\\b[^>]*>(.*?)</h1>",html).first.map { clean($0[1]) })
    }
    static func detail(_ html: String, at page: URL) throws -> TangxinDetail {
        guard TangxinPolicy.video(page), let info = matches("<article\\b([^>]*)>(.*?)</article\\s*>",html).first(where: { (attrs($0[1])["class"] ?? "").split(separator:" ").contains("info") }) else { throw TangxinError.structure }
        let primary = info[2]
        guard let title = matches("<h1\\b[^>]*>(.*?)</h1>",primary).first.map({ clean($0[1]) }), !title.isEmpty else { throw TangxinError.structure }
        let tags = links(primary).filter { ($0.0["href"] ?? "").hasPrefix("/tag/") }.map { clean($0.1) }
        // Do not scan unrelated recommendations or the author's nickname as video metadata.
        let summary = matches("<p\\b([^>]*)>(.*?)</p>",primary).filter { (attrs($0[1])["class"] ?? "").contains("desc") }.map { clean($0[2]) }.joined(separator:"\n")
        guard TangxinPolicy.permitted(([title,summary]+tags).joined(separator:" ")) else { throw TangxinError.blocked }
        // Only an actually issued player source is accepted. Never guess CDN /<id>/index.m3u8.
        let candidates = matches("https://[^\\s\"'<>]+\\.m3u8[^\\s\"'<>]*",html).compactMap { TangxinPolicy.resolve(clean($0[0]),at:page) }.filter(TangxinPolicy.stream)
        guard let stream = candidates.first, Set(candidates).count == 1 else { throw TangxinError.structure }
        let poster = matches("<video\\b([^>]*)>",html).first.flatMap { attrs($0[1])["poster"] }.flatMap { TangxinPolicy.resolve($0,at:page) }.flatMap { TangxinPolicy.image($0) ? $0 : nil }
        return TangxinDetail(video:TangxinVideo(url:page,title:title,poster:poster,author:author(primary,at:page)),summary:summary,tags:tags,stream:stream)
    }
}

struct TangxinClient: Sendable {
    // Own transport: ephemeral, no cookies/cache/credentials, no redirects or TLS exceptions.
    let transport: OnlineTransport
    init(transport: OnlineTransport = OnlineTransport()) { self.transport = transport }
    func document(_ url: URL) async throws -> String {
        guard TangxinPolicy.page(url) || TangxinPolicy.video(url) else { throw TangxinError.unsafe }
        let bytes = try await transport.fetch(url,cap:2*1024*1024,headers:TangxinPolicy.headers,scope:OnlineMediaScope(root:TangxinPolicy.origin))
        guard let html = String(data:bytes,encoding:.utf8) else { throw TangxinError.structure }
        return html
    }
    func list(_ url: URL) async throws -> TangxinPage { try TangxinParser.list(await document(url),at:url) }
    func detail(_ url: URL) async throws -> TangxinDetail { try TangxinParser.detail(await document(url),at:url) }
    func image(_ url: URL) async throws -> Data {
        guard TangxinPolicy.image(url) else { throw TangxinError.unsafe }
        return try await transport.fetch(url,cap:8*1024*1024,headers:TangxinPolicy.headers,scope:OnlineMediaScope(root:url))
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
            let data = try await transport.fetch(url,cap:512*1024,headers:TangxinPolicy.headers,scope:scope)
            let manifest = try OnlineManifest.parse(data,at:url,root:detail.stream)
            for key in manifest.keys { keys.insert(key) }
            if manifest.variants.isEmpty { leaf = true }
            pending += manifest.variants.map { ($0,depth+1) }
        }
        guard leaf, keys.count <= 12 else { throw TangxinError.unsafe }
        for key in keys {
            let bytes = try await transport.fetch(key,cap:32,headers:TangxinPolicy.headers,scope:scope)
            guard bytes.count == 16 else { throw TangxinError.unsafe }
        }
        return TangxinPlayback(url:detail.stream,headers:TangxinPolicy.headers)
    }
}
