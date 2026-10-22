// Independently implemented from bounded anonymous public responses. No AvPlay code.
import Foundation
import CryptoKit
#if canImport(Darwin)
import Darwin
#endif

enum OnlineSource: String, CaseIterable, Identifiable, Sendable {
    case thirdPartyAVDB, javmenu, av01, memojav, missav, jable
    var id: String { rawValue }
    var label: String {
        switch self {
        case .javmenu: return "JavMenu"
        case .thirdPartyAVDB: return "第三方AVDB"
        case .av01: return "AV01"
        case .memojav: return "MemoJav"
        case .missav: return "MissAV"
        case .jable: return "Jable"
        }
    }
}
enum OnlineFailure: Error, LocalizedError, Equatable {
    case noMatch, blocked, tls, parse, timeout, unsafe, tooLarge, cancelled, unsupported, incomplete, drm, keyUnavailable, http(Int)
    var errorDescription: String? {
        switch self {
        case .noMatch: return "未匹配"
        case .blocked: return "来源拒绝访问或要求验证（未绕过限制）"
        case .drm: return "不支持 DRM / SAMPLE-AES 或专有密钥格式"
        case .keyUnavailable: return "标准 AES-128 密钥不可用或格式无效"
        case .incomplete: return "适配未完成（不是未匹配）"
        case .tls: return "TLS 错误（未降低证书验证）"
        case .parse: return "解析失败"
        case .unsupported: return "暂不支持（媒体协议或来源主机尚未验证）"
        case .timeout: return "请求超时"
        case .unsafe: return "来源地址不在安全范围"
        case .tooLarge: return "响应超出大小限制"
        case .cancelled: return "已取消"
        case .http(let status): return "来源 HTTP \(status)"
        }
    }
    static func classify(_ error: Error) -> OnlineFailure {
        if let e = error as? OnlineFailure { return e }
        if error is CancellationError { return .cancelled }
        let code = (error as NSError).code
        if code == NSURLErrorCancelled { return .cancelled }
        if code == NSURLErrorTimedOut { return .timeout }
        if [-1200,-1201,-1202,-1203,-1204,-1205,-1206].contains(code) { return .tls }
        return .parse
    }
}
struct OnlineLine: Identifiable, Equatable, Sendable {
    let source: OnlineSource
    let recordID: String
    let code: String
    let version: String
    let lineKey: String
    var routeDigest: String = "" // One-way binding only; never cache a signed media URL.
    var detailURL: URL? = nil // Public metadata provenance, not a guessed slug or media URL.
    var id: String { source.rawValue + ":" + recordID + ":" + lineKey }
}
struct OnlinePlaybackPlan: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let source: OnlineSource
    let number: String
    let headers: [String:String]
}
enum OnlineIdentity {
    static func key(_ raw: String) -> String? {
        guard let p = CatalogueIdentity.parts(raw), !p.prefix.hasPrefix("FC2") else { return nil }
        // Preserve ALL prefix digits and serial digits. No padding, substring or loose aliases.
        return p.prefix + "-" + p.serial
    }
    static func version(_ candidate: String, number: String, allowVersions: Bool) -> String? {
        guard let wanted = key(number) else { return nil }
        if key(candidate) == wanted { return "原始版本" }
        guard allowVersions else { return nil }
        for suffix in ["ENGLISH-SUBTITLE", "UNCENSORED-LEAK", "CHINESE-SUBTITLE"] {
            let tail = "-" + suffix
            let c = candidate.uppercased()
            if c.hasSuffix(tail), key(String(c.dropLast(tail.count))) == wanted { return suffix }
        }
        return nil
    }
    static func heading(_ text: String, number: String) -> Bool {
        guard let wanted = key(number) else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: wanted)
        return !JRHTML.matches("(?<![A-Z0-9_-])" + escaped + "(?![A-Z0-9_-])", text).isEmpty
    }
}
enum OnlinePolicy {
    static let ua = "AVDB/1.0.2 (iOS; anonymous online playback)"
    // Tight observed set, NOT a wildcard. Unknown origins fail closed.
    static let mediaHosts: Set<String> = ["t26.cdn2020.com", "t27.cdn2020.com", "2608.xbv2608.com", "helvid.com", "video10.memojav.net"]
    static func secure(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.fragment == nil,
              url.port == nil || url.port == 443, let h = url.host?.lowercased(), !h.hasSuffix(".") else { return false }
        return !h.contains(":") && !h.contains("%") && !["localhost","0.0.0.0","127.0.0.1"].contains(h)
    }
    static func metadata(_ url: URL, source: OnlineSource) -> Bool {
        guard secure(url) else { return false }
        let path = url.path
        guard !path.contains(".."), !url.absoluteString.lowercased().contains("%2e") else { return false }
        switch source {
        case .javmenu: return url.host == "javmenu.com" && url.query == nil && path.hasPrefix("/zh/") && path.split(separator: "/").count == 2
        case .thirdPartyAVDB: return url.host == "avdbapi.com" && path == "/api.php/provide/vod"
        case .jable:
            guard url.host == "jable.tv", path.split(separator: "/").count == 2 else { return false }
            if path.hasPrefix("/videos/") { return url.query == nil }
            guard path.hasPrefix("/search/"), let code = path.split(separator: "/").last,
                  OnlineIdentity.key(String(code)) != nil else { return false }
            if url.query == nil { return true }
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            return items.count == 4 && items.filter { $0.name == "mode" && $0.value == "async" }.count == 1
                && items.filter { $0.name == "function" && $0.value == "get_block" }.count == 1
                && items.filter { $0.name == "block_id" && $0.value == "list_videos_videos_list_search_result" }.count == 1
                && items.filter { $0.name == "q" && $0.value == String(code) }.count == 1
        case .missav: return url.host == "missav.fans" && url.query == nil && path.hasPrefix("/cn/")
        case .memojav: return url.host == "memojav.org" && (path.hasPrefix("/video/") || path.hasPrefix("/embed/") || path == "/hls/get_video_info.php")
        case .av01: return (url.host == "www.av01.media" && path.hasPrefix("/api/v1/videos/")) || (url.host == "files.iw01.xyz" && path == "/edge/geo.js" && url.query == "json")
        }
    }
    static func embed(_ url: URL) -> Bool {
        secure(url) && url.host == "upload18.org" && url.path.hasPrefix("/play/") && url.path.split(separator: "/").count == 3 && !url.path.contains("..")
    }
    static func media(_ url: URL) -> Bool {
        secure(url) && mediaHosts.contains(url.host ?? "") && url.path.lowercased().hasSuffix(".m3u8") && !url.path.contains("..")
    }
    static func media(_ url: URL, source: OnlineSource) -> Bool {
        guard media(url) else { return false }
        switch source {
        case .javmenu: return ["t26.cdn2020.com","t27.cdn2020.com","2608.xbv2608.com"].contains(url.host ?? "")
        case .thirdPartyAVDB: return url.host == "helvid.com"
        case .memojav: return url.host == "video10.memojav.net" && url.path.hasPrefix("/stream/")
        // No observed/verified media host: discovery remains real, playback fails closed.
        case .jable, .missav, .av01: return false
        }
    }
    static func bound(_ child: URL, to root: URL) -> Bool {
        // HLS routinely references ../keys and sibling rendition directories.
        // URL resolves dot segments first; security is an exact HTTPS origin, not a folder prefix.
        secure(child) && child.host?.lowercased() == root.host?.lowercased()
    }
    static func discoveredMedia(_ url: URL, source: OnlineSource) -> Bool {
        source == .jable && secure(url) && OnlineMediaScope.publicHost(url.host ?? "")
            && url.path.lowercased().hasSuffix(".m3u8")
    }
    static func headers(referrer: URL) -> [String:String] {
        var value = ["User-Agent": ua, "Referer": referrer.absoluteString]
        if referrer.host == "jable.tv" { value["Origin"] = "https://jable.tv" }
        return value // No account cookies or Authorization; never rotate headers after a 403.
    }
}
// A media origin is either an existing per-provider allowlist entry, or the exact
// public HTTPS origin explicitly issued by an identity-validated Jable detail page.
// No suffix/domain wildcard; requests never follow redirects. DNS preflight is not
// DNS pinning and cannot guarantee the native player's later redirect/DNS behavior.
struct OnlineMediaScope: Sendable {
    let root: URL
    func contains(_ url: URL) -> Bool { OnlinePolicy.bound(url, to: root) }
    static func publicHost(_ host: String) -> Bool {
        let h = host.lowercased()
        guard h.count <= 253, h.contains("."), !h.hasSuffix("."),
              !h.allSatisfy({ $0.isNumber || $0 == "." }),
              !["localhost", "local", "internal", "invalid", "test", "example", "onion"].contains(String(h.split(separator: ".").last ?? "")) else { return false }
        return h.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-"
                && label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
        }
    }
    static func publicAddress(_ address: String) -> Bool {
        if address.contains(":") {
            #if canImport(Darwin)
            var value = in6_addr()
            guard inet_pton(AF_INET6, address, &value) == 1 else { return false }
            return withUnsafeBytes(of: &value) { bytes in
                let a = Array(bytes)
                guard a.count == 16, a[0] & 0xe0 == 0x20 else { return false } // global unicast only
                if a[0] == 0x20 && a[1] == 0x02 { return false } // 6to4 may embed private IPv4
                if a[0] == 0x20 && a[1] == 0x01 {
                    if a[2] == 0x0d && a[3] == 0xb8 { return false } // documentation
                    if a[2] == 0 && a[3] <= 0x2f { return false } // special-use, Teredo, ORCHID
                }
                return true
            }
            #else
            return false
            #endif
        }
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, let a = Int(parts[0]), let b = Int(parts[1]),
              let c = Int(parts[2]), let d = Int(parts[3]), [a,b,c,d].allSatisfy({ (0...255).contains($0) }) else { return false }
        if [0,10,127].contains(a) || a >= 224 { return false }
        if a == 100 && (64...127).contains(b) { return false }
        if a == 169 && b == 254 || a == 172 && (16...31).contains(b) { return false }
        if a == 192 && (b == 168 || b == 0 || b == 88 && c == 99) { return false }
        if a == 198 && (b == 18 || b == 19 || b == 51 && c == 100) { return false }
        if a == 203 && b == 0 && c == 113 { return false }
        return true
    }
    func validateDNS() async throws {
        guard let host = root.host, Self.publicHost(host) else { throw OnlineFailure.unsafe }
        try await Task.detached(priority: .utility) {
            #if canImport(Darwin)
            var result: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(host, nil, nil, &result) == 0, let first = result else { throw OnlineFailure.unsafe }
            defer { freeaddrinfo(first) }
            var cursor: UnsafeMutablePointer<addrinfo>? = first; var count = 0
            while let item = cursor {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let value = item.pointee
                guard value.ai_family == AF_INET || value.ai_family == AF_INET6,
                      let address = value.ai_addr,
                      getnameinfo(address, value.ai_addrlen, &buffer, socklen_t(NI_MAXHOST), nil, 0, NI_NUMERICHOST) == 0,
                      Self.publicAddress(String(cString: buffer)) else { throw OnlineFailure.unsafe }
                count += 1; cursor = value.ai_next
            }
            guard count > 0 else { throw OnlineFailure.unsafe }
            #else
            throw OnlineFailure.unsafe
            #endif
        }.value
        try Task.checkCancellation()
    }
}

struct OnlineManifest {
    let variants: [URL]
    let keys: [URL]
    // RFC 8216 attribute lists: quoted commas are not delimiters; duplicate names
    // and unbalanced quotes are rejected rather than guessing a decryption method.
    static func attributes(_ value: String) throws -> [String:String] {
        var fields: [String] = []; var part = ""; var quoted = false
        for c in value {
            if c == "\"" { quoted.toggle() }
            if c == "," && !quoted { fields.append(part); part = "" } else { part.append(c) }
        }
        guard !quoted else { throw OnlineFailure.parse }; fields.append(part)
        var result: [String:String] = [:]
        for field in fields {
            let pieces = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pieces.count == 2 else { throw OnlineFailure.parse }
            let name = pieces[0].trimmingCharacters(in: .whitespaces)
            var value = pieces[1].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !value.isEmpty, result[name] == nil else { throw OnlineFailure.parse }
            if value.hasPrefix("\"") {
                guard value.hasSuffix("\""), value.count >= 2 else { throw OnlineFailure.parse }
                value = String(value.dropFirst().dropLast())
                guard !value.contains("\"") else { throw OnlineFailure.parse }
            } else if value.contains("\"") { throw OnlineFailure.parse }
            result[name] = value
        }
        return result
    }
    static func parse(_ data: Data, at url: URL, root: URL) throws -> OnlineManifest {
        guard data.count <= 512 * 1024 else { throw OnlineFailure.tooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw OnlineFailure.parse }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("#EXTM3U"), !t.lowercased().contains("<html"), !t.lowercased().contains("<!doctype") else { throw OnlineFailure.parse }
        let lines = t.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard lines.first == "#EXTM3U" else { throw OnlineFailure.parse }
        var variants: [URL] = []; var keys: [URL] = []; var expectsVariant = false; var segments = 0
        func scoped(_ raw: String) throws -> URL {
            if raw.lowercased().hasPrefix("skd:") { throw OnlineFailure.drm }
            guard !raw.contains("{$"), !raw.contains("\\"), !raw.contains(where: { $0.isWhitespace }),
                  let child = URL(string: raw, relativeTo: url)?.absoluteURL.standardized,
                  OnlinePolicy.bound(child, to: root) else { throw OnlineFailure.unsafe }
            return child
        }
        func appendVariant(_ child: URL) throws {
            guard !variants.contains(child) else { return }
            guard variants.count < 6 else { throw OnlineFailure.tooLarge }; variants.append(child)
        }
        for line in lines.dropFirst() where !line.isEmpty {
            if line.hasPrefix("#EXT-X-KEY:") || line.hasPrefix("#EXT-X-SESSION-KEY:") {
                let sessionKey = line.hasPrefix("#EXT-X-SESSION-KEY:")
                let a = try attributes(String(line.split(separator: ":", maxSplits: 1)[1]))
                guard let method = a["METHOD"] else { throw OnlineFailure.parse }
                if method == "NONE" {
                    guard !sessionKey, a.count == 1 else { throw OnlineFailure.parse }; continue
                }
                // Ordinary identity AES-128 is NOT DRM. The normal native HLS
                // client receives the unchanged manifest and handles it itself.
                guard method == "AES-128", a["KEYFORMAT"] == nil || a["KEYFORMAT"] == "identity",
                      a["KEYFORMATVERSIONS"] == nil || a["KEYFORMATVERSIONS"] == "1" else { throw OnlineFailure.drm }
                if let iv = a["IV"] {
                    guard iv.lowercased().hasPrefix("0x"), (3...34).contains(iv.count),
                          iv.dropFirst(2).allSatisfy({ $0.isHexDigit }) else { throw OnlineFailure.parse }
                }
                guard let raw = a["URI"], !raw.isEmpty else { throw OnlineFailure.parse }
                let key = try scoped(raw)
                if !keys.contains(key) { guard keys.count < 16 else { throw OnlineFailure.tooLarge }; keys.append(key) }
                continue
            }
            if line.hasPrefix("#EXT-X-DEFINE:") || line.hasPrefix("#EXT-X-CONTENT-STEERING:") { throw OnlineFailure.unsupported }
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                guard !expectsVariant else { throw OnlineFailure.parse }; expectsVariant = true; continue
            }
            if line.hasPrefix("#") {
                let uriTags = ["#EXT-X-MEDIA:", "#EXT-X-I-FRAME-STREAM-INF:", "#EXT-X-MAP:", "#EXT-X-PART:", "#EXT-X-PRELOAD-HINT:", "#EXT-X-SESSION-DATA:", "#EXT-X-RENDITION-REPORT:"]
                if uriTags.contains(where: { line.hasPrefix($0) }) {
                    let a = try attributes(String(line.split(separator: ":", maxSplits: 1)[1]))
                    if let raw = a["URI"] {
                        let child = try scoped(raw)
                        if line.hasPrefix("#EXT-X-MEDIA:") || line.hasPrefix("#EXT-X-I-FRAME-STREAM-INF:") || line.hasPrefix("#EXT-X-RENDITION-REPORT:") { try appendVariant(child) }
                    }
                } else {
                    for match in JRHTML.matches(#"(?:[:,])\s*URI\s*=\s*\"([^\"]+)\""#, line) { _ = try scoped(match[1]) }
                }
                continue
            }
            let child = try scoped(line)
            if expectsVariant { try appendVariant(child); expectsVariant = false } else { segments += 1 }
        }
        guard !expectsVariant, !variants.isEmpty || (segments > 0 && t.contains("#EXTINF:")),
              !(segments > 0 && lines.contains(where: { $0.hasPrefix("#EXT-X-STREAM-INF:") })) else { throw OnlineFailure.parse }
        return OnlineManifest(variants: variants, keys: keys)
    }
}
final class OnlineTransport: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let loader: (@Sendable (URLRequest) async throws -> Data)?
    init(loader: (@Sendable (URLRequest) async throws -> Data)? = nil) { self.loader = loader; super.init() }
    private func makeSession() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil; c.httpShouldSetCookies = false; c.urlCredentialStorage = nil
        c.urlCache = nil; c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = 12; c.timeoutIntervalForResource = 25
        c.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func fetch(_ url: URL, cap: Int, headers: [String:String] = [:], body: Data? = nil, scope: OnlineMediaScope? = nil) async throws -> Data {
        try Task.checkCancellation()
        if let scope {
            guard scope.contains(url) else { throw OnlineFailure.unsafe }
            if loader == nil { try await scope.validateDNS() }
        } else {
            guard OnlineSource.allCases.contains(where: { OnlinePolicy.metadata(url, source: $0) }) || OnlinePolicy.embed(url) || OnlinePolicy.media(url) else { throw OnlineFailure.unsafe }
        }
        var request = URLRequest(url: url); request.timeoutInterval = 12
        if let body {
            guard url.host == "www.av01.media", url.path == "/api/v1/videos/search", body.count <= 4096 else { throw OnlineFailure.unsafe }
            request.httpMethod = "POST"; request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue(OnlinePolicy.ua, forHTTPHeaderField: "User-Agent")
        for (key,value) in headers where ["User-Agent","Referer","Origin","Accept"].contains(key) {
            if key == "Origin" && value != "https://jable.tv" { throw OnlineFailure.unsafe }
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let loader {
            let data = try await loader(request); try Task.checkCancellation()
            guard data.count <= cap else { throw OnlineFailure.tooLarge }; return data
        }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let r = response as? HTTPURLResponse, r.url == url else { throw OnlineFailure.unsafe }
        if [401,403,429,451].contains(r.statusCode) || (300..<400).contains(r.statusCode) { throw OnlineFailure.blocked }
        if r.statusCode == 404 { throw OnlineFailure.noMatch }
        guard r.statusCode == 200 else { throw OnlineFailure.http(r.statusCode) }
        guard r.expectedContentLength <= Int64(cap) else { throw OnlineFailure.tooLarge }
        var data = Data(); data.reserveCapacity(min(cap, 65536))
        for try await byte in bytes {
            if data.count % 4096 == 0 { try Task.checkCancellation() }
            guard data.count < cap else { throw OnlineFailure.tooLarge }; data.append(byte)
        }
        return data
    }
}

struct OnlineProvider: Sendable {
    let transport: OnlineTransport
    init(transport: OnlineTransport = OnlineTransport()) { self.transport = transport }
    static func routeDigest(_ url: URL) -> String { SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format:"%02x",$0) }.joined() }
    static func api(number: String? = nil, id: String? = nil) -> URL {
        var c = URLComponents(string: "https://avdbapi.com/api.php/provide/vod")!
        c.queryItems = [URLQueryItem(name: "ac", value: "detail")]
        if let number { c.queryItems! += [URLQueryItem(name: "wd", value: number), URLQueryItem(name: "pagesize", value: "5")] }
        if let id { c.queryItems!.append(URLQueryItem(name: "ids", value: id)) }
        return c.url!
    }
    static func page(_ number: String) throws -> URL {
        guard let code = OnlineIdentity.key(number), let u = URL(string: "https://javmenu.com/zh/" + code), OnlinePolicy.metadata(u, source: .javmenu) else { throw OnlineFailure.noMatch }; return u
    }
    static func javmenu(_ data: Data, number: String) throws -> [URL] {
        guard let html = String(data: data, encoding: .utf8) else { throw OnlineFailure.parse }
        let tree = try JRHTML.tree(html)
        let canonical = tree.all { $0.tag == "link" && $0.attrs["rel"]?.lowercased() == "canonical" }.compactMap { $0.attrs["href"] }
        let expected = try page(number)
        guard canonical == [expected.absoluteString], tree.all({ $0.tag == "h1" }).contains(where: { OnlineIdentity.heading($0.text, number: number) }) else {
            if html.lowercased().contains("just a moment") || html.lowercased().contains("cf-chl-") { throw OnlineFailure.blocked }
            throw OnlineFailure.noMatch
        }
        var seen = Set<URL>()
        return tree.all { $0.tag == "a" && $0.has("data-m3u8") }.compactMap { n in
            guard let raw = n.attrs["data-m3u8"], let u = URL(string: raw), OnlinePolicy.media(u, source: .javmenu), seen.insert(u).inserted else { return nil }; return u
        }.prefix(8).map { $0 }
    }
    static func records(_ data: Data) throws -> [[String:Any]] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String:Any], (obj["code"] as? Int) == 1, let list = obj["list"] as? [[String:Any]] else { throw OnlineFailure.parse }
        return Array(list.prefix(5))
    }
    static func identifier(_ item: [String:Any]) -> String? {
        let value: String
        if let s = item["id"] as? String { value = s } else if let n = item["id"] as? Int { value = String(n) } else { return nil }
        return !value.isEmpty && value.count <= 16 && value.allSatisfy(\.isNumber) ? value : nil
    }
    static func episodes(_ record: [String:Any]) -> [(String,URL)] {
        guard let episodes = record["episodes"] as? [String:Any], let servers = episodes["server_data"] as? [String:Any] else { return [] }
        return servers.keys.sorted().prefix(8).compactMap { key in
            guard key.count < 100, let row = servers[key] as? [String:Any], let link = row["link_embed"] as? String, let url = URL(string: link), OnlinePolicy.embed(url) else { return nil }; return (key,url)
        }
    }
    static func config(_ data: Data) throws -> URL {
        guard let html = String(data: data, encoding: .utf8),
              let match = JRHTML.matches(#"window\.PLAYER_CONFIG\s*=\s*(\{.*?\})\s*;"#, html).first,
              let json = match[1].data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: json) as? [String:Any],
              let raw = object["m3u8"] as? String, let url = URL(string: raw), OnlinePolicy.media(url, source: .thirdPartyAVDB) else { throw OnlineFailure.parse }
        return url // literal JSON only; no JS evaluation, decoders or tokens
    }
    func discover(_ source: OnlineSource, number: String, versions: Bool) async throws -> [OnlineLine] {
        guard let exact = OnlineIdentity.key(number) else { throw OnlineFailure.noMatch }
        if source == .javmenu {
            let urls = try Self.javmenu(try await transport.fetch(Self.page(exact), cap: 2*1024*1024), number: exact)
            return urls.indices.map { OnlineLine(source: source, recordID: exact, code: exact, version: "原始版本", lineKey: String($0), routeDigest: Self.routeDigest(urls[$0])) }
        }
        if source != .thirdPartyAVDB { return try await discoverAdditional(source, number: exact, versions: versions) }
        let list = try Self.records(try await transport.fetch(Self.api(number: exact), cap: 1024*1024))
        return list.flatMap { record -> [OnlineLine] in
            guard let code = record["movie_code"] as? String, let version = OnlineIdentity.version(code, number: exact, allowVersions: versions), let id = Self.identifier(record) else { return [] }
            return Self.episodes(record).map { OnlineLine(source: source, recordID: id, code: code, version: version, lineKey: $0.0) }
        }
    }
    func resolve(_ line: OnlineLine, number: String, versions: Bool) async throws -> OnlinePlaybackPlan {
        try Task.checkCancellation()
        guard OnlineIdentity.version(line.code, number: number, allowVersions: versions) != nil else { throw OnlineFailure.noMatch }
        if line.source != .javmenu && line.source != .thirdPartyAVDB { return try await resolveAdditional(line, number: number, versions: versions) }
        let media: URL; let referrer: URL
        if line.source == .javmenu {
            referrer = try Self.page(number)
            let fresh = try Self.javmenu(try await transport.fetch(referrer, cap: 2*1024*1024), number: number)
            guard !line.routeDigest.isEmpty, let bound = fresh.first(where: { Self.routeDigest($0) == line.routeDigest }) else { throw OnlineFailure.noMatch }
            media = bound // Changed/expired candidate requires an explicit new query, never another line.
        } else {
            let records = try Self.records(try await transport.fetch(Self.api(id: line.recordID), cap: 1024*1024))
            guard let record = records.first(where: { Self.identifier($0) == line.recordID }), let code = record["movie_code"] as? String, code == line.code,
                  OnlineIdentity.version(code, number: number, allowVersions: versions) != nil,
                  let embed = Self.episodes(record).first(where: { $0.0 == line.lineKey })?.1 else { throw OnlineFailure.noMatch }
            referrer = embed
            media = try Self.config(try await transport.fetch(embed, cap: 2*1024*1024, headers: OnlinePolicy.headers(referrer: URL(string: "https://avdbapi.com/")!)))
        }
        return try await validatedPlan(media:media, referrer:referrer, line:line, number:number)
    }
    func validatedPlan(media: URL, referrer: URL, line: OnlineLine, number: String, pageIssued: Bool = false) async throws -> OnlinePlaybackPlan {
        guard OnlinePolicy.media(media, source: line.source) || (pageIssued && OnlinePolicy.discoveredMedia(media, source: line.source)) else { throw OnlineFailure.unsafe }
        let headers = OnlinePolicy.headers(referrer: referrer)
        let scope = OnlineMediaScope(root: media)
        var pending: [(URL,Int)] = [(media,0)]; var seen = Set<URL>(); var keys = Set<URL>(); var hasLeaf = false
        // Validate every adaptive/rendition playlist, bounded across the whole graph.
        while !pending.isEmpty {
            let (url,depth) = pending.removeFirst()
            guard !seen.contains(url) else { continue }
            guard seen.count < 8, depth <= 3 else { throw OnlineFailure.tooLarge }
            seen.insert(url)
            let manifest = try OnlineManifest.parse(try await transport.fetch(url, cap: 512*1024, headers: headers, scope: scope), at: url, root: media)
            for key in manifest.keys { keys.insert(key) }
            guard keys.count <= 16 else { throw OnlineFailure.tooLarge }
            if manifest.variants.isEmpty { hasLeaf = true }
            pending += manifest.variants.map { ($0,depth+1) }
        }
        guard hasLeaf else { throw OnlineFailure.parse }
        // Probe only ordinary, publicly provided identity AES-128 keys. Never
        // derive, persist, log, rewrite or decrypt them; the native HLS client
        // subsequently consumes the original playlist. DRM fails above first.
        for key in keys.sorted(by: { $0.absoluteString < $1.absoluteString }) {
            do {
                let bytes = try await transport.fetch(key, cap: 64*1024, headers: headers, scope: scope)
                guard bytes.count == 16 else { throw OnlineFailure.keyUnavailable }
            } catch let failure as OnlineFailure {
                if failure == .noMatch || failure == .tooLarge || failure == .parse { throw OnlineFailure.keyUnavailable }
                throw failure
            }
        }
        try Task.checkCancellation()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--online-playback-fixture"), let neutral = Bundle.main.url(forResource: "neutral-subtitle", withExtension: "mp4") {
            return OnlinePlaybackPlan(url: neutral, source: line.source, number: number, headers: [:])
        }
        #endif
        return OnlinePlaybackPlan(url: media, source: line.source, number: number, headers: headers)
    }
}

#if DEBUG
// Synthetic text only. Used through the REAL detail panel, provider parsers and
// manifest validation; only the final media is the bundled self-made neutral clip.
enum OnlineNeutralFixture {
    static func response(_ url: URL) throws -> Data {
        let media = "https://2608.xbv2608.com/neutral/demo/index.m3u8"
        if ProcessInfo.processInfo.arguments.contains("--online-playback-failures") {
            if url.host == "avdbapi.com" { throw OnlineFailure.blocked }
            if url.host == "missav.fans" { throw OnlineFailure.unsupported }
            if url.host == "memojav.org" { throw OnlineFailure.tls }
            if url.host == "www.av01.media" { return Data("{\"videos\":[]}".utf8) }
        }
        if url.host == "jable.tv" {
            if url.path.hasPrefix("/search/") { return Data("<a href='/videos/demo-123/'>DEMO-123 Neutral</a>".utf8) }
            return Data("<meta property='og:url' content='https://jable.tv/videos/demo-123/'><section class='video-info'><h4>DEMO-123 Neutral</h4></section><script>var hlsUrl = 'https://neutral.jable-cdn.net/demo/index.m3u8';</script>".utf8)
        }
        if url.host == "neutral.jable-cdn.net" {
            if url.path.hasSuffix(".m3u8") { return Data("#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"key\"\n#EXTINF:4,\nneutral.ts\n#EXT-X-ENDLIST\n".utf8) }
            // Deliberately malformed OWN neutral fixture, never a third-party key.
            return Data(repeating: 0, count: 15)
        }
        if url.host == "javmenu.com" {
            return Data("<link rel='canonical' href='https://javmenu.com/zh/DEMO-123'><h1>DEMO-123 Neutral</h1><a data-m3u8='\(media)'>1</a>".utf8)
        }
        if url.host == "avdbapi.com" {
            let record: [String:Any] = ["id":1,"movie_code":"DEMO-123","episodes":["server_data":["Full":["link_embed":"https://upload18.org/play/neutral/demo"]]]]
            return try JSONSerialization.data(withJSONObject: ["code":1,"list":[record]])
        }
        if url.host == "upload18.org" { return Data("<script>window.PLAYER_CONFIG = {\"m3u8\":\"\(media.replacingOccurrences(of: "2608.xbv2608.com", with: "helvid.com"))\"};</script>".utf8) }
        if url.host == "2608.xbv2608.com" || url.host == "helvid.com" { return Data("#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXTINF:4,\nneutral.ts\n#EXT-X-ENDLIST\n".utf8) }
        throw OnlineFailure.unsafe
    }
}
#endif
