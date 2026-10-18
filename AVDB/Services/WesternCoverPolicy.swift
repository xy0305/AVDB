import Foundation

/// Independently implemented. Only the evidenced Blacked Raw scene family is
/// enabled initially. Movies, other brands and incomplete identities fail closed.
enum WesternCoverPolicy {
    struct Identity: Sendable {
        let title: String
        let date: String
        let minutes: Int
        let officialURL: String?
    }
    static func normalized(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased()
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    static func identity(type: String?, number: String?, title: String?, date: String?, minutes: Int?, officialURL: String? = nil) -> Identity? {
        guard type == "2", let number, let title, let minutes, minutes > 0,
              let m = captures(#"^Blackedraw\.(\d{4})\.(\d{2})\.(\d{2})$"#, number).first,
              m.count == 3 else { return nil }
        let d = m.joined(separator: "-")
        if let date, String(date.prefix(10)) != d { return nil }
        // A catalog code or translated display title is not the original title.
        guard title.count >= 4, title.count <= 150, title != number,
              title.unicodeScalars.allSatisfy({ $0.isASCII }), !title.contains("\n") else { return nil }
        if let officialURL, canonicalOfficial(officialURL) == nil { return nil }
        return Identity(title: title, date: d, minutes: minutes, officialURL: officialURL.flatMap(canonicalOfficial))
    }
    static func canonicalOfficial(_ raw: String) -> String? {
        guard let u = URL(string: raw), u.scheme == "https", u.user == nil, u.password == nil,
              u.port == nil, ["www.blackedraw.com", "blackedraw.com"].contains(u.host?.lowercased() ?? ""),
              u.path.range(of: #"^/videos/[a-z0-9]+(?:-[a-z0-9]+)*$"#, options: .regularExpression) != nil else { return nil }
        return "https://www.blackedraw.com" + u.path
    }
    static func recordMatches(_ r: [String: Any], identity: Identity) -> Bool {
        guard let title = r["title"] as? String, normalized(title) == normalized(identity.title),
              let site = r["site"] as? [String: Any], site["short_name"] as? String == "blackedraw",
              site["name"] as? String == "Blacked Raw",
              r["date"] as? String == identity.date,
              let duration = r["duration"] as? Int, abs(duration - identity.minutes * 60) <= 60,
              let rawURL = r["url"] as? String, let url = canonicalOfficial(rawURL),
              let external = r["external_id"] as? String,
              external == "blackedraw:" + (URL(string: url)?.lastPathComponent ?? ""),
              let uuid = r["id"] as? String, UUID(uuidString: uuid) != nil else { return false }
        return identity.officialURL == nil || identity.officialURL == url
    }
    static func uniqueRecord(_ records: [[String: Any]], identity: Identity) -> [String: Any]? {
        // Reject conflicting duplicates, not 'first result wins'.
        let matches = records.filter { recordMatches($0, identity: identity) }
        return matches.count == 1 ? matches[0] : nil
    }
    static func imageAllowed(_ u: URL) -> Bool {
        guard u.scheme == "https", u.user == nil, u.password == nil, u.port == nil,
              u.query == nil, u.fragment == nil else { return false }
        let p = u.path.lowercased()
        guard !["smart", "upscale", "sharpen", "filters:", "/c/"].contains(where: p.contains),
              [".jpg", ".jpeg", ".png"].contains(where: p.hasSuffix) else { return false }
        switch u.host?.lowercased() {
        case "cdn.blackedraw.com": return p.hasPrefix("/scene/videoimages/") && p.contains("/mainlandscape/")
        case "cdn.theporndb.net": return p.hasPrefix("/scene/") && p.contains("/background/")
        case "cdn.dt18.com": return p.hasPrefix("/media/scenes/")
        case "bdn.dt18.com": return p.range(of: #"^/\d+/\d+/\d+/0\.jpg$"#, options: .regularExpression) != nil
        default: return false
        }
    }
    static func tpdbImages(_ record: [String: Any]) -> [String] {
        let background = record["background"] as? [String: Any]
        return [record["image"] as? String, background?["full"] as? String].compactMap { $0 }
            .filter { URL(string: $0).map(imageAllowed) == true }
    }
    static func apiAllowed(_ u: URL) -> Bool {
        guard u.scheme == "https", u.host == "api.theporndb.net", u.port == nil,
              u.user == nil, u.password == nil, u.fragment == nil else { return false }
        return u.path == "/scenes" || (u.path.hasPrefix("/scenes/") && UUID(uuidString: u.lastPathComponent) != nil)
    }
    static func dataPageAllowed(_ u: URL) -> Bool {
        guard u.scheme == "https", u.host == "www.data18.com", u.port == nil,
              u.user == nil, u.password == nil, u.fragment == nil else { return false }
        return u.path == "/sys/live.php" || u.path.range(of: #"^/scenes/\d+-[a-z0-9-]+$"#, options: .regularExpression) != nil ||
            u.path.range(of: #"^/g/scenes/\d+/\d+$"#, options: .regularExpression) != nil || u.path == "/sys/media_photos.php"
    }
    static func eligible(width: Int, height: Int) -> Bool {
        width >= 320 && height >= 180 && width <= 10000 && height <= 10000 && width * height <= 40_000_000
    }
    /// Effective native image area, no preferred site and no 5% portrait bonus.
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
    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&quot;", with: "\"")
    }
    static func dataLinks(_ html: String, title: String) -> [String] {
        let links = captures(#"<a\b[^>]*href=[\"'](https://www\.data18\.com/scenes/\d+-[a-z0-9-]+)[\"'][^>]*>(.*?)</a>"#, html)
        let titled = captures(#"<a\b[^>]*href=[\"'](https://www\.data18\.com/scenes/\d+-[a-z0-9-]+)[\"'][^>]*title=[\"']([^\"']+)[\"']"#, html)
        let exact = titled.filter { normalized(unescape($0[1])) == normalized(title) }.map { $0[0] } + links.filter { normalized(unescape($0[1].replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))) == normalized(title) }.map { $0[0] }
        return Array(Set(exact)).sorted()
    }
    struct DataMatch: Sendable { let image: String; let officialLink: String; let gallery: String? }
    static func dataMatch(_ html: String, identity: Identity) -> DataMatch? {
        // Never accept a movie as a scene, nor a same-day result alone.
        guard captures(#"<title>[^<]*Porn Scene \| DATA18</title>"#, html).count > 0,
              let h = captures(#"<h1\b[^>]*>\s*<a\b[^>]*>(.*?)</a>\s*</h1>"#, html).first?.first,
              normalized(unescape(h)) == normalized(identity.title),
              html.contains("https://www.data18.com/studios/blacked-raw\""),
              html.contains("#date" + identity.date.replacingOccurrences(of: "-", with: "")),
              let duration = captures(#"Duration:\s*<b>(\d+):(\d{2})</b>"#, html).first,
              let min = Int(duration[0]), let sec = Int(duration[1]), sec < 60,
              abs(min * 60 + sec - identity.minutes * 60) <= 60,
              let image = captures(#"<img\b[^>]*id=[\"']playpriimage[\"'][^>]*src=[\"']([^\"']+)[\"']"#, html).first?.first,
              URL(string: image).map(imageAllowed) == true else { return nil }
        let links = Set(captures(#"href=[\"'](https://www\.data18\.com/g/scenes/\d+/\d+\?c=1)[\"']"#, html).compactMap(\.first))
        guard links.count == 1, let link = links.first, URL(string: link).map(dataPageAllowed) == true else { return nil }
        // Gallery URL is read from the public page script, never derived from ID arithmetic.
        let scene = captures(#"media_photos\.php\?s=1&scene=(\d+)&"#, html).first?.first
        let pic = captures(#"id=[\"']gallery(\d+)[\"'][^>]*>\s*<span[^>]*>Gallery #0</span>&nbsp;\s*<span[^>]*>Primary\s*<b>1</b>"#, html).first?.first
        let gallery: String?
        if let scene, let pic { gallery = "https://www.data18.com/sys/media_photos.php?s=1&scene=\(scene)&pic=\(pic)&mscene=&screen=390" } else { gallery = nil }
        return DataMatch(image: image, officialLink: link, gallery: gallery)
    }
    static func primaryImage(_ html: String) -> String? {
        let values = Set(captures(#"(?:href|src)=[\"'](https://bdn\.dt18\.com/\d+/\d+/\d+/0\.jpg)[\"']"#, html).compactMap(\.first))
        return values.count == 1 ? values.first : nil
    }
}
