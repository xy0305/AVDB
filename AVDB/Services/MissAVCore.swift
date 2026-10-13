import Foundation

// Inert public metadata only. Source paths are never JavDB identities.
enum MissAVHTML {
    static let defaultDomain = "https://missav.ws"
    static let periods: [(String, String)] = [("today-hot", "今日热门"), ("weekly-hot", "本周热门"), ("monthly-hot", "本月热门")]
    static let routes = ["today-hot": "/dm301/cn/today-hot", "weekly-hot": "/dm170/cn/weekly-hot", "monthly-hot": "/dm273/cn/monthly-hot"]
    static func route(_ value: String, page: URL, base: URL) -> String? {
        guard let u = URL(string: JRHTML.text(value), relativeTo: page)?.absoluteURL,
              JRPolicy.sameHost(u, base: base), let c = URLComponents(url: u, resolvingAgainstBaseURL: true), c.fragment == nil,
              !c.path.contains(".."), !c.path.contains("%"),
              !JRHTML.matches(#"^/(?:dm[0-9]+/)?cn/(?:[a-z0-9][a-z0-9_-]*)$"#, c.path).isEmpty,
              (c.queryItems ?? []).allSatisfy({ $0.name == "page" && Int($0.value ?? "").map { $0 > 0 && $0 <= 10000 } == true }),
              (c.queryItems ?? []).count <= 1 else { return nil }
        return c.percentEncodedPath + (c.percentEncodedQuery.map { "?" + $0 } ?? "")
    }
    static func image(_ value: String?, base: URL) -> String? {
        guard let value, let u = URL(string: value, relativeTo: base)?.absoluteURL,
              u.scheme == "https", u.user == nil, u.password == nil, u.port == nil,
              JRPolicy.sameHost(u, base: base) || u.host == "fourhoi.com" else { return nil }
        return u.absoluteString
    }
    static func code(slug: String, title: String) -> String {
        var clean = slug.uppercased()
        // Only site-observed edition suffixes, no arbitrary substring guesses.
        for suffix in ["-UNCENSORED-LEAK", "-CHINESE-SUBTITLE"] {
            if clean.hasSuffix(suffix) { clean = String(clean.dropLast(suffix.count)) }
        }
        guard let key = JRPolicy.exactCode(clean) else { return "" }
        if let initial = JRPolicy.catalogueCode(title), let other = JRPolicy.exactCode(initial), other != key { return "" }
        return clean
    }
    static func tree(_ html: String) throws -> JRNode {
        guard html.utf8.count <= 4 * 1024 * 1024 else { throw JRError.message("MissAV 页面超过安全大小限制") }
        let lower = html.lowercased()
        guard !lower.contains("cf-chl-"), !lower.contains("just a moment"), !lower.contains("challenge-platform") else {
            throw JRError.message("MissAV 需要 Cloudflare 验证。未绕过验证；请稍后重试或检查来源域名。浏览器可访问不代表原生请求已获准。")
        }
        return try JRHTML.tree(html)
    }
    static func parse(_ html: String, path: String, base: URL) throws -> MissAVPage {
        let root = try tree(html)
        guard let pageURL = URL(string: path, relativeTo: base) else { throw JRError.message("无效来源路径") }
        var result = MissAVPage(), seen = Set<String>()
        for card in root.all({ $0.tag == "div" && $0.cls("thumbnail") }) {
            guard let a = card.all({ $0.tag == "a" && $0.cls("text-secondary") }).first,
                  let href = a.attrs["href"], let p = route(href, page: pageURL, base: base),
                  !p.contains("?"), seen.insert(p).inserted else { continue }
            let slug = p.split(separator: "/").last.map(String.init) ?? ""
            let img = card.all({ $0.tag == "img" }).first
            let duration = card.all({ $0.tag == "span" }).map(\.text).first { !JRHTML.matches(#"^\d{1,2}:\d{2}(?::\d{2})?$"#, $0).isEmpty } ?? ""
            result.videos.append(JRVideo(path: p, code: code(slug: slug, title: a.text), title: a.text,
                                         image: image(img?.attrs["data-src"] ?? img?.attrs["src"], base: base), subtitle: duration))
        }
        guard !result.videos.isEmpty else { throw JRError.message("MissAV 未返回可识别的排行卡片（可能站点结构变更或验证未通过）；不会显示伪造数据。") }
        for a in root.all({ $0.tag == "a" }) {
            guard let href = a.attrs["href"], let p = route(href, page: pageURL, base: base) else { continue }
            let c = URLComponents(string: p), current = URLComponents(string: path)
            let currentNumber = current?.queryItems?.first?.value.flatMap(Int.init) ?? 1
            if (a.attrs["rel"] ?? "").split(separator: " ").contains("next"), c?.path == current?.path,
               c?.queryItems?.first?.value.flatMap(Int.init) == currentNumber + 1 { result.next = p }
            if let period = periods.first(where: { c?.path.hasSuffix("/" + $0.0) == true }), c?.query == nil {
                result.routes[period.0] = p
            }
        }
        return result
    }
    static func detail(_ html: String, video: JRVideo, base: URL) throws -> MissAVDetail {
        let root = try tree(html)
        var result = MissAVDetail(video: video)
        guard root.all({ $0.attrs["id"] == "videodetails" }).first != nil || root.all({ $0.tag == "meta" && $0.attrs["property"] == "og:type" && $0.attrs["content"] == "video.movie" }).first != nil else {
            throw JRError.message("MissAV 未返回有效详情页")
        }
        if let title = root.all({ $0.tag == "h1" }).first?.text, !title.isEmpty { result.video.title = title }
        for row in root.all({ $0.tag == "div" && $0.cls("text-secondary") }) {
            guard let label = row.children.first(where: { $0.tag == "span" })?.text else { continue }
            let key = label.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "：", with: "")
            guard ["发行日期", "番号", "标题", "女优", "类型", "发行商", "导演", "标籤"].contains(key) else { continue }
            result.metadata.append(row.text)
            if key == "番号" {
                let number = row.children.first(where: { $0.cls("font-medium") })?.text ?? ""
                // A conflicting authoritative detail number disables matching.
                if let exact = JRPolicy.exactCode(number), video.code.isEmpty || exact == JRPolicy.exactCode(video.code) { result.video.code = number }
                else { result.video.code = "" }
            }
        }
        if let meta = root.all({ $0.tag == "meta" && $0.attrs["property"] == "og:image" }).first {
            result.video.image = image(meta.attrs["content"], base: base) ?? video.image
        }
        return result
    }
}
struct MissAVPage {
    var videos: [JRVideo] = []
    var next: String?
    var routes: [String: String] = [:]
}
struct MissAVDetail {
    var video: JRVideo
    var metadata: [String] = []
}
