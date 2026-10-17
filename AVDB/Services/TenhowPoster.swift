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
        guard let m = JRHTML.matches(#"^([a-z]+|13dsvr)-([0-9]{2,5})$"#, s).first,
              let n = Int(m[2]), n > 0 else { return nil }
        return m[1] + "-" + String(n)
    }
    enum Storefront: String, Sendable { case retail, digital }
    struct LinkedCID: Hashable, Sendable {
        let raw: String
        let storefront: Storefront
        var number: String? { TenhowPoster.cid(raw, storefront: storefront) }
    }
    static func cid(_ raw: String, storefront: Storefront = .digital) -> String? {
        let s = raw.lowercased()
        // Only this evidenced digital series retains its numeric catalog prefix.
        if storefront == .digital, let m = JRHTML.matches(#"^13dsvr([0-9]{5})$"#, s).first,
           let n = Int(m[1]), n > 0 { return "13dsvr-" + String(n) }
        guard let m = JRHTML.matches(#"^(h_[0-9]+|d2|[0-9]+)?([a-z]+)([0-9]{2,5})$"#, s).first,
              let n = Int(m[3]), n > 0 else { return nil }
        let common: [String: Set<String>] = [
            "stars":["1"], "star":["1"], "start":["1"], "sods":["1"],
            "fsdss":["1"], "fcdss":["1"], "fns":["1"], "abp":["118"],
            "chn":["118"], "rebd":["h_346"], "rebdb":["h_346"], "ovg":["13"]]
        // Preserve the established digital/video maker rules in DetailPosterPolicy;
        // tightening URL admission must not silently drop previously valid sources.
        let digital: [String: Set<String>] = ["wsa":["2"], "fthtd":["1"], "faleno":["1"],
            "fgan":["1"], "fsnf":["1"], "flav":["1"], "gshrb":["h_346"]]
        let retail: [String: Set<String>] = ["abf":["118"], "gvh":["d2"], "godr":["h_1059"]]
        guard m[1].isEmpty || common[m[2]]?.contains(m[1]) == true
                || (storefront == .digital && digital[m[2]]?.contains(m[1]) == true)
                || (storefront == .retail && retail[m[2]]?.contains(m[1]) == true) else { return nil }
        return m[2] + "-" + String(n)
    }
    static func linkedCID(_ href: String) -> LinkedCID? {
        guard let u = URLComponents(string: href), u.scheme == "https", u.host == "al.fanza.co.jp",
              u.user == nil, u.password == nil, u.port == nil,
              let targets = u.queryItems?.filter({ $0.name == "lurl" }), targets.count == 1,
              let value = targets[0].value, let target = URLComponents(string: value),
              target.scheme == "https", ["www.dmm.co.jp", "video.dmm.co.jp"].contains(target.host ?? ""),
              target.user == nil, target.password == nil, target.port == nil, target.fragment == nil else { return nil }
        if target.host == "www.dmm.co.jp" {
            guard target.query == nil,
                  let m = JRHTML.matches(#"^/(mono/dvd|rental)/-/detail/=/cid=([a-z0-9_]+)/$"#, target.path).first else { return nil }
            return LinkedCID(raw: m[2], storefront: .retail)
        }
        guard target.path == "/av/content/", let items = target.queryItems,
              items.count == 1, items[0].name == "id", let id = items[0].value else { return nil }
        return LinkedCID(raw: id, storefront: .digital)
    }
    struct RecordMatch {
        let images: [String]
        let official: [String]
    }
    static func images(html: String, number raw: String) throws -> [String] {
        try match(html: html, number: raw)?.images ?? []
    }
    static func match(html: String, number raw: String) throws -> RecordMatch? {
        guard html.utf8.count <= 768 * 1024, let wanted = number(raw) else { return nil }
        let tree = try JRHTML.tree(html)
        var matched = Set<String>()
        var identities = Set<LinkedCID>()
        for record in tree.all({ $0.tag == "div" && $0.cls("um_image_a") && $0.cls("um_popup") }) {
            try Task.checkCancellation()
            // Nested records are malformed, not a reason to merge sibling identities.
            if !record.all({ $0.cls("um_image_a") && $0.cls("um_popup") }).isEmpty { continue }
            let links = record.all { $0.tag == "a" }
            let identityLinks = links.filter { ($0.attrs["href"] ?? "").hasPrefix("https://al.fanza.co.jp/") }
            let rawCIDs = identityLinks.compactMap { linkedCID($0.attrs["href"] ?? "") }
            guard rawCIDs.count == identityLinks.count else { continue }
            let codes = rawCIDs.compactMap(\.number)
            guard !codes.isEmpty, codes.count == rawCIDs.count, Set(codes) == [wanted] else { continue }
            let images = Set(links.compactMap { node -> String? in
                guard node.attrs["title"] == "拡大表示", let href = node.attrs["href"],
                      let url = URL(string: href, relativeTo: URL(string:"https://www.tenhow.net/")!)?.absoluteURL,
                      allowedImage(url) else { return nil }
                return url.absoluteString
            })
            guard images.count == 1 else { if images.count > 1 { return nil }; continue }
            matched.formUnion(images)
            identities.formUnion(rawCIDs)
        }
        guard matched.count == 1 else { return nil }
        // Multiple CIDs within one storefront are ambiguous even if the display
        // number agrees (e.g. differently padded product editions). Never pick one.
        let retail = identities.filter { $0.storefront == .retail }
        let digital = identities.filter { $0.storefront == .digital }
        let exact = retail.count == 1 ? Array(retail) : (digital.count == 1 ? Array(digital) : [])
        return RecordMatch(images: Array(matched), official: exact.flatMap { DMMPoster.candidates(identity: $0) })
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
    /// Strip only a proven size-only Amazon rendition from the exact ASIN's
    /// primary image. Preserve image ID and host; never request synthetic upscale.
    /// Public naming reference: sqzw-x/mdcx 58e3f930 mdcx/base/web.py
    /// (Amazon AC rendition removal). Independently implemented; no code copied.
    /// Unknown transformations are left untouched; actual decoded pixels decide.
    static func originalImage(_ url: URL) -> URL? {
        guard allowedImage(url) else { return nil }
        let pattern = #"^(/images/I/[A-Za-z0-9+-]{1,100})\._(?:AC_)?SL[1-9][0-9]{1,3}_\.jpg$"#
        guard let m = JRHTML.matches(pattern, url.path).first else { return url }
        guard let host = url.host,
              let original = URL(string: "https://" + host + m[1] + ".jpg"),
              allowedImage(original) else { return nil }
        return original
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
        if let raw = main[0].attrs["data-old-hires"], let url = URL(string: raw), let original = originalImage(url) { return [original.absoluteString] }
        // Only the main product image's actual metadata; never recommendations.
        guard let raw = main[0].attrs["data-a-dynamic-image"], let data = raw.data(using:.utf8),
              let sizes = try? JSONSerialization.jsonObject(with:data) as? [String: [Int]] else { return [] }
        let candidates = sizes.filter { key, size in
            size.count == 2 && size.allSatisfy { $0 > 0 && $0 <= 10000 } && URL(string:key).map(allowedImage) == true
        }.sorted { a,b in
            let x=a.value[0]*a.value[1], y=b.value[0]*b.value[1]
            return x == y ? a.key < b.key : x > y
        }
        return candidates.first.flatMap { URL(string: $0.key).flatMap(originalImage) }.map { [$0.absoluteString] } ?? []
    }
}

/// Independent native implementation of public DMM image URL conventions.
/// Research provenance: Amane v0.21.0 / #424 (7468d8e); no GPL code is incorporated.
/// Admission verifies host, exact path, directory/filename CID and storefront
/// BEFORE removing the narrowly supported resize parameters.
enum DMMPoster {
    struct PathIdentity {
        let linked: TenhowPoster.LinkedCID
        let standardPath: String
        let highPath: String
    }
    static func pathIdentity(_ url: URL) -> PathIdentity? {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
              !url.absoluteString.contains("%"),
              ["pics.dmm.co.jp", "awsimgsrc.dmm.co.jp"].contains(url.host ?? "") else { return nil }
        let aws = url.host == "awsimgsrc.dmm.co.jp"
        let path = url.path
        let relative: String
        if aws {
            guard path.hasPrefix("/pics_dig/") else { return nil }
            relative = String(path.dropFirst("/pics_dig".count))
        } else { relative = path }
        let patterns: [(String, TenhowPoster.Storefront)] = [
            (#"^/digital/video/([a-z0-9_]+)/([a-z0-9_]+)(ps|pl)\.jpg$"#, .digital),
            (#"^/mono/movie/(?:adult/|japanese/)?([a-z0-9_]+)/([a-z0-9_]+)(ps|pl)\.jpg$"#, .retail)]
        for (pattern, store) in patterns {
            guard let m = JRHTML.matches(pattern, relative).first, m[1] == m[2] else { continue }
            let linked = TenhowPoster.LinkedCID(raw: m[1], storefront: store)
            guard linked.number != nil else { return nil }
            let tail = "\(m[1])/\(m[1])ps.jpg"
            let high = store == .retail ? "/mono/movie/" + tail : "/digital/video/" + tail
            // AWS mono copies never have a classification directory.
            if aws && relative != high.replacingOccurrences(of: "ps.jpg", with: m[3] + ".jpg") { return nil }
            let standard = String(relative.dropLast(6)) + "ps.jpg"
            return PathIdentity(linked: linked, standardPath: standard, highPath: high)
        }
        return nil
    }
    static func candidates(metadata: String, number: String) -> [String] {
        guard let url = URL(string: metadata), let identity = pathIdentity(url),
              let wanted = TenhowPoster.number(number), identity.linked.number == wanted,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [] }
        if let query = parts.queryItems {
            let names = query.map(\.name)
            guard Set(names).count == names.count, !query.isEmpty,
                  query.allSatisfy({ item in
                    ["w", "h", "width", "height"].contains(item.name)
                      && item.value?.range(of: #"^[1-9][0-9]{0,3}$"#, options: .regularExpression) != nil
                  }) else { return [] }
        }
        // Fragment does not select an image; only stripped after identity proof.
        let high = "https://awsimgsrc.dmm.co.jp/pics_dig" + identity.highPath
        let standard = "https://pics.dmm.co.jp" + identity.standardPath
        return [high, standard]
    }
    static func candidates(identity: TenhowPoster.LinkedCID) -> [String] {
        guard let number = identity.number else { return [] }
        let base = identity.storefront == .retail ? "mono/movie/adult/" : "digital/video/"
        return candidates(metadata: "https://pics.dmm.co.jp/\(base)\(identity.raw)/\(identity.raw)ps.jpg", number: number)
    }
    static func allowedImage(_ url: URL) -> Bool {
        guard url.query == nil, url.fragment == nil, let identity = pathIdentity(url) else { return false }
        let path = url.host == "awsimgsrc.dmm.co.jp" ? "/pics_dig" + identity.highPath : identity.standardPath
        return url.path == path
    }
}
