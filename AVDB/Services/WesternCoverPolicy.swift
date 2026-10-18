import Foundation

/// Explicit, audited scene brands. Unknown brands fail closed; no actor/date-only match.
enum WesternCoverPolicy {
    struct Site: Sendable { let key: String; let name: String; let dataSlug: String }
    static let sites: [Site] = [
        Site(key: "blackedraw", name: "Blacked Raw", dataSlug: "blacked-raw"),
        Site(key: "blacked", name: "Blacked", dataSlug: "blacked"),
        Site(key: "vixen", name: "Vixen", dataSlug: "vixen"),
        Site(key: "tushy", name: "Tushy", dataSlug: "tushy")]
    struct Identity: Sendable {
        let site: Site
        let title: String
        let date: String
        let minutes: Int?
        let officialURL: String?
        let tpdbID: String?
    }
    static func normalized(_ text: String) -> String {
        unescape(text).precomposedStringWithCanonicalMapping.lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    static func identity(type: String?, number: String?, title: String?, date: String?, minutes: Int?, officialURL: String? = nil) -> Identity? {
        guard type == "2", let number,
              let code = captures(#"^([a-z][a-z0-9 _-]*)\.(\d{4})\.(\d{2})\.(\d{2})$"#, number).first,
              let site = sites.first(where: { normalized($0.key) == normalized(code[0]).replacingOccurrences(of: " ", with: "") }) else { return nil }
        let d = code.dropFirst().joined(separator: "-")
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let parsed = formatter.date(from: d), formatter.string(from: parsed) == d else { return nil }
        let raw = officialURL ?? ""
        let url = canonicalOfficial(raw)
        let id = tpdbID(raw)
        let t = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nativeTitle = t.count >= 4 && t.count <= 180 && t != number && t.unicodeScalars.allSatisfy({ $0.isASCII }) && !t.contains("\n")
        // Exact IDs/URLs can resolve a scene without a translated display title.
        guard url != nil || id != nil || (nativeTitle && (minutes ?? 0) > 0) else { return nil }
        if let url, URL(string: url)?.host != "www." + site.key + ".com" { return nil }
        if let date, String(date.prefix(10)) != d, url == nil && id == nil { return nil }
        return Identity(site: site, title: nativeTitle ? t : "", date: d, minutes: minutes, officialURL: url, tpdbID: id)
    }
    static func canonicalOfficial(_ raw: String) -> String? {
        guard let u = URL(string: raw), u.scheme == "https", u.user == nil, u.password == nil, u.port == nil,
              let host = u.host?.lowercased(), let site = sites.first(where: { host == $0.key + ".com" || host == "www." + $0.key + ".com" }),
              u.path.range(of: #"^/videos/[a-z0-9]+(?:-[a-z0-9]+)*/?$"#, options: .regularExpression) != nil else { return nil }
        return "https://www." + site.key + ".com" + u.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).withLeadingSlash
    }
    static func tpdbID(_ raw: String) -> String? {
        guard let u = URL(string: raw), u.scheme == "https", ["theporndb.net", "api.theporndb.net"].contains(u.host ?? ""),
              u.user == nil, u.password == nil, u.port == nil, u.path.hasPrefix("/scenes/"), UUID(uuidString: u.lastPathComponent) != nil else { return nil }
        return u.lastPathComponent.lowercased()
    }
    static func recordMatches(_ r: [String: Any], identity i: Identity) -> Bool {
        guard let uuid = r["id"] as? String, UUID(uuidString: uuid) != nil,
              let site = r["site"] as? [String: Any], normalized(site["name"] as? String ?? "") == normalized(i.site.name),
              normalized(site["short_name"] as? String ?? "").replacingOccurrences(of: " ", with: "") == i.site.key,
              let raw = r["url"] as? String, let url = canonicalOfficial(raw), URL(string: url)?.host == "www." + i.site.key + ".com" else { return false }
        if !i.title.isEmpty, normalized(r["title"] as? String ?? "") != normalized(i.title) { return false }
        if let minutes = i.minutes, minutes > 0, let seconds = r["duration"] as? Int, abs(seconds - minutes * 60) > 60 { return false }
        if let exact = i.tpdbID { return uuid.lowercased() == exact }
        if let exact = i.officialURL { return exact == url } // Date alone may disagree; exact URL is stronger evidence.
        guard r["date"] as? String == i.date, !i.title.isEmpty, let minutes = i.minutes, minutes > 0,
              let seconds = r["duration"] as? Int, abs(seconds - minutes * 60) <= 60 else { return false }
        return true
    }
    static func uniqueRecord(_ records: [[String: Any]], identity: Identity) -> [String: Any]? {
        let matches = records.filter { recordMatches($0, identity: identity) }
        return matches.count == 1 ? matches[0] : nil
    }
    static func imageAllowed(_ u: URL) -> Bool {
        guard u.scheme == "https", u.user == nil, u.password == nil, u.port == nil, u.query == nil, u.fragment == nil else { return false }
        let p = u.path.lowercased()
        guard !["smart", "upscale", "sharpen", "filters:", "/c/"].contains(where: p.contains), [".jpg", ".jpeg", ".png"].contains(where: p.hasSuffix) else { return false }
        let host = u.host?.lowercased() ?? ""
        if sites.contains(where: { host == "cdn." + $0.key + ".com" }) { return p.hasPrefix("/scene/videoimages/") && p.contains("/mainlandscape/") }
        if host == "cdn.theporndb.net" { return p.hasPrefix("/scene/") && p.contains("/background/") }
        if host == "cdn.dt18.com" { return p.hasPrefix("/media/scenes/") }
        if host == "bdn.dt18.com" { return p.range(of: #"^/\d+/\d+/\d+/0\.jpg$"#, options: .regularExpression) != nil }
        return false
    }
    static func tpdbImages(_ r: [String: Any]) -> [String] {
        let bg = r["background"] as? [String: Any]
        return [r["image"] as? String, bg?["full"] as? String].compactMap { $0 }.filter { URL(string: $0).map(imageAllowed) == true }
    }
    static func apiAllowed(_ u: URL) -> Bool {
        guard u.scheme == "https", u.host == "api.theporndb.net", u.user == nil, u.password == nil, u.port == nil, u.fragment == nil else { return false }
        return u.path == "/scenes" || (u.path.hasPrefix("/scenes/") && UUID(uuidString: u.lastPathComponent) != nil)
    }
    static func dataPageAllowed(_ u: URL) -> Bool {
        guard u.scheme == "https", u.host == "www.data18.com", u.user == nil, u.password == nil, u.port == nil, u.fragment == nil else { return false }
        return u.path == "/sys/live.php" || u.path.range(of: #"^/scenes/\d+-[a-z0-9-]+$"#, options: .regularExpression) != nil || u.path == "/sys/media_photos.php"
    }
    static func eligible(width: Int, height: Int) -> Bool { width >= 320 && height >= 180 && width <= 10000 && height <= 10000 && width * height <= 40_000_000 }
    static func winner(_ values: [DetailPosterQuality]) -> DetailPosterQuality? {
        values.filter { eligible(width: $0.width, height: $0.height) }.sorted {
            let a = Int64($0.width) * Int64($0.height), b = Int64($1.width) * Int64($1.height)
            return a == b ? $0.source < $1.source : a > b
        }.first
    }
    static func captures(_ pattern: String, _ text: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { m in
            (1..<m.numberOfRanges).map { Range(m.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
        }
    }
    static func unescape(_ s: String) -> String { s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#039;", with: "'").replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&quot;", with: "\"") }
    static func attributes(_ tag: String) -> [String: String] {
        var result: [String: String] = [:]
        for m in captures(#"([a-z][a-z0-9_-]*)\s*=\s*(["'])(.*?)\2"#, tag) { guard result[m[0].lowercased()] == nil else { return [:] }; result[m[0].lowercased()] = unescape(m[2]) }
        return result
    }
    static func restricted(_ html: String) -> Bool {
        ["age verification", "agecheck", "verify your age", "confirm your age", "captcha", "access denied", "年齢認証"].contains { html.localizedCaseInsensitiveContains($0) }
    }
    static func dataLinks(_ html: String, title: String) -> [String] {
        let anchors = captures(#"(<a\b[^>]*>)(.*?)</a>"#, html)
        let urls = anchors.compactMap { m -> String? in
            let a = attributes(m[0]); guard let href = a["href"], let u = URL(string: href, relativeTo: URL(string: "https://www.data18.com")!)?.absoluteURL, dataPageAllowed(u), u.path.hasPrefix("/scenes/") else { return nil }
            let text = m[1].replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            return normalized(a["title"] ?? text) == normalized(title) ? u.absoluteString : nil
        }
        return Array(Set(urls)).sorted()
    }
    struct DataMatch: Sendable { let images: [String]; let gallery: String? }
    static func dataMatch(_ html: String, identity i: Identity) -> DataMatch? {
        guard !restricted(html), !i.title.isEmpty,
              html.range(of: #"<title>[^<]*Porn Scene \| DATA18</title>"#, options: [.regularExpression, .caseInsensitive]) != nil,
              let h = captures(#"<h1\b[^>]*>\s*(?:<a\b[^>]*>)?(.*?)(?:</a>)?\s*</h1>"#, html).first?.first,
              normalized(h.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)) == normalized(i.title),
              html.contains("/studios/" + i.site.dataSlug + "\""), html.contains("#date" + i.date.replacingOccurrences(of: "-", with: "")),
              let d = captures(#"Duration:\s*<b>(\d+):(\d{2})</b>"#, html).first, let mins = Int(d[0]), let secs = Int(d[1]), secs < 60,
              let wanted = i.minutes, wanted > 0, abs(mins * 60 + secs - wanted * 60) <= 60 else { return nil }
        var images: [String] = []; var gallery: String?
        for m in captures(#"(<(?:img|a)\b[^>]*>)"#, html) {
            let a = attributes(m[0]); let raw = a["id"] == "playpriimage" ? a["src"] : a["id"] == "enlargecover" ? a["data-featherlight"] : nil
            if let raw, let u = URL(string: raw), imageAllowed(u) { images.append(u.absoluteString) }
            // Only an actual Primary gallery href, never scene-ID arithmetic or synthesized photo endpoints.
            if let href = a["href"], href.contains("media_photos.php"), m[0].localizedCaseInsensitiveContains("primary"), let u = URL(string: href, relativeTo: URL(string: "https://www.data18.com")!)?.absoluteURL, dataPageAllowed(u) { gallery = u.absoluteString }
        }
        return images.isEmpty ? nil : DataMatch(images: Array(Set(images)).sorted(), gallery: gallery)
    }
    static func primaryImage(_ html: String) -> String? {
        let values = Set(captures(#"(?:href|src|data-featherlight)=["'](https://bdn\.dt18\.com/\d+/\d+/\d+/0\.jpg)["']"#, html).compactMap(\.first))
        return values.count == 1 ? values.first : nil
    }
}
private extension String { var withLeadingSlash: String { "/" + self } }
