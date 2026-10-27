import Foundation

// Selective reuse of AVDB 232 static parsers; no withdrawn sources or scripts.
enum OnlineAdditional {
    static func html(_ data: Data) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else { throw OnlineFailure.parse }
        return text
    }
    static func exactDetail(_ data: Data, page: URL, code: String, source: OnlineSource) throws -> String {
        let text = try html(data); let dom = try JRHTML.tree(text)
        let urls = dom.all { ($0.tag == "link" && $0.attrs["rel"] == "canonical") || ($0.tag == "meta" && $0.attrs["property"] == "og:url") }.compactMap { $0.attrs["href"] ?? $0.attrs["content"] }
        let jableHeadings = source == .jable ? dom.all { $0.tag == "section" && $0.cls("video-info") }.flatMap { $0.all { $0.tag == "h4" } }.map(\.text)
            + dom.all { $0.tag == "meta" && $0.attrs["property"] == "og:title" }.compactMap { $0.attrs["content"] } : []
        let javdayHeadings = source == .javday ? dom.all { $0.tag == "meta" && $0.attrs["property"] == "og:title" }.compactMap { $0.attrs["content"] } : []
        let headings = dom.all { $0.tag == "h1" }.map(\.text) + jableHeadings + javdayHeadings
        let slug = OnlinePolicy.pathSlug(page).uppercased()
        let exactVersionHeading = OnlineIdentity.version(slug, number: code, allowVersions: true) != nil
            && headings.contains { !JRHTML.matches("(?<![A-Z0-9_-])" + NSRegularExpression.escapedPattern(for: slug) + "(?![A-Z0-9_-])", $0).isEmpty }
        let pageMatch = urls.contains(page.absoluteString)
            || urls.contains(where: { URL(string: $0)?.absoluteURL.absoluteString == page.absoluteString })
            || (source == .javday && urls.contains(where: {
                guard let u = URL(string: $0)?.absoluteURL else { return false }
                return OnlinePolicy.javdaySlug(u)?.caseInsensitiveCompare(OnlinePolicy.pathSlug(page)) == .orderedSame
            }))
        guard pageMatch, headings.contains(where: { OnlineIdentity.heading($0, number: code) }) || exactVersionHeading else {
            if MissAVHTML.isChallenge(text) { throw OnlineFailure.blocked }
            throw OnlineFailure.noMatch
        }
        return text
    }
    static func searchLinks(_ data: Data, base: URL, source: OnlineSource, number: String) throws -> [URL] {
        let text = try html(data)
        if MissAVHTML.isChallenge(text) { throw OnlineFailure.blocked }
        let dom = try JRHTML.tree(text); var seen = Set<URL>()
        return dom.all { $0.tag == "a" }.compactMap { node in
            guard let href = node.attrs["href"], let url = URL(string: href, relativeTo: base)?.absoluteURL,
                  OnlinePolicy.metadata(url, source: source), url.query == nil, !url.path.contains("/search/"),
                  let slug = url.path.split(separator: "/").last,
                  OnlineIdentity.key(String(slug)) == OnlineIdentity.key(number), seen.insert(url).inserted else { return nil }
            return url
        }.prefix(5).map { $0 }
    }
    static func memoID(_ text: String, number: String) throws -> String {
        let dom = try JRHTML.tree(text)
        let expected = "/embed/" + (OnlineIdentity.key(number) ?? "")
        guard dom.all({ $0.tag == "iframe" }).contains(where: { n in
            guard let raw = n.attrs["src"], let u = URL(string: raw, relativeTo: URL(string: "https://memojav.org")!)?.absoluteURL else { return false }
            return u.host == "memojav.org" && u.scheme == "https" && u.path == expected
        }) else { throw OnlineFailure.parse }
        return OnlineIdentity.key(number)!
    }
    // Independently expressed public /static/main.js timestamp proof, not a
    // password, private signing key or IPA credential. No signatures are guessed.
    static func memoProof(milliseconds: Int64) -> [URLQueryItem] {
        let encoded = Data(String(milliseconds).utf8).base64EncodedString()
        guard encoded.count >= 12 else { return [] }
        let proof = String(encoded.suffix(12).prefix(10))
        let checksum = proof.utf8.enumerated().reduce(1) { $0 + Int($1.element) * $1.offset * 1743 }
        return [URLQueryItem(name: "sig", value: proof), URLQueryItem(name: "sts", value: String(checksum))]
    }
    static func memoMedia(_ data: Data) throws -> URL {
        var text = try html(data)
        if text.hasPrefix("for (;;);") { text = String(text.dropFirst(9)) }
        guard let d = text.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: d) as? [String:Any], obj["success"] as? Bool == true else { throw OnlineFailure.blocked }
        guard obj["type"] as? String == "hls", let raw = obj["url"] as? String else { throw OnlineFailure.unsupported }
        // A normal once-percent-encoded URL in the actual public response.
        let decoded = raw.hasPrefix("https%3A") || raw.hasPrefix("https%3a") ? raw.removingPercentEncoding ?? "" : raw
        guard let url = URL(string: decoded), OnlinePolicy.media(url, source: .memojav) else { throw OnlineFailure.unsafe }; return url
    }
    static func jsURLLiteral(_ literal: String) throws -> String {
        guard literal.count <= 8192, literal.count >= 2, let quote = literal.first,
              (quote == "\"" || quote == "'"), literal.last == quote else { throw OnlineFailure.parse }
        let chars = Array(literal.dropFirst().dropLast()); var result = ""; var i = 0
        while i < chars.count {
            let c = chars[i]; i += 1
            if c != "\\" { result.append(c); continue }
            guard i < chars.count else { throw OnlineFailure.parse }
            let escaped = chars[i]; i += 1
            if escaped == "\\" || escaped == "/" || escaped == "\"" || escaped == "'" { result.append(escaped) }
            else if escaped == "u" || escaped == "x" {
                let count = escaped == "u" ? 4 : 2
                guard i + count <= chars.count,
                      chars[i..<(i+count)].allSatisfy({ $0.isHexDigit }),
                      let number = UInt32(String(chars[i..<(i+count)]), radix: 16),
                      let scalar = UnicodeScalar(number) else { throw OnlineFailure.parse }
                result.unicodeScalars.append(scalar); i += count
            } else { throw OnlineFailure.parse }
        }
        guard !result.contains(where: { $0.isWhitespace || $0.asciiValue.map({ $0 < 32 || $0 == 127 }) == true }) else { throw OnlineFailure.unsafe }
        return result
    }
    // A small static data decoder for the observed public word-table container.
    // Never evaluate its function body. The decoded result must consist ENTIRELY
    // of three known URL assignments; executable statements cannot be returned.
    static func missavPackedSource(_ script: String) throws -> String? {
        let pattern = #"return\s+p\}\('((?:\\.|[^'\\])*)',(\d+),(\d+),'([^'\\]*)'\.split\('\|'\),0,\{\}\)\)"#
        // Ignore unrelated advertisement/library containers without a source field.
        // This is literal word-table inspection, not evaluation or a decoder fallback.
        let blocks = JRHTML.matches(pattern, script).filter { $0[4].components(separatedBy: "|").contains("source") }
        guard !blocks.isEmpty else { return nil }
        guard blocks.count == 1 else { throw OnlineFailure.unsupported }
        let m = blocks[0]
        guard let radix = Int(m[2]), (2...36).contains(radix), let count = Int(m[3]), (1...128).contains(count),
              m[1].count <= 8192, m[4].count <= 8192 else { throw OnlineFailure.tooLarge }
        let words = m[4].components(separatedBy: "|")
        guard words.count == count, words.allSatisfy({ $0.count <= 256 && $0.utf8.allSatisfy { (33...126).contains($0) && $0 != 39 && $0 != 92 } }) else { throw OnlineFailure.parse }
        var decoded = try jsURLLiteral("'" + m[1] + "'")
        // One pass, bounded replacements, not the remote Packer function.
        let regex = try NSRegularExpression(pattern: #"\b[0-9a-z]+\b"#)
        for token in regex.matches(in: decoded, range: NSRange(decoded.startIndex..., in: decoded)).reversed() {
            guard let range = Range(token.range, in: decoded), let index = Int(decoded[range], radix: radix),
                  index < words.count, !words[index].isEmpty else { continue }
            decoded.replaceSubrange(range, with: words[index])
        }
        let assignments = JRHTML.matches(#"(source(?:842|1280)?)='([^'\s]+)';"#, decoded)
        guard (1...3).contains(assignments.count), assignments.map({ $0[0] }).joined() == decoded,
              Set(assignments.map { $0[1] }).count == assignments.count,
              let primary = assignments.first(where: { $0[1] == "source" }),
              let root = URL(string: primary[2]) else { throw OnlineFailure.unsupported }
        guard OnlinePolicy.discoveredMedia(root, source: .missav) else { throw OnlineFailure.unsafe }
        for row in assignments {
            guard let url = URL(string: row[2]), OnlinePolicy.discoveredMedia(url, source: .missav),
                  OnlinePolicy.bound(url, to: root), url.path.split(separator: "/").first == root.path.split(separator: "/").first else { throw OnlineFailure.unsafe }
        }
        return primary[2] // Page-issued master, never a guessed UUID or rendition.
    }
    // Literal player source or the strictly bounded public assignment container.
    static func missavMedia(_ text: String) throws -> URL {
        var found = Set<URL>()
        func consider(_ raw: String) throws {
            let value = raw.replacingOccurrences(of: "\\/", with: "/")
            guard value.lowercased().contains("surrit."), let url = URL(string: value.hasPrefix("//") ? "https:" + value : value),
                  OnlinePolicy.discoveredMedia(url, source: .missav),
                  url.host?.lowercased().hasPrefix("surrit.") == true else { throw OnlineFailure.unsafe }
            let parts = url.path.split(separator: "/")
            guard parts.count >= 2, parts[0].range(of: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#, options: .regularExpression) != nil,
                  parts.last?.lowercased().hasSuffix(".m3u8") == true else { throw OnlineFailure.unsafe }
            found.insert(url)
        }
        let dom = try JRHTML.tree(text)
        for node in dom.all({ $0.tag == "video" || $0.tag == "source" }) {
            for name in ["src", "data-src"] {
                guard let raw = node.attrs[name], raw.lowercased().contains("surrit.") else { continue }
                try consider(raw)
            }
        }
        for block in JRHTML.matches(#"<script\b[^>]*>(.*?)</script\s*>"#, text) {
            if let raw = try missavPackedSource(block[1]) { try consider(raw) }
            for match in JRHTML.matches(#"\b(?:(?:var|let|const)\s+)?(?:source|hlsUrl)\s*=\s*(\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*')\s*(?:;|$)"#, block[1]) {
                try consider(try jsURLLiteral(match[1]))
            }
        }
        guard found.count == 1, let media = found.first else { throw OnlineFailure.unsupported }
        return media
    }
    static func jableMedia(_ text: String) throws -> URL {
        var found = Set<URL>()
        let page = URL(string: "https://jable.tv/")!
        for block in JRHTML.matches(#"<script\b[^>]*>(.*?)</script\s*>"#, text) {
            for match in JRHTML.matches(#"\b(?:var|let|const)\s+hlsUrl\s*=\s*(\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*')\s*(?:;|$)"#, block[1]) {
                let raw = try jsURLLiteral(match[1])
                guard let url = OnlineProvider.issuedPlaylist(raw, relativeTo: page, source: .jable) else { throw OnlineFailure.unsafe }
                found.insert(url)
            }
        }
        guard found.count == 1, let media = found.first else { throw OnlineFailure.unsupported }
        return media
    }
    // JavDay: page-issued HLS only (source/.m3u8 / DPlayer url / Artplayer url). No guessed CDN paths.
    static func javdayMedia(_ text: String, page: URL) throws -> URL {
        var found = Set<URL>()
        func consider(_ raw: String) throws {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\\/", with: "/")
            guard let url = OnlineProvider.issuedPlaylist(value, relativeTo: page, source: .javday) else { throw OnlineFailure.unsafe }
            found.insert(url)
        }
        let dom = try JRHTML.tree(text)
        for node in dom.all({ $0.tag == "source" || $0.tag == "video" }) {
            for name in ["src", "data-src"] {
                guard let raw = node.attrs[name], raw.lowercased().contains(".m3u8") else { continue }
                try consider(raw)
            }
        }
        for block in JRHTML.matches(#"<script\b[^>]*>(.*?)</script\s*>"#, text) {
            let body = block[1]
            for match in JRHTML.matches(#"\burl\s*:\s*(\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*')"#, body) {
                let raw = try jsURLLiteral(match[1])
                if raw.lowercased().contains(".m3u8") { try consider(raw) }
            }
            for match in JRHTML.matches(#"['\"](https?://[^'\"]+\.m3u8[^'\"]*)['\"]"#, body) {
                try consider(match[1])
            }
        }
        guard found.count == 1, let media = found.first else { throw OnlineFailure.unsupported }
        return media
    }
}
