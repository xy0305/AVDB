import Foundation

/// Independent parser of public JavBus detail markup; no GPL implementation copied.
/// Evidence: z291173301/MDCx e037880e0add4433bcf0ab8c926b836ec04801f1
/// mdcx/crawlers/javbus.py getWebNumber/getCover; public live details 2026-10-19.
/// Deliberately supports only the evidenced first-party /pics/cover/ main jacket.
/// No guessed CID, thumbnail rewrite, search fallback, third-party CDN or cookies.
enum JavBusPoster {
    static func number(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard s.range(of: #"^[A-Z]{2,12}-[0-9]{2,5}$"#, options: .regularExpression) != nil,
              let digits = s.split(separator: "-").last, let n = Int(digits), n > 0 else { return nil }
        // Keep complete prefix AND digit string; no FC2, suffix, padding or alias guess.
        return s
    }
    static func clean(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "www.javbus.com" && url.user == nil
            && url.password == nil && url.port == nil && url.query == nil && url.fragment == nil
            && !url.absoluteString.contains("%")
    }
    static func page(number raw: String) -> URL? {
        number(raw).flatMap { URL(string: "https://www.javbus.com/" + $0) }
    }
    static func allowedPage(_ url: URL, number raw: String) -> Bool {
        guard let n = number(raw), clean(url) else { return false }
        return url.path == "/" + n
    }
    static func allowedImage(_ url: URL) -> Bool {
        clean(url) && url.path.range(of: #"^/pics/cover/[A-Za-z0-9]{1,40}_b\.jpg$"#, options: .regularExpression) != nil
    }
    static func images(html: String, number raw: String, finalURL: URL) throws -> [String] {
        guard html.utf8.count <= 768 * 1024, let wanted = number(raw), allowedPage(finalURL, number: wanted) else { return [] }
        let lower = html.lowercased()
        for marker in ["age verification", "id=\"ageverify\"", "driver-verify", "cf-chl-", "challenge-platform", "captcha", "just a moment"] {
            if lower.contains(marker) { return [] }
        }
        let tree = try JRHTML.tree(html)
        let movies = tree.all { $0.tag == "div" && $0.cls("movie") }
        guard movies.count == 1 else { return [] }
        let movie = movies[0]
        let infos = movie.all { $0.tag == "div" && $0.cls("info") }
        guard infos.count == 1 else { return [] }
        var identities: [String] = []
        for p in infos[0].all({ $0.tag == "p" }) {
            try Task.checkCancellation()
            let spans = p.children.filter { $0.tag == "span" }
            guard let header = spans.first, header.cls("header"),
                  ["識別碼:", "识别码:"].contains(header.text.trimmingCharacters(in: .whitespacesAndNewlines)) else { continue }
            guard spans.count == 2, let n = number(spans[1].text) else { return [] }
            identities.append(n)
        }
        guard identities == [wanted] else { return [] }
        let mains = movie.all { $0.tag == "a" && $0.cls("bigImage") }
        guard mains.count == 1, let href = mains[0].attrs["href"],
              let url = URL(string: href, relativeTo: finalURL)?.absoluteURL,
              allowedImage(url) else { return [] }
        return [url.absoluteString] // href, never an img src or gallery sample.
    }
}
