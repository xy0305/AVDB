import Foundation

// Source identities are paths, NEVER JavDB IDs. No executable site code is evaluated.
enum JRPolicy {
    static let defaultDomain = "https://javranking.cc"
    static func domain(_ input: String) throws -> URL {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = raw.contains("://") ? raw : "https://" + raw
        guard var c = URLComponents(string: value), let host = c.host?.lowercased(),
              ["http", "https"].contains(c.scheme?.lowercased() ?? ""),
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              c.path.isEmpty || c.path == "/", c.port == nil,
              host.contains("."), !host.contains(":"), !host.contains(" "),
              host != "localhost", !host.hasSuffix(".local"),
              host.range(of: #"^[0-9.]+$"#, options: .regularExpression) == nil else {
            throw JRError.message("请输入 HTTPS 域名，不含路径、端口、账号、查询或片段。")
        }
        c.scheme = "https"; c.host = host; c.path = ""; return c.url!
    }
    static func sameHost(_ url: URL, base: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil, let h = url.host?.lowercased(), let b = base.host?.lowercased() else { return false }
        return h == b || h.hasSuffix("." + b)
    }
    static func route(_ href: String, relativeTo page: String, base: URL) -> String? {
        let raw = JRHTML.text(href)
        guard !raw.isEmpty, !raw.contains("#"), !raw.lowercased().hasPrefix("javascript:"),
              !raw.lowercased().hasPrefix("mailto:") else { return nil }
        guard var origin = URLComponents(string: page.hasPrefix("http") ? page : base.absoluteString + (page.hasPrefix("/") ? page : "/" + page)),
              let originURL = origin.url, sameHost(originURL, base: base) else { return nil }
        let url: URL
        if raw.hasPrefix("?") {
            // A query-only href replaces (never appends to) the current query.
            // Keep the directory path explicit rather than re-resolving it as a file.
            origin.percentEncodedQuery = String(raw.dropFirst())
            origin.fragment = nil
            guard let resolved = origin.url else { return nil }
            url = resolved
        } else {
            guard let resolved = URL(string: raw, relativeTo: originURL)?.absoluteURL else { return nil }
            url = resolved
        }
        guard sameHost(url, base: base), let components = URLComponents(url: url, resolvingAgainstBaseURL: true), components.fragment == nil else { return nil }
        let queryPart = components.percentEncodedQuery
        // URL.path on Darwin omits trailing directory slashes. Read the component
        // path so /zh-hans/ and pagination retain their canonical identities.
        let p = components.path
        guard p.hasPrefix("/zh-hans/"), !p.contains(".."), !p.hasSuffix(".md") else { return nil }
        let allowed = ["videos", "actors", "makers", "directors", "rankings", "explore", "pick", "most-awarded-videos", "most-awarded-actors", "most-awarded-male-actors", "search", "about", "help", "privacy", "terms", "feedback", "extension", "sponsor"]
        guard p == "/zh-hans/" || allowed.contains(p.split(separator: "/").dropFirst().first.map(String.init) ?? "") else { return nil }
        let path = p.hasSuffix("/") || p == "/" ? p : p + "/"
        guard let q = queryPart, !q.isEmpty else { return path }
        let items = q.split(separator: "&").map(String.init).filter { !$0.isEmpty }
        guard items.allSatisfy({ ["page", "q", "cat", "sort"].contains($0.split(separator: "=").first.map(String.init) ?? "") }) else { return nil }
        return path + "?" + items.joined(separator: "&")
    }
    static func image(_ value: String?, base: URL) -> String? {
        guard let value, let u = URL(string: value, relativeTo: base)?.absoluteURL,
              u.scheme == "https", u.user == nil, u.password == nil, u.port == nil else { return nil }
        let h = u.host?.lowercased() ?? ""
        // Observed public image hosts only. Third-party player sites are not image sources.
        let allowed = h == "jdbstatic.com" || h.hasSuffix(".jdbstatic.com")
            || h == "static.javranking.cc" || h == "javranking.cc"
        guard sameHost(u, base: base) || allowed else { return nil }
        return u.absoluteString
    }
    // Only complete ASCII catalogue tokens are eligible for cross-source lookup.
    // FC2-PPV is not interchangeable with FC2; no prefix/substring matching.
    static func catalogueCode(_ input: String) -> String? {
        let value = input.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX")).uppercased()
        return JRHTML.matches(#"^(FC2[-_ ]PPV[-_ ][0-9]+|[A-Z]{2,12}[-_][0-9]{2,10}|[0-9]{6}_[0-9]{3})(?=\s|$)"#, value).first?[1]
    }
    static func exactCode(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = value.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX")).uppercased()
        guard !JRHTML.matches(#"^(?:FC2[-_ ]?PPV[-_ ]?[0-9]+|[A-Z]{2,12}[-_ ]?[0-9]{2,10}|[0-9]{6}_[0-9]{3})$"#, folded).isEmpty else { return nil }
        return normalizedCode(folded)
    }
    static func normalizedCode(_ code: String) -> String {
        code.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .uppercased().filter { $0.isLetter || $0.isNumber }
    }
}
enum JRError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}
struct JRLink: Identifiable, Hashable {
    let path: String; let title: String
    var id: String { path }
}
struct JRVideo: Identifiable, Hashable {
    let path: String
    var code: String = ""
    var title: String = ""
    var image: String?
    var subtitle: String = ""
    var date: String = ""
    var score: Double = 0
    var categories: [Int] = []
    var rank: Int? = nil
    var id: String { "javranking:" + path }
}
struct JRPage {
    var title = "JAV Ranking"
    var videos: [JRVideo] = []
    var links: [JRLink] = []
    var detail: JRVideo?
    var metadata: [String] = []
    var paragraphs: [String] = []
    var images: [String] = []
    var magnets: [String] = []
    var next: String?
}
struct JRCategory: Identifiable {
    let id: Int; let name: String; let aliases: [String]
}
struct JRIndex {
    var videos: [JRVideo] = []
    var categories: [JRCategory] = []
    var entities: [JRLink] = []
    var aliases: [String: String] = [:]
    // The public explore HTML is a static first-page shell even for ?page=2.
    // Its published filter index is the data source for native pagination.
    func explorePage(number: Int) throws -> JRPage {
        let size = 20
        guard number > 0, number <= max(1, (videos.count + size - 1) / size) else {
            throw JRError.message("片库页码超出公开索引范围")
        }
        let start = (number - 1) * size
        var page = JRPage()
        page.title = "片库探索 · 第 \(number) 页"
        page.videos = Array(videos.dropFirst(start).prefix(size))
        page.links = [JRLink(path: "/zh-hans/rankings/", title: "全部排行榜")]
        if start + size < videos.count { page.next = "/zh-hans/explore/?page=\(number + 1)" }
        return page
    }
    static func parse(_ data: Data, base: URL) throws -> JRIndex {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["videos"] as? [[String: Any]] else { throw JRError.message("站点索引格式已改变") }
        var result = JRIndex(); var seen = Set<String>()
        for r in rows {
            guard let n = r["videoId"] as? Int, n > 0 else { continue }
            let path = "/zh-hans/videos/\(n)/"
            guard seen.insert(path).inserted else { continue }
            result.videos.append(JRVideo(path: path, code: r["code"] as? String ?? "", title: r["title"] as? String ?? "未提供标题", image: JRPolicy.image(r["coverUrl"] as? String, base: base), subtitle: (r["actorLinks"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.joined(separator: " · "), date: r["releaseDate"] as? String ?? "", score: (r["score"] as? NSNumber)?.doubleValue ?? 0, categories: r["categoryIds"] as? [Int] ?? []))
        }
        for r in root["categories"] as? [[String: Any]] ?? [] {
            if let id = r["id"] as? Int, let name = r["name"] as? String { result.categories.append(JRCategory(id: id, name: name, aliases: r["aliases"] as? [String] ?? [])) }
        }
        for r in root["entities"] as? [[String: Any]] ?? [] {
            guard let kind = r["kind"] as? String, ["actor", "maker", "director"].contains(kind), let slug = r["slug"] as? String, let name = r["name"] as? String,
                  slug.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else { continue }
            let path = "/zh-hans/\(kind)s/\(slug)/"
            result.entities.append(JRLink(path: path, title: name))
            result.aliases[path] = ([name] + (r["aliases"] as? [String] ?? [])).joined(separator: " ")
        }
        return result
    }
}

// Small inert HTML tree: handles quoted attributes and void tags, strips scripts/styles.
// Only known metadata/card selectors are consumed; there is no browser or JS runtime.
final class JRNode {
    let tag: String; let attrs: [String: String]
    var children: [JRNode] = []; var raw = ""
    init(_ tag: String, _ attrs: [String: String] = [:]) { self.tag = tag; self.attrs = attrs }
    private var cachedText: String?
    var text: String {
        if let cachedText { return cachedText }
        let value = JRHTML.text(raw + children.map(\.text).joined(separator: " "))
        cachedText = value
        return value
    }
    func all(_ predicate: (JRNode) -> Bool) -> [JRNode] {
        var found: [JRNode] = []
        var pending = Array(children.reversed())
        while let node = pending.popLast() {
            if predicate(node) { found.append(node) }
            pending.append(contentsOf: node.children.reversed())
        }
        return found
    }
    func has(_ name: String) -> Bool { attrs[name] != nil }
    func cls(_ value: String) -> Bool { (attrs["class"] ?? "").split(separator: " ").contains(Substring(value)) }
}
enum JRHTML {
    private static let expressions = NSCache<NSString, NSRegularExpression>()
    static func matches(_ pattern: String, _ s: String) -> [[String]] {
        let key = pattern as NSString
        let re: NSRegularExpression
        if let cached = expressions.object(forKey: key) { re = cached }
        else {
            guard let compiled = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
            expressions.countLimit = 32
            expressions.setObject(compiled, forKey: key)
            re = compiled
        }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
        }
    }
    private static let whitespace = try! NSRegularExpression(pattern: #"\s+"#)
    private static let numericEntity = try! NSRegularExpression(pattern: #"&#(x[0-9a-f]+|[0-9]+);"#, options: .caseInsensitive)
    static func text(_ input: String) -> String {
        var s = input
        if s.contains("&") {
            for (a,b) in [("&amp;","&"),("&quot;","\""),("&#39;","'"),("&apos;","'"),("&lt;","<"),("&gt;",">"),("&nbsp;"," ")] { s = s.replacingOccurrences(of: a, with: b) }
            let ns = s as NSString
            let output = NSMutableString(string: s)
            // Reverse range replacement is bounded, unlike rescanning the whole
            // string for every numeric entity (including duplicate entities).
            for m in numericEntity.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
                let value = ns.substring(with: m.range(at: 1))
                let hex = value.lowercased().hasPrefix("x")
                if let n = UInt32(hex ? String(value.dropFirst()) : value, radix: hex ? 16 : 10), let scalar = UnicodeScalar(n) {
                    output.replaceCharacters(in: m.range, with: String(scalar))
                }
            }
            s = output as String
        }
        return whitespace.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static let inertBlocks = try! NSRegularExpression(pattern: #"<(script|style|template)\b[^>]*>.*?</\1\s*>|<!--.*?-->"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
    static func tree(_ html: String) throws -> JRNode {
        let inert = inertBlocks.stringByReplacingMatches(in: html, range: NSRange(location: 0, length: (html as NSString).length), withTemplate: "")
        let root = JRNode("root"); var stack = [root]
        let void: Set<String> = ["img","input","meta","link","br","hr","source","wbr","area","embed"]
        var tokenCount = 0
        for token in tokens(inert) {
            tokenCount += 1
            if tokenCount % 1024 == 0 { try Task.checkCancellation() }
            guard tokenCount <= 500_000, stack.count <= 128 else { throw JRError.message("页面结构超出安全解析限制，请在来源浏览器查看完整内容") }
            let t = token
            if t.hasPrefix("</") {
                let name = t.dropFirst(2).prefix { $0.isLetter || $0.isNumber }.lowercased()
                if let idx = stack.lastIndex(where: { $0.tag == name }), idx > 0 { stack.removeSubrange(idx...) }
            } else if t.hasPrefix("<") {
                guard let name = matches(#"^<([a-z][a-z0-9-]*)"#,t).first?[1] else { continue }
                var attrs: [String:String] = [:]
                for m in matches(#"\s([a-z_:][a-z0-9_:.-]*)(?:\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+)))?"#,t) { attrs[m[1].lowercased()] = text(m[2].isEmpty ? (m[3].isEmpty ? m[4] : m[3]) : m[2]) }
                let n = JRNode(name.lowercased(), attrs); stack.last!.children.append(n)
                if !void.contains(n.tag) && !t.hasSuffix("/>") { stack.append(n) }
            } else { let n = JRNode("text"); n.raw = t; stack.last!.children.append(n) }
        }
        return root
    }
    // Quote-aware split. A tag regex stops at the first unquoted '>' inside a real attribute.
    static func tokens(_ html: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inTag = false
        var quote: Character?
        for ch in html {
            if inTag {
                current.append(ch)
                if let q = quote {
                    if ch == q { quote = nil }
                } else if ch == "\"" || ch == "'" {
                    quote = ch
                } else if ch == ">" {
                    result.append(current)
                    current = ""
                    inTag = false
                }
            } else if ch == "<" {
                if !current.isEmpty { result.append(current); current = "" }
                current = "<"
                inTag = true
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
    static func parse(_ html: String, path: String, base: URL) throws -> JRPage {
        guard html.utf8.count <= 12 * 1024 * 1024 else { throw JRError.message("公开页面超出安全大小限制") }
        let root = try tree(html); var page = JRPage()
        guard let main = root.all({ $0.tag == "main" }).first else { throw JRError.message("站点未返回公开内容，可能受到访问限制。请稍后重试。") }
        page.title = main.all { $0.tag == "h1" }.first?.text ?? "JAV Ranking"
        var seen = Set<String>()
        for node in main.all({ $0.has("data-video-card") || $0.cls("video-card") }) {
            guard let a = node.all({ $0.has("data-video-card-title") }).first,
                  let href = a.attrs["href"], let route = JRPolicy.route(href, relativeTo: path, base: base), route.contains("/videos/"), seen.insert(route).inserted else { continue }
            page.videos.append(JRVideo(path: route, code: node.all { $0.has("data-video-card-code") }.first?.text ?? "", title: a.text, image: JRPolicy.image(node.all { $0.tag == "img" }.first?.attrs["src"], base: base), subtitle: node.all { $0.has("data-video-card-actors") }.first?.text ?? "", rank: node.all { $0.cls("video-card__rank") }.first.flatMap { Int($0.text) }))
        }
        var linkSeen = Set<String>()
        // Public site navigation lives in header/footer, outside <main>.
        // The same route policy excludes account, external and executable links.
        for a in root.all({ $0.tag == "a" }) {
            guard let href = a.attrs["href"], let route = JRPolicy.route(href, relativeTo: path, base: base), !route.contains("/videos/"), route != path else { continue }
            let title = a.text.isEmpty ? (a.attrs["aria-label"] ?? route) : a.text
            // Numeric pagination and the Next button share a URL. Inspect every
            // pagination anchor before deduplicating ordinary navigation links.
            if route.contains("page=") {
                let label = title + (a.attrs["aria-label"] ?? "")
                if a.attrs["rel"] == "next" || label.contains("下一") { page.next = route }
                continue
            }
            guard linkSeen.insert(route).inserted else { continue }
            page.links.append(JRLink(path: route, title: title))
        }
        for m in matches(#"<script[^>]*type=[\"']application/ld\+json[\"'][^>]*>(.*?)</script>"#,html) {
            guard let data = m[1].data(using: .utf8), let j = try? JSONSerialization.jsonObject(with: data) as? [String:Any] else { continue }
            if j["@type"] as? String == "Movie" {
                page.detail = JRVideo(path: path, code: j["alternateName"] as? String ?? "", title: j["name"] as? String ?? page.title, image: JRPolicy.image(j["image"] as? String, base: base), date: j["datePublished"] as? String ?? "")
                page.metadata = [j["datePublished"] as? String, j["duration"] as? String].compactMap { $0 }
                if let actors = j["actor"] as? [[String:Any]] { page.metadata.append(actors.compactMap { $0["name"] as? String }.joined(separator: " · ")) }
            }
            if j["@type"] as? String == "ItemList", let entries = j["itemListElement"] as? [[String:Any]] {
                var ranked: [JRVideo] = []
                var rankedPaths = Set<String>()
                for entry in entries {
                    guard let href = entry["url"] as? String,
                          let route = JRPolicy.route(href, relativeTo: path, base: base), route.contains("/videos/"),
                          let title = entry["name"] as? String, rankedPaths.insert(route).inserted else { continue }
                    let card = page.videos.first { $0.path == route }
                    ranked.append(JRVideo(path: route, code: JRPolicy.catalogueCode(title) ?? card?.code ?? "", title: title,
                                          image: card?.image, subtitle: card?.subtitle ?? "", rank: entry["position"] as? Int))
                }
                if !ranked.isEmpty {
                    page.videos = ranked + page.videos.filter { !rankedPaths.contains($0.path) }
                }
                let links = entries.compactMap { r -> JRLink? in
                    guard let u = r["url"] as? String, let p = JRPolicy.route(u, relativeTo: path, base: base), !p.contains("/videos/"), let title = r["name"] as? String else { return nil }; return JRLink(path: p, title: title)
                }
                if !links.isEmpty { page.links = links + page.links.filter { a in !links.contains(where: { $0.path == a.path }) } }
            }
        }
        if path.contains("/videos/") {
            page.paragraphs = main.all { $0.tag == "blockquote" || $0.cls("review-card") || $0.cls("review-list") }.map(\.text).filter { !$0.isEmpty }
            page.magnets = Array(Set(main.all { $0.tag == "a" }.compactMap { $0.attrs["href"] }.filter { $0.hasPrefix("magnet:?xt=urn:btih:") })).sorted()
            page.images = Array(Set(main.all { $0.tag == "img" }.compactMap { JRPolicy.image($0.attrs["src"], base: base) })).sorted()
            page.metadata += main.all { $0.tag == "dd" || $0.cls("facts-panel__row") }.map(\.text).filter { !$0.isEmpty }
        } else if page.videos.isEmpty && page.links.isEmpty || ["about","help","privacy","terms","feedback","extension","sponsor"].contains(path.split(separator: "/").dropFirst().first.map(String.init) ?? "") {
            page.paragraphs = main.all { ["h2","h3","p","li"].contains($0.tag) }.map(\.text).filter { !$0.isEmpty && $0.count < 3000 }
        }
        return page
    }
}
