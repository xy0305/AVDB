import Foundation

// JavLibrary is an independent source. IDs here are NEVER JavDB IDs.
enum JLRanking: String, CaseIterable, Identifiable {
    case mostWanted, highlyRated, actors
    var id: String { rawValue }
    var title: String { switch self { case .mostWanted: return "最想要"; case .highlyRated: return "高评价"; case .actors: return "演员排行榜" } }
    var route: String { switch self { case .mostWanted: return "vl_mostwanted.php"; case .highlyRated: return "vl_bestrated.php"; case .actors: return "star_mostfav.php" } }
}
struct JLFilter: Equatable, Identifiable {
    let value: String
    let title: String
    var id: String { value }
}
struct JLVideo: Identifiable, Equatable {
    let id: String
    let code: String
    let title: String
    let image: URL?
    let url: URL
    let position: Int // page-local source order, not a fabricated global rank
}
struct JLActor: Identifiable, Equatable {
    let id: String
    let name: String
    let image: URL?
    let url: URL
    let rank: Int?
}
struct JLPage {
    var title = "JavLibrary"
    var filters: [JLFilter] = []
    var videos: [JLVideo] = []
    var actors: [JLActor] = []
    var next: URL?
}
enum JLError: LocalizedError {
    case verification, http(Int), invalidURL, unsupportedHTML
    var errorDescription: String? {
        switch self {
        case .verification: return "JavLibrary 要求浏览器验证。请使用可见浏览器正常完成验证；未通过前无法加载榜单。"
        case .http(let status): return "JavLibrary 请求失败（HTTP \(status)）"
        case .invalidURL: return "JavLibrary 来源地址无效"
        case .unsupportedHTML: return "JavLibrary 未返回受支持的榜单结构，不会将验证页面当作空榜单。"
        }
    }
}
enum JLPolicy {
    static let canonical = URL(string: "https://www.javlibrary.com")!
    static func domain(_ input: String) throws -> URL {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c = URLComponents(string: value.contains("://") ? value : "https://" + value),
              c.scheme == "https", let host = c.host, host.contains("."),
              !host.hasSuffix(".local"), !host.contains(":"),
              host.range(of: #"^[0-9.]+$"#, options: .regularExpression) == nil,
              c.user == nil, c.password == nil, c.port == nil,
              c.query == nil, c.fragment == nil, c.path.isEmpty || c.path == "/",
              let url = URL(string: "https://" + host.lowercased()) else { throw JLError.invalidURL }
        return url
    }
    static func route(_ kind: JLRanking, mode: String? = nil, page: Int = 1, base: URL = canonical) -> URL {
        var c = URLComponents(url: base.appendingPathComponent("cn/" + kind.route), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = []
        if kind != .actors, let mode, ["0", "1", "2"].contains(mode) { items.append(URLQueryItem(name: "mode", value: mode)) }
        if kind != .actors { items.append(URLQueryItem(name: "page", value: String(max(1, page)))) }
        c.queryItems = items.isEmpty ? nil : items
        return c.url!
    }
    static func sourceURL(_ raw: String, relativeTo page: URL) -> URL? {
        guard let url = URL(string: raw, relativeTo: page)?.absoluteURL,
              url.scheme == "https", url.host?.lowercased() == page.host?.lowercased(),
              url.user == nil, url.password == nil, url.port == page.port,
              url.path.hasPrefix("/cn/") else { return nil }
        return url
    }
    static func image(_ raw: String?, page: URL) -> URL? {
        guard let raw, let url = URL(string: raw, relativeTo: page)?.absoluteURL,
              url.scheme == "https", url.user == nil, url.password == nil else { return nil }
        return url
    }
    static func validate(_ data: Data, response: HTTPURLResponse) throws -> String {
        let html = String(decoding: data, as: UTF8.self)
        let lower = html.lowercased()
        if response.value(forHTTPHeaderField: "cf-mitigated")?.lowercased() == "challenge" ||
            lower.contains("/cdn-cgi/challenge-platform/") || lower.contains("cf-chl-") ||
            lower.contains("<title>just a moment") || lower.contains("<title>请稍候") {
            throw JLError.verification
        }
        guard (200..<300).contains(response.statusCode) else { throw JLError.http(response.statusCode) }
        guard data.count <= 12 * 1024 * 1024 else { throw JLError.unsupportedHTML }
        return html
    }
}
enum JLHTML {
    static func parse(_ html: String, pageURL: URL) throws -> JLPage {
        guard html.utf8.count <= 12 * 1024 * 1024 else { throw JLError.unsupportedHTML }
        let root = try JRHTML.tree(html)
        var page = JLPage()
        page.title = root.all { $0.tag == "title" }.first?.text ?? page.title
        for select in root.all({ $0.tag == "select" && ($0.attrs["onchange"] ?? "").contains("mode=") }) {
            page.filters = select.all { $0.tag == "option" }.compactMap { option in
                guard let value = option.attrs["value"], ["0", "1", "2"].contains(value) else { return nil }
                return JLFilter(value: value, title: option.text)
            }
        }
        var seen = Set<String>()
        for card in root.all({ $0.cls("video") }) {
            guard let rawID = card.attrs["id"], rawID.hasPrefix("vid_"),
                  let anchor = card.all({ $0.tag == "a" && $0.has("href") }).first,
                  let href = anchor.attrs["href"], let url = JLPolicy.sourceURL(href, relativeTo: pageURL),
                  let code = card.all({ $0.cls("id") }).first?.text,
                  JRPolicy.exactCode(code) != nil, seen.insert(rawID).inserted else { continue }
            page.videos.append(JLVideo(id: String(rawID.dropFirst(4)), code: code,
                title: card.all({ $0.cls("title") }).first?.text ?? anchor.attrs["title"] ?? code,
                image: JLPolicy.image(card.all({ $0.tag == "img" }).first?.attrs["src"], page: pageURL),
                url: url, position: page.videos.count + 1))
        }
        seen.removeAll()
        for card in root.all({ $0.cls("searchitem") }) {
            guard let anchor = card.all({ $0.tag == "a" && ($0.attrs["href"] ?? "").contains("vl_star.php?") }).first,
                  let href = anchor.attrs["href"], let url = JLPolicy.sourceURL(href, relativeTo: pageURL),
                  let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "s" })?.value,
                  !id.isEmpty, !anchor.text.isEmpty, seen.insert(id).inserted else { continue }
            let rankText = card.all { $0.tag == "h3" }.first?.text ?? ""
            let rank = JRHTML.matches(#"#\s*(\d+)"#, rankText).first.flatMap { Int($0[1]) }
            page.actors.append(JLActor(id: id, name: anchor.text,
                image: JLPolicy.image(card.all({ $0.tag == "img" }).first?.attrs["src"], page: pageURL), url: url, rank: rank))
        }
        let current = URLComponents(url: pageURL, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "page" }).flatMap { Int($0.value ?? "") } ?? 1
        if let next = root.all({ $0.tag == "a" && $0.cls("page") && $0.cls("next") }).first?.attrs["href"],
           let url = JLPolicy.sourceURL(next, relativeTo: pageURL), url.path == pageURL.path,
           URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "page" && (Int($0.value ?? "") ?? 0) > current }) == true {
            page.next = url
        }
        guard !page.videos.isEmpty || !page.actors.isEmpty else { throw JLError.unsupportedHTML }
        return page
    }
}
