import Foundation
import Combine
import WebKit

// Build 353: avfan public-page scraping layer, ported from AVFan's
// SiteClient/HTMLParser subset (search + cards + detail + magnets +
// cast search). Used ONLY as the matching layer for the five external
// ranking boards (DMM / JAV Ranking / MissAV / JAVLibrary / 中指通):
// board entries match avfan by exact code, covers come from avfan,
// taps open the avfan detail — the boards make zero JavDB requests.
//
// Red lines (same as AVFan): public pages only; never /api/,
// /autocomplete, /user/ or any login-gated account page; no UA
// spoofing beyond the site's own mobile Safari string; serial lanes
// with spacing; 403/429 stops and degrades instead of retry loops.
// Login (Build 353 supplement) only makes these public fetches carry
// the user's own session cookies — it never widens what is fetched,
// and credentials pass through the real sign-in page in a WKWebView
// only; nothing about the password is stored or sent by this code.

struct AvfanNamedLink: Identifiable, Hashable, Codable {
    var name: String
    var href: String
    var kind: String?
    var id: String { href + "|" + name }
}

struct AvfanMovieCard: Identifiable, Hashable, Codable {
    var pathID: String
    var href: String
    var code: String?
    var title: String
    var coverURL: String?
    var date: String?
    var ratingText: String?
    var badges: [String]
    var canPlay: Bool
    var id: String { pathID }
    var displayCode: String { code ?? pathID }
    /// Catalog titles carry the code as a prefix; the detail page's
    /// own title does not. Placeholders use this so the hero title
    /// never changes text when the real detail lands.
    var titleWithoutCodePrefix: String {
        guard let code, !code.isEmpty, title.hasPrefix(code) else { return title }
        let rest = title.dropFirst(code.count)
            .drop(while: { $0 == " " || $0 == "　" || $0 == "-" || $0 == "－" })
        return rest.isEmpty ? title : String(rest)
    }
}

struct AvfanMagnetItem: Identifiable, Hashable {
    var url: String
    var name: String
    var sizeText: String?
    var sizeKB: Int?
    var fileCount: Int?
    var date: String?
    var tags: [String]
    var id: String { url }
    var displayMeta: String {
        var parts: [String] = []
        if let date, !date.isEmpty { parts.append(date) }
        if let fileCount { parts.append("\(fileCount)个文件") }
        if let sizeText, !sizeText.isEmpty { parts.append(sizeText) }
        return parts.joined(separator: " · ")
    }
}

struct AvfanMovieDetail: Hashable {
    var pathID: String
    var pageURL: String
    var code: String?
    var title: String
    var coverURL: String?
    var summary: String?
    var releaseDate: String?
    var duration: String?
    var rating: Double?
    var ratingCount: Int?
    var makers: [AvfanNamedLink]
    var publishers: [AvfanNamedLink]
    var directors: [AvfanNamedLink]
    var series: [AvfanNamedLink]
    var casts: [AvfanNamedLink]
    var tags: [AvfanNamedLink]
    var magnets: [AvfanMagnetItem]
    var alsoStarred: [AvfanMovieCard] = []
    var relatedWorks: [AvfanMovieCard] = []
    var displayCode: String { code ?? pathID }
    var displayTitle: String { title.isEmpty ? displayCode : title }
}

struct AvfanCastCard: Identifiable, Hashable {
    var name: String
    var href: String
    var avatarURL: String?
    var countText: String?
    var id: String { href }
    var pathID: String { href.split(separator: "/").last.map(String.init) ?? href }
}

struct AvfanCastProfile: Hashable {
    var name: String = ""
    var avatarURL: String? = nil
    var worksCount: Int? = nil
    var works: [AvfanMovieCard] = []
}

enum AvfanError: LocalizedError {
    case blocked(status: Int)
    case transport(String)
    case emptyPage
    var errorDescription: String? {
        switch self {
        case .blocked(let status): return "avfan 暂时拒绝访问（HTTP \(status)），已暂停匹配"
        case .transport(let text): return text
        case .emptyPage: return "avfan 页面没有可解析的内容"
        }
    }
}

// MARK: - Cover choice (avfan's own images only)

enum AvfanCoverPolicy {
    static func preferred(from candidates: [String]) -> String? {
        let unique = uniqued(candidates.compactMap(normalized(_:)))
        guard !unique.isEmpty else { return nil }
        return unique.max(by: { score($0) < score($1) })
    }

    static func collect(from html: String) -> [String] {
        var found: [String] = []
        let patterns = [
            "<img[^>]+src=\"([^\"]+)\"",
            "<img[^>]+data-src=\"([^\"]+)\"",
            "<img[^>]+data-original=\"([^\"]+)\"",
            "<img[^>]+src='([^']+)'",
            "<img[^>]+data-src='([^']+)'",
            "<img[^>]+data-original='([^']+)'",
            "(https?://[^\"'\\s<>]+c1\\.avfan\\.com[^\"'\\s<>]*)",
        ]
        for pattern in patterns {
            found.append(contentsOf: AvfanHTMLParser.allMatches(pattern, in: html))
        }
        return uniqued(found.compactMap(normalized(_:)))
    }

    static func preferred(in html: String) -> String? {
        preferred(from: collect(from: html))
    }

    private static func score(_ value: String) -> Int {
        let lower = value.lowercased()
        if lower.contains("/covers/") { return 200 }        // avfan's own cover
        if lower.contains("c1.avfan.com") { return 190 }
        if lower.contains("dmm.co.jp") || lower.contains("fanza") { return 100 }
        return 50
    }

    private static func normalized(_ raw: String) -> String? {
        var value = AvfanHTMLParser.unescape(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("//") { value = "https:" + value }
        guard value.hasPrefix("http://") || value.hasPrefix("https://") else { return nil }
        let lower = value.lowercased()
        guard !lower.hasSuffix(".svg"), !lower.contains("favicon"), !lower.contains("/logo") else { return nil }
        guard lower.contains(".jpg") || lower.contains(".jpeg") || lower.contains(".png") || lower.contains(".webp") else { return nil }
        return value
    }

    private static func uniqued(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

// MARK: - HTML parsing (ported from AVFan's HTMLParser, trimmed)

enum AvfanHTMLParser {
    static let localePrefixes = ["zh-CN", "zh-TW", "en", "ja", "ko", "th"]
    static let locale = "zh-CN"

    static func unescape(_ raw: String) -> String {
        var text = raw
        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&nbsp;", " "),
            ("&rarr;", "→"),
        ]
        for (entity, value) in entities {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        text = text.replacingOccurrences(of: "&#x([0-9a-fA-F]+);", with: "{$1}", options: .regularExpression)
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches.reversed() {
                if let range = Range(match.range(at: 1), in: text),
                   let value = UInt32(text[range]),
                   let scalar = UnicodeScalar(value) {
                    text.replaceSubrange(Range(match.range, in: text)!, with: String(Character(scalar)))
                }
            }
        }
        return text
    }

    static func stripTags(_ html: String) -> String {
        let noTags = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return unescape(noTags).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func attribute(_ name: String, in tag: String) -> String? {
        for pattern in ["\(name)=\"([^\"]*)\"", "\(name)='([^']*)'"] {
            if let match = firstMatch(pattern, in: tag) {
                return unescape(match)
            }
        }
        return nil
    }

    static func firstMatch(_ pattern: String, in text: String, options: NSRegularExpression.Options = [.caseInsensitive, .dotMatchesLineSeparators]) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    static func allMatches(_ pattern: String, in text: String, group: Int = 1) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > group, let r = Range(match.range(at: group), in: text) else { return nil }
            return String(text[r])
        }
    }

    /// Parsing is pure CPU work over large HTML; run it off the main actor.
    static func detached<T>(_ work: @escaping @Sendable () -> T) async -> T {
        await Task.detached(priority: .userInitiated, operation: work).value
    }

    static func stripLocale(_ path: String) -> String {
        var p = path
        if p.hasPrefix("https://avfan.com") { p = String(p.dropFirst("https://avfan.com".count)) }
        if p.hasPrefix("/") { p.removeFirst() }
        for prefix in localePrefixes where p.hasPrefix(prefix + "/") {
            p = String(p.dropFirst(prefix.count + 1))
            break
        }
        return p
    }

    static func isBlocked(_ html: String, status: Int?) -> Bool {
        if let status, status == 403 || status == 429 || status == 503 { return true }
        let lowered = html.lowercased()
        if lowered.contains("just a moment") { return true }
        if lowered.contains("cf-browser-verification") { return true }
        if lowered.contains("attention required") && lowered.contains("cloudflare") { return true }
        if lowered.contains("why have i been blocked") { return true }
        return false
    }

    static func hasCatalogItems(_ html: String) -> Bool {
        if firstMoviePath(in: html) != nil { return true }
        if html.contains("data-magnet=") || html.contains("magnet:?") { return true }
        if html.contains("class=\"movie-info") || html.contains("class='movie-info") { return true }
        if html.contains("/casts/") && html.range(of: "/casts/[A-Za-z0-9]{8}", options: .regularExpression) != nil {
            return true
        }
        return false
    }

    static func firstMoviePath(in html: String) -> String? {
        firstMatch("(?:https://avfan\\.com)?(/?(?:zh-CN|zh-TW|en|ja|ko|th)?/movies/[A-Za-z0-9]{8})", in: html)
    }

    static func pathID(from href: String) -> String? {
        firstMatch("/movies/([A-Za-z0-9]{8})(?:[/?#]|$)", in: href)
    }

    static func absoluteURL(_ href: String) -> String {
        if href.hasPrefix("http://") || href.hasPrefix("https://") { return href }
        if href.hasPrefix("/") { return "https://avfan.com" + href }
        return "https://avfan.com/\(locale)/" + href
    }

    static func extractCode(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = firstMatch("\\[([A-Z0-9]{2,10}-[A-Z0-9]{2,12})\\]", in: trimmed, options: [.caseInsensitive]) {
            return match.uppercased()
        }
        if let match = firstMatch("^\\s*([A-Z]{2,10}-?\\d{2,8}(?:-[A-Z0-9]+)?)\\s*$", in: trimmed, options: [.caseInsensitive]) {
            return match.uppercased()
        }
        if let match = firstMatch("\\b(FC2[-_]?PPV[-_]?\\d{5,8})\\b", in: trimmed, options: [.caseInsensitive]) {
            return match.uppercased().replacingOccurrences(of: "_", with: "-")
        }
        if let match = firstMatch("\\b([A-Z]{2,10}-\\d{2,8})\\b", in: trimmed, options: [.caseInsensitive]) {
            return match.uppercased()
        }
        if let match = firstMatch("\\b([A-Za-z][A-Za-z0-9]*(?:\\.[A-Za-z0-9]+)*\\.\\d{4}\\.\\d{2}\\.\\d{2})\\b", in: trimmed) {
            return match
        }
        return nil
    }

    // MARK: Cards

    static func movieCards(in html: String) -> [AvfanMovieCard] {
        var cards: [AvfanMovieCard] = []
        guard let regex = try? NSRegularExpression(
            pattern: "<a([^>]*href=\"([^\"]*/movies/[A-Za-z0-9]{8})[^\"]*\"[^>]*)>(.*?)</a>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }

        let ns = html as NSString
        let range = NSRange(location: 0, length: ns.length)
        for match in regex.matches(in: html, range: range) {
            let tag = ns.substring(with: match.range(at: 1))
            let href = unescape(ns.substring(with: match.range(at: 2)))
            let inner = ns.substring(with: match.range(at: 3))
            guard let id = pathID(from: href) else { continue }

            let titleAttr = attribute("title", in: tag).map(unescape) ?? ""
            let imgSrc = firstMatch("<img[^>]+(?:data-src|data-original|src)=\"([^\"]+)\"", in: inner)
            let imgAlt = firstMatch("<img[^>]+alt=\"([^\"]*)\"", in: inner).map(unescape) ?? ""
            let bold = firstMatch("class=\"[^\"]*font-bold[^\"]*\"[^>]*>([^<]+)", in: inner)
                ?? firstMatch("<strong[^>]*>([^<]+)</strong>", in: inner)
            let sub = firstMatch("class=\"[^\"]*text-sm[^\"]*\"[^>]*>([^<]+)", in: inner)
                ?? firstMatch("<span class=\"[^\"]*line-clamp-1[^\"]*\"[^>]*>([^<]+)", in: inner)
            let date = firstMatch("class=\"[^\"]*text-xs[^\"]*\"[^>]*>\\s*(\\d{4}-\\d{2}-\\d{2})", in: inner)
            let rating = firstMatch("(\\d+(?:\\.\\d+)?分[^<]*)", in: inner)

            let code = extractCode(from: bold ?? "") ?? extractCode(from: titleAttr) ?? extractCode(from: imgAlt)
            var title = stripTags(sub ?? "")
            if title.isEmpty {
                if let code, titleAttr.contains(code) {
                    title = titleAttr.replacingOccurrences(of: "[\(code)]", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                } else if !titleAttr.isEmpty {
                    title = titleAttr
                } else {
                    title = imgAlt
                }
            }
            if title.hasPrefix("["), let close = title.firstIndex(of: "]") {
                title = title[title.index(after: close)...].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            var badges: [String] = []
            for badge in allMatches("class=\"[^\"]*sub-tag[^\"]*\"[^>]*>([^<]+)", in: inner) {
                let label = stripTags(badge)
                if !label.isEmpty { badges.append(label) }
            }
            if inner.contains("可播放") { badges.append("可播放") }
            if inner.contains("最新上架") { badges.append("最新上架") }

            let incoming = AvfanMovieCard(
                pathID: id,
                href: href,
                code: code,
                title: title,
                coverURL: AvfanCoverPolicy.preferred(from: AvfanCoverPolicy.collect(from: inner) + [imgSrc].compactMap { $0 }.map { absoluteURL($0) }),
                date: date,
                ratingText: rating.map(stripTags),
                badges: Array(Set(badges)),
                canPlay: inner.contains("可播放")
            )

            if let index = cards.firstIndex(where: { $0.pathID == id }) {
                if cards[index].code == nil { cards[index].code = incoming.code }
                if cards[index].title.isEmpty { cards[index].title = incoming.title }
                cards[index].coverURL = AvfanCoverPolicy.preferred(from: [cards[index].coverURL, incoming.coverURL].compactMap { $0 }) ?? cards[index].coverURL
                if cards[index].date == nil { cards[index].date = incoming.date }
                if cards[index].ratingText == nil { cards[index].ratingText = incoming.ratingText }
                if incoming.canPlay { cards[index].canPlay = true }
                var merged = Set(cards[index].badges)
                merged.formUnion(incoming.badges)
                cards[index].badges = Array(merged)
            } else {
                cards.append(incoming)
            }
        }

        // Ranking-style pages split cover and title into separate anchors:
        // merge covers into the cards that lack one.
        if let coverRegex = try? NSRegularExpression(
            pattern: "<a([^>]*href=\"([^\"]*/movies/[A-Za-z0-9]{8})[^\"]*\"[^>]*)>[^<]*<img[^>]+src=\"([^\"]+)\"[^>]*>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) {
            for match in coverRegex.matches(in: html, range: range) {
                let href = unescape(ns.substring(with: match.range(at: 2)))
                let src = unescape(ns.substring(with: match.range(at: 3)))
                guard let id = pathID(from: href) else { continue }
                if let index = cards.firstIndex(where: { $0.pathID == id }) {
                    cards[index].coverURL = AvfanCoverPolicy.preferred(from: [cards[index].coverURL, absoluteURL(src)].compactMap { $0 }) ?? cards[index].coverURL
                }
            }
        }
        // Sibling-cover pass: nearest image after (then before) the anchor,
        // stopping at neighbouring anchors so covers are never stolen.
        for index in cards.indices where cards[index].coverURL == nil {
            guard let anchorRange = html.range(of: cards[index].href) else { continue }
            var window = String(html[anchorRange.upperBound...].prefix(1500))
            if let nextAnchor = window.range(of: "<a ", options: .caseInsensitive) {
                window = String(window[..<nextAnchor.lowerBound])
            }
            if let found = AvfanCoverPolicy.preferred(in: window) {
                cards[index].coverURL = found
                continue
            }
            let beforeText = String(html[..<anchorRange.lowerBound].suffix(1500))
            var bWindow = beforeText
            if let prevClose = beforeText.range(of: "</a>", options: [.caseInsensitive, .backwards]) {
                bWindow = String(beforeText[prevClose.upperBound...])
            }
            let lastImg = allMatches("<img[^>]+(?:src|data-src)=\"([^\"]+)\"", in: bWindow).last
                ?? allMatches("<img[^>]+(?:src|data-src)='([^']+)'", in: bWindow).last
            if let lastImg {
                cards[index].coverURL = AvfanCoverPolicy.preferred(from: [absoluteURL(lastImg)])
            }
        }
        return cards
    }

    /// Cards in the detail page's 出演/相关 grids: one `history-link`
    /// anchor per title. Pairing discipline (AVFan builds 41/46): the
    /// card's image must live INSIDE its own anchor; fields are read
    /// from inside the anchor only — a bare mention anchor never wears
    /// another movie's cover/code under its own id.
    static func historyLinkCards(in html: String) -> [AvfanMovieCard] {
        guard let regex = try? NSRegularExpression(
            pattern: "<a([^>]*href=\"([^\"]*/movies/[A-Za-z0-9]{8})[^\"]*\"[^>]*)>",
            options: [.caseInsensitive]
        ) else { return [] }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var cards: [AvfanMovieCard] = []
        var seen = Set<String>()
        for (index, match) in matches.enumerated() {
            let tag = ns.substring(with: match.range(at: 1))
            let href = unescape(ns.substring(with: match.range(at: 2)))
            guard let id = pathID(from: href), !seen.contains(id) else { continue }
            let windowStart = match.range.location + match.range.length
            let windowEnd = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
            let windowLen = max(0, windowEnd - windowStart)
            let fullWindow = ns.substring(with: NSRange(location: windowStart, length: windowLen))
            let nsWindow = fullWindow as NSString
            let imgLocation = nsWindow.range(of: "<img", options: .caseInsensitive).location
            let closeRange = nsWindow.range(of: "</a>", options: .caseInsensitive)
            guard imgLocation != NSNotFound,
                  closeRange.location != NSNotFound,
                  imgLocation < closeRange.location else { continue }
            let window = nsWindow.substring(to: closeRange.location)
            seen.insert(id)
            let titleAttr = attribute("title", in: tag).map(unescape) ?? ""
            let imgSrc = firstMatch("<img[^>]+(?:data-src|data-original|src)=\"([^\"]+)\"", in: window)
            let imgAlt = firstMatch("<img[^>]+alt=\"([^\"]*)\"", in: window).map(unescape) ?? ""
            let bold = firstMatch("<strong[^>]*>([^<]+)</strong>", in: window)
            let code = extractCode(from: bold ?? "") ?? extractCode(from: titleAttr) ?? extractCode(from: imgAlt)
            var title = stripTags(bold ?? "")
            if let code, title == code { title = "" }
            if title.isEmpty {
                if let code, titleAttr.contains(code) {
                    title = titleAttr.replacingOccurrences(of: "[\(code)]", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                } else if !titleAttr.isEmpty {
                    title = titleAttr
                } else {
                    title = imgAlt
                }
            }
            let candidates = AvfanCoverPolicy.collect(from: window) + [imgSrc].compactMap { $0 }.map { absoluteURL($0) }
            cards.append(AvfanMovieCard(
                pathID: id,
                href: href,
                code: code,
                title: title,
                coverURL: AvfanCoverPolicy.preferred(from: candidates),
                date: nil,
                ratingText: firstMatch("(\\d+(?:\\.\\d+)?分[^<]*)", in: window).map(stripTags),
                badges: [],
                canPlay: window.contains("可播放")
            ))
        }
        return cards
    }

    static func sectionCards(in html: String, heading: String) -> [AvfanMovieCard] {
        guard let range = html.range(of: heading) else { return [] }
        var slice = String(html[range.upperBound...])
        for other in ["还出演过", "相关作品", "相关清单"] where other != heading {
            if let end = slice.range(of: other) {
                slice = String(slice[..<end.lowerBound])
            }
        }
        if slice.count > 60000 { slice = String(slice.prefix(60000)) }
        var seen = Set<String>()
        let specialized = historyLinkCards(in: slice)
        let parsed = specialized.isEmpty ? movieCards(in: slice) : specialized
        return parsed.filter { seen.insert($0.pathID).inserted }.prefix(12).map { $0 }
    }

    /// The detail page's own canonical movie id — an identity check
    /// independent of the parsed code.
    static func canonicalPathID(in html: String) -> String? {
        for pattern in [
            "<link[^>]*rel=\"canonical\"[^>]*href=\"([^\"]*/movies/[A-Za-z0-9]{8})[^\"]*\"",
            "<link[^>]*href=\"([^\"]*/movies/[A-Za-z0-9]{8})[^\"]*\"[^>]*rel=\"canonical\""
        ] {
            if let href = firstMatch(pattern, in: html) {
                return pathID(from: unescape(href))
            }
        }
        return nil
    }

    // MARK: Magnets

    static func magnets(in html: String) -> [AvfanMagnetItem] {
        var items: [AvfanMagnetItem] = []
        var seen = Set<String>()

        if let regex = try? NSRegularExpression(
            pattern: "<div class=\"magnet-list-item\"[\\s\\S]*?</div>\\s*</div>",
            options: [.caseInsensitive]
        ) {
            let ns = html as NSString
            for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
                let block = ns.substring(with: match.range)
                guard let raw = attribute("data-magnet", in: block) ?? firstMatch("href=\"(magnet:[^\"]+)\"", in: block) else { continue }
                let url = unescape(raw)
                if !seen.insert(url).inserted { continue }
                let name = firstMatch("class=\"[^\"]*break-all[^\"]*\"[^>]*>([^<]+)", in: block).map(stripTags)
                    ?? firstMatch("[?&]dn=([^&\"']+)", in: url).map { unescape($0.removingPercentEncoding ?? $0) }
                    ?? "磁力链接"
                let sizeKB = firstMatch("data-sort-size=\"(\\d+)\"", in: block).flatMap(Int.init)
                let files = firstMatch("data-sort-files=\"(\\d+)\"", in: block).flatMap(Int.init)
                let meta = firstMatch("<span>(\\d{4}-\\d{2}-\\d{2}[^<]*)</span>", in: block).map(stripTags)
                var date: String?
                var sizeText: String?
                var fileCount = files
                if let meta {
                    let parts = meta.split(separator: "·").map { $0.trimmingCharacters(in: .whitespaces) }
                    for part in parts {
                        if part.range(of: "^\\d{4}-\\d{2}-\\d{2}", options: .regularExpression) != nil {
                            date = String(part.prefix(10))
                        } else if part.contains("文件"), let n = firstMatch("(\\d+)", in: part) {
                            fileCount = fileCount ?? Int(n)
                        } else if part.contains("GB") || part.contains("MB") || part.contains("KB") {
                            sizeText = part
                        }
                    }
                }
                if sizeText == nil, let sizeKB {
                    sizeText = formatSize(mb: sizeKB)
                }
                var tags: [String] = []
                for tag in allMatches("class=\"[^\"]*sub-tag[^\"]*\"[^>]*>([^<]+)", in: block) {
                    let label = stripTags(tag)
                    if !label.isEmpty { tags.append(label) }
                }
                items.append(AvfanMagnetItem(url: url, name: name, sizeText: sizeText, sizeKB: sizeKB, fileCount: fileCount, date: date, tags: tags))
            }
        }

        if items.isEmpty {
            for raw in allMatches("(?:data-magnet=|href=)\"(magnet:[^\"]+)\"", in: html) {
                let url = unescape(raw)
                if seen.insert(url).inserted {
                    let name = firstMatch("[?&]dn=([^&\"']+)", in: url).map { unescape($0.removingPercentEncoding ?? $0) } ?? "磁力链接"
                    items.append(AvfanMagnetItem(url: url, name: name, sizeText: nil, sizeKB: nil, fileCount: nil, date: nil, tags: []))
                }
            }
        }
        return items
    }

    /// `data-sort-size` on avfan magnet rows is already in megabytes.
    static func formatSize(mb: Int) -> String {
        if mb >= 1024 * 1024 {
            return String(format: "%.2fPB", Double(mb) / 1024.0 / 1024.0)
        }
        if mb >= 1024 {
            return String(format: "%.2fGB", Double(mb) / 1024.0)
        }
        return "\(mb)MB"
    }

    // MARK: Detail

    static func movieDetail(from html: String, url: URL?) -> AvfanMovieDetail {
        let pageURL = url?.absoluteString
            ?? firstMatch("property=\"og:url\"\\s+content=\"([^\"]+)\"", in: html)
            ?? ""
        let pathID = pathID(from: pageURL) ?? pathID(from: html) ?? ""
        let schema = firstMatch("<script[^>]*type=\"application/ld\\+json\"[^>]*>(\\{[\\s\\S]*?\"@type\"\\s*:\\s*\"VideoObject\"[\\s\\S]*?\\})</script>", in: html)
            ?? firstMatch("<script[^>]*type=\"application/ld\\+json\"[^>]*>(\\{[\\s\\S]*?VideoObject[\\s\\S]*?\\})</script>", in: html)

        var title = firstMatch("<h1[^>]*>([\\s\\S]*?)</h1>", in: html).map(stripTags)
            ?? firstMatch("property=\"og:title\"\\s+content=\"([^\"]+)\"", in: html).map { unescape($0).replacingOccurrences(of: " | AVFan", with: "") }
            ?? ""
        var cover = firstMatch("property=\"og:image\"\\s+content=\"([^\"]+)\"", in: html)
            ?? firstMatch("thumbnailUrl\"\\s*:\\s*\"([^\"]+)\"", in: html)
        var summary = descriptionText(in: html)
            ?? firstMatch("property=\"og:description\"\\s+content=\"([^\"]+)\"", in: html).map(unescape)
        var releaseDate = definition(named: "发行日期", in: html) ?? firstMatch("uploadDate\"\\s*:\\s*\"([0-9T:+-]+)\"", in: html).map { String($0.prefix(10)) }
        var duration = definition(named: "片长", in: html)
        var rating: Double?
        var ratingCount: Int?

        if let schema, let data = schema.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if title.isEmpty, let name = obj["name"] as? String { title = unescape(name) }
            if cover == nil, let thumb = obj["thumbnailUrl"] as? String { cover = thumb }
            if summary == nil, let desc = obj["description"] as? String { summary = unescape(desc) }
            if releaseDate == nil, let upload = obj["uploadDate"] as? String { releaseDate = String(upload.prefix(10)) }
            if duration == nil, let iso = obj["duration"] as? String, let minutes = firstMatch("PT(\\d+)M", in: iso) {
                duration = "\(minutes) 分钟"
            }
            if let agg = obj["aggregateRating"] as? [String: Any] {
                rating = (agg["ratingValue"] as? NSNumber)?.doubleValue ?? Double("\(agg["ratingValue"] ?? "")")
                ratingCount = (agg["ratingCount"] as? NSNumber)?.intValue ?? Int("\(agg["ratingCount"] ?? "")")
            }
        }

        let code = firstMatch("data-number=\"([^\"]+)\"", in: html)
            ?? firstMatch("class=\"[^\"]*movie-number[^\"]*\"[^>]*>([\\s\\S]*?)</span>", in: html).map { stripTags($0).replacingOccurrences(of: " ", with: "") }
            ?? extractCode(from: title)

        if let code, title.hasPrefix(code) {
            title = title.replacingOccurrences(of: code, with: "", options: [], range: title.startIndex..<title.index(title.startIndex, offsetBy: min(code.count + 1, title.count))).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // The page's own declared cover (og:image / JSON-LD) IS this
        // movie's cover and wins outright; the whole-page scan is only
        // a fallback for pages declaring none (it can surface other
        // titles' art).
        let declaredCover = cover.flatMap { $0.isEmpty ? nil : $0 }
        let preferredCover = declaredCover ?? AvfanCoverPolicy.preferred(in: html)
        return AvfanMovieDetail(
            pathID: pathID,
            pageURL: pageURL,
            code: code,
            title: title,
            coverURL: preferredCover,
            summary: summary,
            releaseDate: releaseDate,
            duration: duration,
            rating: rating,
            ratingCount: ratingCount,
            makers: links(in: definitionHTML(named: "制作商", in: html) ?? "", kind: "maker"),
            publishers: links(in: definitionHTML(named: "发行商", in: html) ?? "", kind: "publisher"),
            directors: links(in: definitionHTML(named: "导演", in: html) ?? "", kind: "director"),
            series: links(in: html, kind: "series", pathHint: "/series/"),
            casts: links(in: definitionHTML(named: "演员", in: html) ?? "", kind: "cast"),
            tags: links(in: definitionHTML(named: "标签", in: html) ?? "", kind: "tag"),
            magnets: magnets(in: html),
            alsoStarred: sectionCards(in: html, heading: "还出演过"),
            relatedWorks: sectionCards(in: html, heading: "相关作品")
        )
    }

    static func descriptionText(in html: String) -> String? {
        guard let inner = firstMatch("<div[^>]*id=\"description\"[^>]*>([\\s\\S]*?)</div>", in: html) else { return nil }
        var text = stripTags(inner)
        text = text.replacingOccurrences(of: "<br>", with: "\n")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    // MARK: Casts

    static func castCards(in html: String) -> [AvfanCastCard] {
        var out: [AvfanCastCard] = []
        var seen = Set<String>()
        if let regex = try? NSRegularExpression(
            pattern: "<a[^>]+href=\"([^\"]*/casts/([A-Za-z0-9]{8})[^\"]*)\"[^>]*>([\\s\\S]*?)</a>",
            options: [.caseInsensitive]
        ) {
            let ns = html as NSString
            for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
                guard match.numberOfRanges >= 4 else { continue }
                let href = ns.substring(with: match.range(at: 1))
                let id = ns.substring(with: match.range(at: 2))
                let block = ns.substring(with: match.range(at: 3))
                guard seen.insert(id).inserted else { continue }
                let avatar = firstMatch("<img[^>]+(?:src|data-src|data-original)=\"([^\"]+)\"", in: block)
                    .map { unescape($0) }
                let lines = block
                    .replacingOccurrences(of: "<[^>]+>", with: "\n", options: .regularExpression)
                    .split(separator: "\n")
                    .map { unescape(String($0)).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                var name: String?
                var count: String?
                for line in lines {
                    if count == nil,
                       line.range(of: "\\d+\\s*(部作品|部影片|部|works|Works)", options: .regularExpression) != nil {
                        count = line
                    } else if name == nil {
                        name = line
                    }
                }
                guard let name, !name.isEmpty else { continue }
                out.append(AvfanCastCard(name: name, href: unescape(href), avatarURL: avatar, countText: count))
            }
        }
        return out
    }

    /// Actor page header (name / avatar / works count) + its works
    /// grid cards. Only the page's own public profile data — account
    /// wiring on the page is never read or used.
    static func castProfile(in html: String) -> AvfanCastProfile {
        var profile = AvfanCastProfile()
        if let title = firstMatch("<title>([^<]+)</title>", in: html) {
            let head = title.components(separatedBy: "|").first ?? title
            let parts = head.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if let first = parts.first { profile.name = first }
        }
        if profile.name.isEmpty, let h1 = firstMatch("<h1[^>]*>([\\s\\S]*?)</h1>", in: html) {
            profile.name = stripTags(h1)
        }
        if let avatar = firstMatch("<img[^>]+src=\"([^\"]*/avatars/[^\"]+)\"", in: html) {
            profile.avatarURL = unescape(avatar)
        }
        if let countText = firstMatch(#"(\d+)\s*部作品"#, in: stripTags(html)) {
            profile.worksCount = Int(countText)
        }
        profile.works = movieCards(in: html)
        return profile
    }

    // MARK: Definition lists

    private static func definition(named label: String, in html: String) -> String? {
        definitionHTML(named: label, in: html).map(stripTags).flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func definitionHTML(named label: String, in html: String) -> String? {
        firstMatch("<dt[^>]*>\\s*\(NSRegularExpression.escapedPattern(for: label))\\s*</dt>\\s*<dd[^>]*>([\\s\\S]*?)</dd>", in: html)
    }

    private static func links(in html: String, kind: String, pathHint: String? = nil) -> [AvfanNamedLink] {
        var results: [AvfanNamedLink] = []
        var seen = Set<String>()
        let pattern: String
        if let pathHint {
            pattern = "href=\"([^\"]*\(NSRegularExpression.escapedPattern(for: pathHint))[^\"]*)\"[^>]*>([^<]+)"
        } else {
            pattern = "href=\"([^\"]+)\"[^>]*>([^<]+)"
        }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = html as NSString
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let href = unescape(ns.substring(with: match.range(at: 1)))
            let name = stripTags(ns.substring(with: match.range(at: 2)))
            guard !name.isEmpty, seen.insert(href + name).inserted else { continue }
            if pathHint == nil, href.contains("/advanced_search") || href.contains("javascript:") { continue }
            results.append(AvfanNamedLink(name: name, href: href, kind: kind))
        }
        return results
    }

    // MARK: - Site session signals (public HTML only)

    static func containsSignInLink(_ html: String) -> Bool {
        html.contains("/sign_in") || html.contains(">登录<") || html.contains(">登入<")
    }

    static func isSignedIn(html: String) -> Bool {
        if signOutURL(in: html) != nil { return true }
        if html.contains(">退出登录<") || html.contains(">登出<") {
            return true
        }
        if html.contains(">退出<") && html.contains("sign_out") {
            return true
        }
        return false
    }

    static func signOutURL(in html: String) -> String? {
        if let href = firstMatch("href=\"([^\"]*sign_out[^\"]*)\"", in: html) { return absoluteURL(href) }
        if let href = firstMatch("href=\"([^\"]*logout[^\"]*)\"", in: html) { return absoluteURL(href) }
        return nil
    }

    static func signedInDisplayName(in html: String) -> String? {
        let candidates = [
            "id=\"dropdown-user\"[\\s\\S]{0,800}?>([^<]{1,40})</",
            "class=\"[^\"]*user-name[^\"]*\"[^>]*>([^<]+)",
        ]
        for pattern in candidates {
            if let name = firstMatch(pattern, in: html).map(stripTags), !name.isEmpty,
               name != "登录", name != "注册", name != "登入", name != "退出" {
                return name
            }
        }
        return nil
    }
}

// MARK: - Cookie bridge (WebKit <-> URLSession shared storage)

/// avfan cookies live in two stores: WKWebView's default data store
/// (the login page runs there) and HTTPCookieStorage.shared (the
/// URLSession fetches read it). The bridge keeps them in sync so a
/// WebView login immediately covers the scraping fetches, and a
/// sign-out clears both.
@MainActor
enum AvfanCookieBridge {
    static let host = "avfan.com"

    static func exportWebKitToShared() async {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        for cookie in cookies where cookie.domain.hasSuffix(host) {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    static func importSharedToWebKit() async {
        let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://avfan.com")!) ?? []
        for cookie in cookies {
            await WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie)
        }
    }

    static func clearSiteCookies() async {
        if let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://avfan.com")!) {
            for cookie in cookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
        let webCookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        for cookie in webCookies where cookie.domain.hasSuffix(host) {
            await WKWebsiteDataStore.default().httpCookieStore.deleteCookie(cookie)
        }
    }

    /// The site's legal-age confirmation cookie (value `1`), applied
    /// when the user confirms in the login screen.
    static func applyLegalAgeCookie() async {
        let cookie = HTTPCookie(
            properties: [
                .domain: host,
                .path: "/",
                .name: "legal_age",
                .value: "1",
                .secure: true,
                .expires: Date(timeIntervalSinceNow: 60 * 60 * 24 * 365),
            ]
        )
        if let cookie {
            HTTPCookieStorage.shared.setCookie(cookie)
            await WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie)
        }
    }
}

// MARK: - Session state (login bookkeeping, no account data)

@MainActor
final class AvfanSession: ObservableObject {
    static let shared = AvfanSession()

    @Published private(set) var isSignedIn: Bool
    @Published private(set) var displayName: String?
    private(set) var signOutURL: String?

    private let signedInKey = "avdb.avfan.session.signedIn"
    private let displayNameKey = "avdb.avfan.session.displayName"
    private let signOutURLKey = "avdb.avfan.session.signOutURL"

    private init() {
        let defaults = UserDefaults.standard
        isSignedIn = defaults.bool(forKey: signedInKey)
        displayName = defaults.string(forKey: displayNameKey)
        signOutURL = defaults.string(forKey: signOutURLKey)
    }

    static func signInURL() -> URL {
        URL(string: "https://avfan.com/\(AvfanHTMLParser.locale)/sign_in")!
    }

    func markSignedIn(name: String? = nil, signOutURL: String? = nil) {
        isSignedIn = true
        if let name, !name.isEmpty { displayName = name }
        if let signOutURL, !signOutURL.isEmpty { self.signOutURL = signOutURL }
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: signedInKey)
        if let displayName { defaults.set(displayName, forKey: displayNameKey) }
        if let signOutURL = self.signOutURL { defaults.set(signOutURL, forKey: signOutURLKey) }
    }

    func markSignedOut() {
        isSignedIn = false
        displayName = nil
        signOutURL = nil
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: signedInKey)
        defaults.removeObject(forKey: displayNameKey)
        defaults.removeObject(forKey: signOutURLKey)
    }

    /// The scraping layer reports the sign-in/out state it observes on
    /// every public page it fetches; an explicit sign-out link on a
    /// page proves signed-in, a sign-in link (with no sign-out link)
    /// proves signed-out.
    func applyPageSignals(html: String, url: URL?) {
        if let out = AvfanHTMLParser.signOutURL(in: html) {
            let name = AvfanHTMLParser.signedInDisplayName(in: html)
            if !isSignedIn || name != nil || signOutURL != out {
                markSignedIn(name: name, signOutURL: out)
            }
            return
        }
        if AvfanHTMLParser.isSignedIn(html: html) {
            if !isSignedIn { markSignedIn() }
            return
        }
        if isSignedIn, AvfanHTMLParser.containsSignInLink(html) {
            markSignedOut()
        }
    }

    /// Sign-out runs the site's own sign-out URL inside a WebView (it
    /// needs the real session), then wipes both cookie stores.
    func signOut() async {
        if let urlString = signOutURL, let url = URL(string: urlString) {
            _ = try? await AvfanWebViewFetcher.shared.html(for: url, ageCookie: nil)
        }
        await AvfanCookieBridge.clearSiteCookies()
        markSignedOut()
        await AvfanClient.shared.clearCache()
    }
}

// MARK: - WKWebView fetch fallback

/// Loads a public page in a real WKWebView session and returns the
/// rendered HTML. Used only when URLSession is blocked or the raw
/// HTML has no catalog items.
@MainActor
final class AvfanWebViewFetcher: NSObject, WKNavigationDelegate {
    static let shared = AvfanWebViewFetcher()

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String, Error>?
    private var timeoutTask: Task<Void, Never>?

    func html(for url: URL, ageCookie: String?) async throws -> String {
        if let ageCookie {
            await injectCookie(ageCookie, for: url)
        }
        let webView = preparedWebView()
        return try await withCheckedThrowingContinuation { continuation in
            if let previous = self.continuation {
                previous.resume(throwing: AvfanError.transport("已被新的页面请求取消"))
            }
            self.continuation = continuation
            timeoutTask?.cancel()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                await MainActor.run {
                    self?.fail(AvfanError.transport("网页加载超时"))
                }
            }
            var request = URLRequest(url: url)
            request.setValue(AvfanClient.mobileSafariUA, forHTTPHeaderField: "User-Agent")
            webView.load(request)
        }
    }

    private func preparedWebView() -> WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        view.customUserAgent = AvfanClient.mobileSafariUA
        view.navigationDelegate = self
        self.webView = view
        return view
    }

    private func injectCookie(_ cookieHeader: String, for url: URL) async {
        let parts = cookieHeader.split(separator: ";", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = parts.first, let eq = first.firstIndex(of: "=") else { return }
        let name = String(first[..<eq])
        let value = String(first[first.index(after: eq)...])
        guard let cookie = HTTPCookie(properties: [
            .domain: url.host ?? "avfan.com",
            .path: "/",
            .name: name,
            .value: value,
            .secure: true,
        ]) else { return }
        await WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            let script = "document.documentElement ? document.documentElement.outerHTML : document.body.outerHTML"
            do {
                let result = try await webView.evaluateJavaScript(script)
                let html = result as? String ?? ""
                finish(html)
            } catch {
                fail(error)
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            fail(error)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            fail(error)
        }
    }

    private func finish(_ html: String) {
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(returning: html)
        continuation = nil
    }

    private func fail(_ error: Error) {
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

// MARK: - Client

actor AvfanClient {
    static let shared = AvfanClient()

    static let mobileSafariUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"

    private let session: URLSession
    private var htmlCache: [String: (html: String, at: Date)] = [:]
    private let cacheLifetime: TimeInterval = 12 * 60

    /// Matching engine lanes: at most `laneCount` concurrent fetches,
    /// each lane keeps at least `laneInterval` between requests.
    static let laneCount = 3
    static let laneInterval: TimeInterval = 0.4
    private var laneFreeAt = [Date](repeating: .distantPast, count: AvfanClient.laneCount)

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = .shared
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 40
        session = URLSession(configuration: config)
    }

    func clearCache() {
        htmlCache.removeAll()
    }

    func pageURL(_ path: String) -> URL {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path) ?? URL(string: "https://avfan.com")!
        }
        // stripLocale removes any leading "/" and an existing locale
        // prefix, so stored hrefs never double up the locale segment.
        let clean = AvfanHTMLParser.stripLocale(path)
        return URL(string: "https://avfan.com/\(AvfanHTMLParser.locale)/\(clean)")!
    }

    func searchURL(query: String, st: String) -> URL {
        var components = URLComponents(string: "https://avfan.com/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "st", value: st),
        ]
        return components.url!
    }

    func movieURL(pathID: String) -> URL {
        URL(string: "https://avfan.com/\(AvfanHTMLParser.locale)/movies/\(pathID)")!
    }

    private func respectLane() async throws {
        let now = Date()
        var index = 0
        for i in laneFreeAt.indices where laneFreeAt[i] < laneFreeAt[index] {
            index = i
        }
        let start = max(now, laneFreeAt[index])
        laneFreeAt[index] = start.addingTimeInterval(Self.laneInterval)
        let wait = start.timeIntervalSince(now)
        if wait > 0 {
            try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
    }

    func html(for url: URL, allowWebViewFallback: Bool = true, expectCatalog: Bool = false, bypassCache: Bool = false) async throws -> String {
        let key = url.absoluteString
        if !bypassCache, let cached = htmlCache[key],
           Date().timeIntervalSince(cached.at) < cacheLifetime {
            return cached.html
        }
        try await respectLane()

        var request = URLRequest(url: url)
        request.setValue(Self.mobileSafariUA, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode
            let html = String(data: data, encoding: .utf8) ?? ""
            let blocked = AvfanHTMLParser.isBlocked(html, status: status)
            let emptyCatalog = expectCatalog && !AvfanHTMLParser.hasCatalogItems(html)
            if (blocked || emptyCatalog) && allowWebViewFallback {
                let webHTML = try await AvfanWebViewFetcher.shared.html(for: url, ageCookie: nil)
                if !webHTML.isEmpty {
                    htmlCache[key] = (webHTML, Date())
                    await reportSignals(webHTML, url: url)
                    return webHTML
                }
            }
            if blocked {
                throw AvfanError.blocked(status: status ?? 403)
            }
            if html.isEmpty {
                throw AvfanError.emptyPage
            }
            htmlCache[key] = (html, Date())
            await reportSignals(html, url: url)
            return html
        } catch let error as AvfanError {
            throw error
        } catch {
            if allowWebViewFallback {
                let webHTML = try await AvfanWebViewFetcher.shared.html(for: url, ageCookie: nil)
                if !webHTML.isEmpty {
                    htmlCache[key] = (webHTML, Date())
                    await reportSignals(webHTML, url: url)
                    return webHTML
                }
            }
            throw AvfanError.transport(error.localizedDescription)
        }
    }

    private func reportSignals(_ html: String, url: URL) async {
        await MainActor.run {
            AvfanSession.shared.applyPageSignals(html: html, url: url)
        }
    }
}
