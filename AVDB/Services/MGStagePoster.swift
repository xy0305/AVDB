import Foundation

/// Conservative MGStage record adapter. No search, title matching, maker guessing,
/// prefix removal, or URL enlargement. Only IDs already evidenced by official
/// image metadata can initiate one exact detail request. Public schema reference:
/// MGStage's EnlargeImage link (independent implementation; no crawler code copied).
enum MGStagePoster {
    static func number(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard value.range(of: #"^(?:[0-9]{1,4})?[A-Z]{2,12}-[0-9]{2,6}$"#, options: .regularExpression) != nil else { return nil }
        return value
    }

    /// Both directory CID and front/wrap basename must be identical to the full
    /// supplied number. In particular 300MIUM is NOT MIUM or 200MIUM.
    static func evidencedID(number raw: String, metadata: [String]) -> String? {
        guard let id = number(raw) else { return nil }
        return metadata.contains { value in
            guard let url = URL(string: value) else { return false }
            return imageIdentity(url) == id
        } ? id : nil
    }

    static func imageIdentity(_ url: URL) -> String? {
        guard url.scheme == "https", url.host?.lowercased() == "image.mgstage.com",
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil,
              !url.absoluteString.contains("%"), !url.path.contains("..") else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count == 5, parts[0] == "images",
              parts[1].range(of: #"^[a-z0-9_]+$"#, options: .regularExpression) != nil,
              let id = number(parts[2] + "-" + parts[3]) else { return nil }
        let suffix = id.lowercased() + ".jpg"
        guard ["pf_e_", "pf_o1_", "pb_e_"].contains(where: { parts[4] == $0 + suffix }) else { return nil }
        return id
    }

    static func page(_ id: String) -> URL? {
        guard number(id) == id else { return nil }
        return URL(string: "https://www.mgstage.com/product/product_detail/" + id + "/")
    }

    static func allowedPage(_ url: URL, id: String) -> Bool {
        guard let expected = page(id) else { return false }
        return url.absoluteString == expected.absoluteString
    }

    static func attributes(_ tag: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(pattern: #"([A-Za-z_:][A-Za-z0-9_:.-]*)\s*=\s*(["'])(.*?)\2"#, options: [.dotMatchesLineSeparators]) else { return [:] }
        var result: [String: String] = [:]
        for match in regex.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
            guard let key = Range(match.range(at: 1), in: tag), let value = Range(match.range(at: 3), in: tag) else { continue }
            let name = tag[key].lowercased()
            // Duplicate critical attributes are ambiguous, not last-one-wins.
            guard result[name] == nil else { return [:] }
            result[name] = String(tag[value])
        }
        return result
    }

    static func images(html: String, pageURL: URL, id: String) -> [String] {
        guard allowedPage(pageURL, id: id), html.utf8.count <= 768 * 1024,
              !html.localizedCaseInsensitiveContains("captcha"),
              !html.localizedCaseInsensitiveContains("request blocked"),
              let tags = try? NSRegularExpression(pattern: #"<(?:a|link)\b[^>]*>"#, options: [.caseInsensitive]) else { return [] }
        // Remove comments/script blocks so non-DOM text cannot manufacture a cover.
        let clean = html.replacingOccurrences(of: #"<!--[\s\S]*?-->|<script\b[^>]*>[\s\S]*?</script\s*>"#, with: "", options: [.regularExpression, .caseInsensitive])
        var found = Set<String>()
        for match in tags.matches(in: clean, range: NSRange(clean.startIndex..., in: clean)) {
            guard let range = Range(match.range, in: clean) else { continue }
            let attrs = attributes(String(clean[range]))
            if attrs["rel"]?.lowercased() == "canonical" {
                guard let href = attrs["href"], let canonical = URL(string: href), allowedPage(canonical, id: id) else { return [] }
            }
            guard attrs["id"] == "EnlargeImage", let href = attrs["href"],
                  let image = URL(string: href), imageIdentity(image) == id,
                  ["pf_e_", "pf_o1_"].contains(where: { image.lastPathComponent.hasPrefix($0) }) else { continue }
            found.insert(image.absoluteString)
        }
        // No fallback to og:image, enlarge_image thumbnail, sample-photo or pb_e.
        return found.count == 1 ? found.sorted() : []
    }
}

private final class MGStageRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Age/login/region redirects terminate; never inject an age/captcha cookie.
        completionHandler(nil)
    }
}

extension MGStagePoster {
    static func discover(id: String, timeout: TimeInterval) async -> [String] {
        guard timeout > 0, !Task.isCancelled, let url = page(id) else { return [] }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = timeout; config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config, delegate: MGStageRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            var request = URLRequest(url: url); request.timeoutInterval = timeout
            request.setValue("text/html", forHTTPHeaderField: "Accept")
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let final = response.url, allowedPage(final, id: id),
                  http.mimeType == "text/html", response.expectedContentLength <= 768 * 1024 else { return [] }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 768 * 1024 else { return [] }
                data.append(byte)
            }
            guard !Task.isCancelled, let html = String(data: data, encoding: .utf8) else { return [] }
            return images(html: html, pageURL: final, id: id)
        } catch { return [] }
    }
}
