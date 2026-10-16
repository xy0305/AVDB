import Foundation

/// Explicit actor links generated from Tenhow's own navigation; never romanize a name.
/// Independent implementation using AVDB's existing bounded native JRHTML tree.
enum TenhowPoster {
    static func cleanName(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping.lowercased().filter { !$0.isWhitespace }
    }
    static func pages(identities: [[String]], mapping: [String: Set<String>] = TenhowActorLinks.mapping) -> [String] {
        var found = Set<String>()
        for names in identities {
            var paths = Set<String>(); var ambiguous = false
            for name in names {
                if let matches = mapping[cleanName(name)] {
                    if matches.count != 1 { ambiguous = true }
                    paths.formUnion(matches)
                }
            }
            // Conflicting aliases for the same actor never choose arbitrarily.
            if !ambiguous, paths.count == 1, let path = paths.first, allowedPage(path) { found.insert(path) }
        }
        return Array(found.sorted().prefix(2))
    }
    static func allowedPage(_ path: String) -> Bool {
        path.range(of: #"^/[a-z][a-z0-9_]{0,79}\.html$"#, options: .regularExpression) != nil
            && TenhowActorLinks.paths.contains(path)
    }
    static func allowedImage(_ url: URL) -> Bool {
        cleanURL(url) && url.path.range(of: #"^/images/[A-Z0-9]{10}\.jpg$"#, options: .regularExpression) != nil
    }
    static func cleanURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host?.lowercased() == "www.tenhow.net" && url.user == nil
            && url.password == nil && url.port == nil && url.query == nil && url.fragment == nil
            && !url.absoluteString.contains("%")
    }
    static func permitsRedirect(from: URL, to: URL) -> Bool {
        cleanURL(to) && from.absoluteString == to.absoluteString
    }
    static func number(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let m = JRHTML.matches(#"^([a-z]+)-([0-9]{2,5})$"#, s).first,
              let n = Int(m[2]), n > 0 else { return nil }
        return m[1] + "-" + String(n)
    }
    static func cid(_ raw: String) -> String? {
        let s = raw.lowercased()
        // Do not strip arbitrary manufacturer digits: they are part of identity.
        guard let m = JRHTML.matches(#"^(h_[0-9]+|[0-9]+)?([a-z]+)([0-9]{2,5})$"#, s).first,
              let n = Int(m[3]), n > 0 else { return nil }
        let manufacturers: [String: Set<String>] = [
            "stars":["1"], "star":["1"], "start":["1"], "sods":["1"],
            "fsdss":["1"], "fcdss":["1"], "fns":["1"], "abp":["118"],
            "chn":["118"], "rebd":["h_346"], "rebdb":["h_346"], "ovg":["13"]]
        guard m[1].isEmpty || manufacturers[m[2]]?.contains(m[1]) == true else { return nil }
        return m[2] + "-" + String(n)
    }
    static func linkedCID(_ href: String) -> String? {
        guard let u = URLComponents(string: href), u.scheme == "https", u.host == "al.fanza.co.jp",
              u.user == nil, u.password == nil, u.port == nil,
              let targets = u.queryItems?.filter({ $0.name == "lurl" }), targets.count == 1,
              let value = targets[0].value, let target = URLComponents(string: value),
              target.scheme == "https", ["www.dmm.co.jp", "video.dmm.co.jp"].contains(target.host ?? ""),
              target.user == nil, target.password == nil, target.port == nil, target.fragment == nil else { return nil }
        if target.host == "www.dmm.co.jp" {
            return JRHTML.matches(#"^/mono/dvd/-/detail/=/cid=([a-z0-9_]+)/$"#, target.path).first?[1]
        }
        guard target.path == "/av/content/", let ids = target.queryItems?.filter({ $0.name == "id" }), ids.count == 1 else { return nil }
        return ids[0].value
    }
    static func images(html: String, number raw: String) throws -> [String] {
        guard html.utf8.count <= 768 * 1024, let wanted = number(raw) else { return [] }
        let tree = try JRHTML.tree(html)
        var matched = Set<String>()
        for record in tree.all({ $0.tag == "div" && $0.cls("um_image_a") && $0.cls("um_popup") }) {
            try Task.checkCancellation()
            // Nested records are malformed, not a reason to merge sibling identities.
            if !record.all({ $0.cls("um_image_a") && $0.cls("um_popup") }).isEmpty { continue }
            let links = record.all { $0.tag == "a" }
            let rawCIDs = links.compactMap { linkedCID($0.attrs["href"] ?? "") }
            let codes = rawCIDs.compactMap(cid)
            guard !codes.isEmpty, codes.count == rawCIDs.count, Set(codes) == [wanted] else { continue }
            let images = Set(links.compactMap { node -> String? in
                guard node.attrs["title"] == "拡大表示", let href = node.attrs["href"],
                      let url = URL(string: href, relativeTo: URL(string:"https://www.tenhow.net/")!)?.absoluteURL,
                      allowedImage(url) else { return nil }
                return url.absoluteString
            })
            guard images.count == 1 else { if images.count > 1 { return [] }; continue }
            matched.formUnion(images)
        }
        return matched.count == 1 ? Array(matched) : []
    }
}

/// Optional exact-ASIN Japanese Amazon enrichment. No search, no URL size guessing.
enum AmazonPoster {
    static func asin(_ url: URL) -> String? {
        guard TenhowPoster.allowedImage(url) else { return nil }
        return String(url.deletingPathExtension().lastPathComponent)
    }
    static func allowedPage(_ url: URL, asin: String) -> Bool {
        guard asin.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) != nil,
              url.scheme == "https", url.host == "www.amazon.co.jp", url.user == nil,
              url.password == nil, url.port == nil, url.query == nil, url.fragment == nil else { return false }
        let parts = url.path.split(separator: "/")
        return (parts.count == 2 || parts.count == 3) && parts[parts.count - 2] == "dp" && parts.last == Substring(asin)
    }
    static func allowedImage(_ url: URL) -> Bool {
        guard url.scheme == "https", ["m.media-amazon.com", "images-na.ssl-images-amazon.com"].contains(url.host ?? ""),
              url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil,
              !url.absoluteString.contains("%") else { return false }
        return url.path.range(of: #"^/images/I/[A-Za-z0-9+_.-]{1,150}\.jpg$"#, options: .regularExpression) != nil
    }
    static func images(html: String, asin: String) throws -> [String] {
        guard html.utf8.count <= 2 * 1024 * 1024, !html.contains("validateCaptcha"), !html.contains("/errors/validateCaptcha") else { return [] }
        let tree = try JRHTML.tree(html)
        let identities = tree.all { $0.tag == "input" && $0.attrs["id"] == "ASIN" }.compactMap { $0.attrs["value"] }
        guard !identities.isEmpty, Set(identities) == [asin] else { return [] }
        let canonical = tree.all { $0.tag == "link" && $0.attrs["rel"] == "canonical" }.compactMap { $0.attrs["href"] }.compactMap(URL.init(string:))
        guard canonical.count == 1, allowedPage(canonical[0], asin: asin) else { return [] }
        let main = tree.all { $0.tag == "img" && $0.attrs["id"] == "landingImage" }
        guard main.count == 1 else { return [] }
        if let raw = main[0].attrs["data-old-hires"], let url = URL(string: raw), allowedImage(url) { return [url.absoluteString] }
        // Only the main product image's actual metadata; never recommendations.
        guard let raw = main[0].attrs["data-a-dynamic-image"], let data = raw.data(using:.utf8),
              let sizes = try? JSONSerialization.jsonObject(with:data) as? [String: [Int]] else { return [] }
        let candidates = sizes.filter { key, size in
            size.count == 2 && size.allSatisfy { $0 > 0 && $0 <= 10000 } && URL(string:key).map(allowedImage) == true
        }.sorted { a,b in
            let x=a.value[0]*a.value[1], y=b.value[0]*b.value[1]
            return x == y ? a.key < b.key : x > y
        }
        return candidates.first.map { [$0.key] } ?? []
    }
}
