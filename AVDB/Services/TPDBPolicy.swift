import Foundation

/// Independently implemented protocol policy; no third-party scraper code.
enum TPDBPolicy {
    struct Identity: Sendable { let brand: String; let title: String; let date: String; let seconds: Int; let official: String? }
    static let brands = ["blackedraw": "Blacked Raw", "blacked": "Blacked", "vixen": "Vixen", "tushy": "Tushy"]
    static func normalized(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    static func canonical(_ raw: String) -> String? {
        guard let u = URL(string: raw), u.scheme == "https", u.user == nil, u.password == nil,
              u.port == nil, u.query == nil, u.fragment == nil,
              let host = u.host?.lowercased(), brands.keys.contains(where: { host == $0 + ".com" || host == "www." + $0 + ".com" }),
              u.path.range(of: #"^/videos/[a-z0-9]+(?:-[a-z0-9]+)*$"#, options: .regularExpression) != nil else { return nil }
        return "https://www." + host.replacingOccurrences(of: "www.", with: "") + u.path
    }
    static func identity(type: String?, number: String?, title: String?, date: String?, minutes: Int?, official: String?) -> Identity? {
        guard type == "2", let number, let title, let minutes, minutes > 0,
              title.count >= 4, title.count <= 160, title != number,
              title.unicodeScalars.allSatisfy({ $0.isASCII && $0.value >= 32 }),
              let re = try? NSRegularExpression(pattern: #"^(Blackedraw|Blacked|Vixen|Tushy)\.(\d{4})\.(\d{2})\.(\d{2})$"#, options: .caseInsensitive),
              let match = re.firstMatch(in: number, range: NSRange(number.startIndex..., in: number)) else { return nil }
        let parts = (1...4).compactMap { Range(match.range(at: $0), in: number).map { String(number[$0]) } }
        guard parts.count == 4 else { return nil }
        let d = parts.dropFirst().joined(separator: "-")
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let parsed = formatter.date(from: d), formatter.string(from: parsed) == d,
              date == nil || String(date!.prefix(10)) == d else { return nil }
        if let official, canonical(official) == nil { return nil }
        let canonicalURL = official.flatMap(canonical)
        if let canonicalURL, URL(string: canonicalURL)?.host != "www." + parts[0].lowercased() + ".com" { return nil }
        return Identity(brand: parts[0].lowercased(), title: title, date: d, seconds: minutes * 60, official: canonicalURL)
    }
    static func matches(_ r: [String: Any], _ i: Identity) -> Bool {
        guard let id = r["id"] as? String, UUID(uuidString: id) != nil,
              normalized(r["title"] as? String ?? "") == normalized(i.title),
              r["date"] as? String == i.date,
              let site = r["site"] as? [String: Any], site["short_name"] as? String == i.brand,
              site["name"] as? String == brands[i.brand],
              let duration = r["duration"] as? Int, abs(duration - i.seconds) <= 60,
              let raw = r["url"] as? String, let url = canonical(raw),
              URL(string: url)?.host == "www." + i.brand + ".com",
              r["external_id"] as? String == i.brand + ":" + (URL(string: url)?.lastPathComponent ?? "") else { return false }
        return i.official == nil || i.official == url
    }
    static func unique(_ records: [[String: Any]], _ i: Identity) -> [String: Any]? {
        let exact = records.filter { matches($0, i) }
        return exact.count == 1 ? exact[0] : nil
    }
    static func uniqueQuery(_ object: [String: Any], _ identity: Identity) -> [String: Any]? {
        guard let records = object["data"] as? [[String: Any]],
              let meta = object["meta"] as? [String: Any],
              meta["current_page"] as? Int == 1, meta["last_page"] as? Int == 1,
              meta["total"] as? Int == records.count,
              (object["links"] as? [String: Any])?["next"] as? String == nil else { return nil }
        return unique(records, identity)
    }
    static func apiAllowed(_ u: URL) -> Bool {
        guard u.scheme == "https", u.host == "api.theporndb.net", u.user == nil, u.password == nil,
              u.port == nil, u.fragment == nil else { return false }
        return u.path == "/scenes" || (u.path == "/scenes/" + u.lastPathComponent && UUID(uuidString: u.lastPathComponent) != nil && u.query == nil)
    }
    static func imageAllowed(_ u: URL) -> Bool {
        guard u.scheme == "https", u.user == nil, u.password == nil, u.port == nil,
              u.query == nil, u.fragment == nil else { return false }
        let p = u.path.lowercased()
        guard !["smart", "upscale", "sharpen", "filters:", "/c/"].contains(where: p.contains),
              [".jpg", ".jpeg", ".png"].contains(where: p.hasSuffix) else { return false }
        if u.host == "cdn.theporndb.net" { return p.hasPrefix("/scene/") && p.contains("/background/") }
        return brands.keys.contains { u.host == "cdn." + $0 + ".com" } && p.hasPrefix("/scene/videoimages/") && p.contains("/mainlandscape/")
    }
    static func images(_ r: [String: Any]) -> [URL] {
        let background = r["background"] as? [String: Any]
        var seen = Set<String>()
        return [r["image"] as? String, background?["full"] as? String].compactMap { $0 }.compactMap(URL.init(string:)).filter { imageAllowed($0) && seen.insert($0.absoluteString).inserted }
    }
    static func request(_ url: URL, token: String?, timeout: TimeInterval) -> URLRequest? {
        guard token == nil ? imageAllowed(url) : apiAllowed(url) else { return nil }
        if let token, token.isEmpty || token.count > 4096 || !token.utf8.allSatisfy({ (33...126).contains($0) }) { return nil }
        var request = URLRequest(url: url); request.timeoutInterval = timeout
        request.setValue(token == nil ? "image/*" : "application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        return request
    }
    static func permitsRedirect(authenticated: Bool, count: Int, target: URL) -> Bool {
        !authenticated && count <= 2 && imageAllowed(target)
    }
    static func status(_ code: Int) -> String {
        switch code {
        case 200: return "HTTP 200"
        case 401: return "HTTP 401：未获授权，请检查 Token"
        case 403: return "HTTP 403：权限或访问策略拒绝（不能据此断言 Token 失效）"
        case 429: return "HTTP 429：请求受限，请稍后重试"
        case 300...399: return "拒绝 API 重定向"
        default: return "HTTP \(code)：保留原封面"
        }
    }
}
