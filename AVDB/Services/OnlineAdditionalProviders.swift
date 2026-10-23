// Public page/API protocol adapters. Never execute remote JS or share app accounts.
import Foundation

enum OnlineAdditional {
    static func page(_ source: OnlineSource, _ code: String) throws -> URL {
        guard let n = OnlineIdentity.key(code) else { throw OnlineFailure.noMatch }
        switch source {
        case .jable: return URL(string: "https://jable.tv/videos/" + n.lowercased() + "/")!
        case .missav: return URL(string: "https://missav.fans/cn/" + n.lowercased())!
        case .memojav: return URL(string: "https://memojav.org/video/" + n)!
        default: throw OnlineFailure.parse
        }
    }
    static func html(_ data: Data) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else { throw OnlineFailure.parse }
        return text
    }
    static func exactDetail(_ data: Data, page: URL, code: String, source: OnlineSource) throws -> String {
        let text = try html(data); let dom = try JRHTML.tree(text)
        let urls = dom.all { ($0.tag == "link" && $0.attrs["rel"] == "canonical") || ($0.tag == "meta" && $0.attrs["property"] == "og:url") }.compactMap { $0.attrs["href"] ?? $0.attrs["content"] }
        let jableHeadings = source == .jable ? dom.all { $0.tag == "section" && $0.cls("video-info") }.flatMap { $0.all { $0.tag == "h4" } }.map(\.text)
            + dom.all { $0.tag == "meta" && $0.attrs["property"] == "og:title" }.compactMap { $0.attrs["content"] } : []
        let headings = dom.all { $0.tag == "h1" }.map(\.text) + jableHeadings
        let slug = page.lastPathComponent.uppercased()
        let exactVersionHeading = OnlineIdentity.version(slug, number: code, allowVersions: true) != nil
            && headings.contains { !JRHTML.matches("(?<![A-Z0-9_-])" + NSRegularExpression.escapedPattern(for: slug) + "(?![A-Z0-9_-])", $0).isEmpty }
        guard urls.contains(page.absoluteString), headings.contains(where: { OnlineIdentity.heading($0, number: code) }) || exactVersionHeading else {
            if text.lowercased().contains("just a moment") || text.contains("cf-chl-") { throw OnlineFailure.blocked }
            throw OnlineFailure.noMatch
        }
        return text
    }
    static func searchLinks(_ data: Data, base: URL, source: OnlineSource, number: String) throws -> [URL] {
        let text = try html(data)
        if text.lowercased().contains("just a moment") || text.contains("cf-chl-") { throw OnlineFailure.blocked }
        let dom = try JRHTML.tree(text); var seen = Set<URL>()
        return dom.all { $0.tag == "a" }.compactMap { node in
            guard let href = node.attrs["href"], let url = URL(string: href, relativeTo: base)?.absoluteURL,
                  OnlinePolicy.metadata(url, source: source), url.query == nil, !url.path.contains("/search/"),
                  let slug = url.path.split(separator: "/").last,
                  OnlineIdentity.key(String(slug)) == OnlineIdentity.key(number), seen.insert(url).inserted else { return nil }
            return url
        }.prefix(5).map { $0 }
    }
    static func av01Records(_ data: Data, number: String) throws -> [OnlineLine] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String:Any], let list = obj["videos"] as? [[String:Any]] else { throw OnlineFailure.parse }
        return list.prefix(5).compactMap { v in
            guard let code = v["dvd_id"] as? String, OnlineIdentity.key(code) == OnlineIdentity.key(number), let id = OnlineProvider.identifier(v) else { return nil }
            return OnlineLine(source: .av01, recordID: id, code: code, version: "原始版本", lineKey: "primary")
        }
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
    static func jableSearch(_ number: String) throws -> URL {
        guard let code = OnlineIdentity.key(number) else { throw OnlineFailure.noMatch }
        var components = URLComponents(string: "https://jable.tv/search/\(code)/")!
        components.queryItems = [URLQueryItem(name: "mode", value: "async"), URLQueryItem(name: "function", value: "get_block"),
                                 URLQueryItem(name: "block_id", value: "list_videos_videos_list_search_result"), URLQueryItem(name: "q", value: code)]
        return components.url!
    }
    static func jableLines(_ data: Data, base: URL, number: String, versions: Bool) throws -> [OnlineLine] {
        let text = try html(data)
        if text.lowercased().contains("just a moment") || text.contains("cf-chl-") { throw OnlineFailure.blocked }
        let dom = try JRHTML.tree(text); var seen = Set<URL>()
        // Use the actual search anchors, not a constructed /videos/{number}/ URL.
        // Every complete slug is independently matched; never fall back to a random first result.
        return dom.all { $0.tag == "a" }.compactMap { node in
            guard let raw = node.attrs["href"], let url = URL(string: raw, relativeTo: base)?.absoluteURL,
                  OnlinePolicy.metadata(url, source: .jable), url.path.hasPrefix("/videos/"),
                  let slug = url.path.split(separator: "/").last,
                  let version = OnlineIdentity.version(String(slug), number: number, allowVersions: versions),
                  seen.insert(url).inserted else { return nil }
            return OnlineLine(source: .jable, recordID: String(slug), code: String(slug).uppercased(),
                              version: version, lineKey: "primary", detailURL: url)
        }.prefix(5).map { $0 }
    }
    // Decode bounded JS string literals only. No JS evaluation, Packer execution,
    // dynamic expressions, credentials, word-table reconstruction or guessed CDN URLs.
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
    // Direct public playlist only. Packed word-table reconstruction, UUID guessing
    // and alternate-host polling are not independently validated and stay unsupported.
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
            for match in JRHTML.matches(#"https?:\\?/\\?/(?:surrit\.[^\"'\\/\s]+)/(?:[0-9a-fA-F-]{36})(?:\\?/[^\"'\\<\s]*)?\.m3u8"#, block[1]) {
                try consider(match[0])
            }
            for match in JRHTML.matches(#"\b(?:var|let|const)\s+(?:source|hlsUrl)\s*=\s*(\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*')\s*(?:;|$)"#, block[1]) {
                try consider(try jsURLLiteral(match[1]))
            }
        }
        guard found.count == 1, let media = found.first else { throw OnlineFailure.unsupported }
        return media
    }
    static func missavLines(_ data: Data, base: URL, number: String, versions: Bool) throws -> [OnlineLine] {
        let text = try html(data)
        if text.lowercased().contains("just a moment") || text.contains("cf-chl-") { throw OnlineFailure.blocked }
        let dom = try JRHTML.tree(text)
        var seen = Set<URL>()
        return dom.all { $0.tag == "a" }.compactMap { node in
            guard let raw = node.attrs["href"],
                  let url = URL(string: OnlineAdditional.rewriteMissav(raw), relativeTo: base)?.absoluteURL,
                  OnlinePolicy.metadata(url, source: .missav), !url.path.contains("/search/"),
                  let slug = url.path.split(separator: "/").last,
                  let version = OnlineIdentity.version(String(slug), number: number, allowVersions: versions),
                  seen.insert(url).inserted else { return nil }
            return OnlineLine(source: .missav, recordID: String(slug), code: String(slug).uppercased(),
                              version: version, lineKey: "primary", detailURL: url)
        }.prefix(5).map { $0 }
    }
    static func rewriteMissav(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"^https?://missav\.[a-z0-9.-]+"#, with: "https://missav.fans", options: .regularExpression)
    }
    // Only a literal HTTPS playlist already present in the identity-checked public
    // detail. Short-lived geo authorization is not a media URL and is not rewritten.
    static func av01Media(_ detail: [String:Any]) throws -> URL {
        let candidates = [detail["master"], detail["playlist"], detail["m3u8"], detail["hls_url"]]
        let layout = detail["hls_layout"]
        var values: [Any?] = candidates
        if let layout = layout as? [String:Any] { values += [layout["master"], layout["playlist"], layout["url"], layout["m3u8"]] }
        else if let layout = layout as? String { values.append(layout) }
        var found = Set<URL>()
        for value in values {
            guard let raw = value as? String, !raw.isEmpty,
                  let url = OnlineProvider.issuedPlaylist(raw, relativeTo: URL(string: "https://www.av01.media/")!, source: .av01) else { continue }
            found.insert(url)
        }
        // A numeric layout or geo authorization is not a public playlist.
        guard found.count == 1, let url = found.first else { throw OnlineFailure.incomplete }
        return url
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
    static func staticMedia(_ text: String, source: OnlineSource) throws -> URL {
        if source == .jable { return try jableMedia(text) }
        if source == .missav { return try missavMedia(text) }
        throw OnlineFailure.unsupported
    }
}

extension OnlineProvider {
    func discoverAdditional(_ source: OnlineSource, number: String, versions: Bool = false) async throws -> [OnlineLine] {
        guard let code = OnlineIdentity.key(number) else { throw OnlineFailure.noMatch }
        if source == .jable {
            let search = try OnlineAdditional.jableSearch(code)
            let data = try await transport.fetch(search, cap: 2*1024*1024, headers: ["Accept": "text/html,application/xhtml+xml"])
            return try OnlineAdditional.jableLines(data, base: search, number: code, versions: versions)
        }
        if source == .missav {
            let search = URL(string: "https://missav.fans/cn/search/" + code)!
            let data = try await transport.fetch(search, cap: 2*1024*1024, headers: OnlinePolicy.headers(referrer: URL(string: "https://missav.fans/")!))
            return try OnlineAdditional.missavLines(data, base: search, number: code, versions: versions)
        }
        if source == .av01 {
            let url = URL(string: "https://www.av01.media/api/v1/videos/search?lang=en&include_facets=true")!
            let body = try JSONSerialization.data(withJSONObject: ["query":code,"pagination":["page":1,"limit":5]])
            return try OnlineAdditional.av01Records(try await transport.fetch(url, cap: 1024*1024, body: body), number: code)
        }
        let detail: URL
        if source == .memojav { detail = try OnlineAdditional.page(source, code) }
        else { throw OnlineFailure.parse }
        let text = try OnlineAdditional.exactDetail(try await transport.fetch(detail, cap: 2*1024*1024), page: detail, code: code, source: source)
        if source == .memojav { _ = try OnlineAdditional.memoID(text, number: code) }
        return [OnlineLine(source:source, recordID:code, code:code, version:"原始版本", lineKey:"primary")]
    }
    func resolveAdditional(_ line: OnlineLine, number: String, versions: Bool = false) async throws -> OnlinePlaybackPlan {
        guard OnlineIdentity.version(line.code, number: number, allowVersions: versions) != nil else { throw OnlineFailure.noMatch }
        if line.source == .jable {
            guard let detail = line.detailURL, OnlinePolicy.metadata(detail, source: .jable), detail.path.hasPrefix("/videos/"),
                  let slug = detail.path.split(separator: "/").last,
                  String(slug).uppercased() == line.code.uppercased(),
                  String(slug) == line.recordID else { throw OnlineFailure.noMatch }
            let text = try OnlineAdditional.exactDetail(try await transport.fetch(detail, cap: 2*1024*1024,
                headers: OnlinePolicy.headers(referrer: URL(string: "https://jable.tv/")!)), page: detail, code: number, source: .jable)
            let media = try OnlineAdditional.jableMedia(text)
            return try await validatedPlan(media: media, referrer: detail, line: line, number: number, pageIssued: true)
        }
        if line.source == .av01 {
            let url = URL(string:"https://www.av01.media/api/v1/videos/" + line.recordID)!
            let data = try await transport.fetch(url, cap: 1024*1024)
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String:Any], OnlineProvider.identifier(obj) == line.recordID,
                  let dvd = obj["dvd_id"] as? String, OnlineIdentity.key(dvd) == OnlineIdentity.key(number),
                  obj["storage_base"] is String else { throw OnlineFailure.noMatch }
            // A literal master in the identity-checked public detail can be validated.
            // Short-lived geo authorization is not guessed, cached or sent cross-source.
            let media = try OnlineAdditional.av01Media(obj)
            let referrer = URL(string: "https://www.av01.media/videos/" + line.recordID)!
            return try await validatedPlan(media: media, referrer: referrer, line: line, number: number, pageIssued: true)
        }
        if line.source == .missav {
            guard let detail = line.detailURL, OnlinePolicy.metadata(detail, source: .missav),
                  detail.path.split(separator: "/").last.map(String.init)?.uppercased() == line.code.uppercased() else { throw OnlineFailure.noMatch }
            let text = try OnlineAdditional.exactDetail(try await transport.fetch(detail, cap: 2*1024*1024,
                headers: OnlinePolicy.headers(referrer: URL(string: "https://missav.fans/")!)), page: detail, code: number, source: .missav)
            let media = try OnlineAdditional.missavMedia(text)
            return try await validatedPlan(media: media, referrer: detail, line: line, number: number, pageIssued: true)
        }
        let detail = try OnlineAdditional.page(line.source, number)
        let text = try OnlineAdditional.exactDetail(try await transport.fetch(detail, cap: 2*1024*1024), page: detail, code: number, source: line.source)
        let media: URL; let referrer: URL
        if line.source == .memojav {
            let id = try OnlineAdditional.memoID(text, number:number)
            referrer = URL(string:"https://memojav.org/embed/" + id)!
            let embed = try OnlineAdditional.html(try await transport.fetch(referrer, cap: 2*1024*1024))
            guard let declared = JRHTML.matches(#"\bid\s*:\s*['"]([^'"]+)['"]"#,embed).first?[1], OnlineIdentity.key(declared) == OnlineIdentity.key(number) else { throw OnlineFailure.noMatch }
            var query = URLComponents(string:"https://memojav.org/hls/get_video_info.php")!
            query.queryItems = [URLQueryItem(name:"id",value:id)] + OnlineAdditional.memoProof(milliseconds:Int64(Date().timeIntervalSince1970*1000))
            media = try OnlineAdditional.memoMedia(try await transport.fetch(query.url!, cap:1024*1024, headers:OnlinePolicy.headers(referrer:referrer)))
        } else { referrer = detail; media = try OnlineAdditional.staticMedia(text,source:line.source) }
        return try await validatedPlan(media:media, referrer:referrer, line:line, number:number)
    }
}
