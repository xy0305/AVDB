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
        guard urls.contains(page.absoluteString), dom.all({ $0.tag == "h1" }).contains(where: { OnlineIdentity.heading($0.text, number: code) }) else {
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
    static func staticMedia(_ text: String, source: OnlineSource) throws -> URL {
        let patterns: [String]
        if source == .jable { patterns = [#"\bhlsUrl\s*=\s*['"](https://[^'"\s<>]+\.m3u8(?:\?[^'"\s<>]*)?)['"]"#] }
        else { patterns = [#"(?:source|hlsUrl)\s*=\s*['"](https://[^'"\s<>]+\.m3u8(?:\?[^'"\s<>]*)?)['"]"#, #"https://surrit\.com/[A-Za-z0-9/_-]+/playlist\.m3u8"#] }
        for pattern in patterns {
            if let m = JRHTML.matches(pattern, text).first, let url = URL(string: m.count > 1 ? m[1] : m[0]) {
                guard OnlinePolicy.media(url, source: source) else { throw OnlineFailure.unsupported }; return url
            }
        }
        // Packed word-table reconstruction is not verified; no guessed URL or JS execution.
        throw OnlineFailure.unsupported
    }
}

extension OnlineProvider {
    func discoverAdditional(_ source: OnlineSource, number: String) async throws -> [OnlineLine] {
        guard let code = OnlineIdentity.key(number) else { throw OnlineFailure.noMatch }
        if source == .av01 {
            let url = URL(string: "https://www.av01.media/api/v1/videos/search?lang=en&include_facets=true")!
            let body = try JSONSerialization.data(withJSONObject: ["query":code,"pagination":["page":1,"limit":5]])
            return try OnlineAdditional.av01Records(try await transport.fetch(url, cap: 1024*1024, body: body), number: code)
        }
        let detail: URL
        if source == .memojav { detail = try OnlineAdditional.page(source, code) }
        else {
            let search = source == .jable ? URL(string:"https://jable.tv/search/" + code + "/")! : URL(string:"https://missav.fans/cn/search/" + code)!
            let links = try OnlineAdditional.searchLinks(try await transport.fetch(search, cap: 2*1024*1024), base: search, source: source, number: code)
            guard let first = links.first else { return [] }; detail = first
        }
        let text = try OnlineAdditional.exactDetail(try await transport.fetch(detail, cap: 2*1024*1024), page: detail, code: code, source: source)
        if source == .memojav { _ = try OnlineAdditional.memoID(text, number: code) }
        return [OnlineLine(source:source, recordID:code, code:code, version:"原始版本", lineKey:"primary")]
    }
    func resolveAdditional(_ line: OnlineLine, number: String) async throws -> OnlinePlaybackPlan {
        guard OnlineIdentity.key(line.code) == OnlineIdentity.key(number) else { throw OnlineFailure.noMatch }
        if line.source == .av01 {
            let url = URL(string:"https://www.av01.media/api/v1/videos/" + line.recordID)!
            let data = try await transport.fetch(url, cap: 1024*1024)
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String:Any], OnlineProvider.identifier(obj) == line.recordID,
                  let dvd = obj["dvd_id"] as? String, OnlineIdentity.key(dvd) == OnlineIdentity.key(number), obj["storage_base"] is String else { throw OnlineFailure.noMatch }
            let geo = try await transport.fetch(URL(string:"https://files.iw01.xyz/edge/geo.js?json")!, cap: 64*1024)
            guard let issued = try? JSONSerialization.jsonObject(with: geo) as? [String:Any] else { throw OnlineFailure.parse }
            // Observed comp=true, but its policy semantics are unconfirmed. Do not
            // fabricate a 403, override policy, or invent authorization. Stop explicitly unsupported.
            if issued["comp"] as? Bool == true { throw OnlineFailure.unsupported }
            // Public site requires dynamic master rewriting with CDN-issued authorization.
            // Native scoped adaptation is NOT yet verified; fail closed, never pass embed/API as media.
            throw OnlineFailure.unsupported
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
