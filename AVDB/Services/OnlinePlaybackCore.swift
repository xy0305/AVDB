// Independently implemented from bounded anonymous public responses. No AvPlay code.
import Foundation

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
    case noMatch, blocked, tls, parse, timeout, unsafe, tooLarge, cancelled, unsupported, http(Int)
    var errorDescription: String? {
        switch self {
        case .noMatch: return "未匹配"
        case .blocked: return "访问受限（含受保护清单；不会请求密钥或绕过限制）"
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
        case .jable: return url.host == "jable.tv" && url.query == nil && (path.hasPrefix("/search/") || path.hasPrefix("/videos/"))
        case .missav: return url.host == "missav.ws" && url.query == nil && path.hasPrefix("/cn/")
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
        guard secure(child), child.host == root.host else { return false }
        let folder = root.deletingLastPathComponent().path + "/"
        return child.path.hasPrefix(folder) && !child.path.contains("..") && !child.absoluteString.lowercased().contains("%2e")
    }
    static func headers(referrer: URL) -> [String:String] {
        // No account cookies, Authorization, Origin guesses or alternate header spraying.
        ["User-Agent": ua, "Referer": referrer.absoluteString]
    }
}
struct OnlineManifest {
    let variants: [URL]
    static func parse(_ data: Data, at url: URL, root: URL) throws -> OnlineManifest {
        guard data.count <= 512 * 1024, let text = String(data: data, encoding: .utf8) else { throw OnlineFailure.parse }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("#EXTM3U"), !t.lowercased().contains("<html"), !t.lowercased().contains("<!doctype") else { throw OnlineFailure.parse }
        // Protected playlists fail BEFORE reading any key URI or requesting any segment.
        guard !t.contains("#EXT-X-KEY:"), !t.contains("#EXT-X-SESSION-KEY:"), !t.contains("#EXT-X-SESSION-DATA:"), !t.contains("#EXT-X-DEFINE:") else { throw OnlineFailure.blocked }
        let lines = t.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var variants: [URL] = []; var expectsVariant = false; var segments = 0
        for line in lines where !line.isEmpty {
            if line.hasPrefix("#EXT-X-STREAM-INF:") { expectsVariant = true; continue }
            if line.hasPrefix("#") {
                // URI-bearing alternate audio, map and subtitles must also be source/path bound.
                for match in JRHTML.matches(#"URI\s*=\s*"([^"]+)""#, line) {
                    guard let u = URL(string: match[1], relativeTo: url)?.absoluteURL, OnlinePolicy.bound(u, to: root) else { throw OnlineFailure.unsafe }
                    // Alternate rendition manifests are not silently left unvalidated.
                    if u.path.hasSuffix(".m3u8") { throw OnlineFailure.blocked }
                }
                continue
            }
            guard let child = URL(string: line, relativeTo: url)?.absoluteURL, OnlinePolicy.bound(child, to: root) else { throw OnlineFailure.unsafe }
            if expectsVariant {
                guard OnlinePolicy.media(child), variants.count < 6 else { throw OnlineFailure.unsafe }
                variants.append(child); expectsVariant = false
            } else { segments += 1 }
        }
        guard !expectsVariant, !variants.isEmpty || (segments > 0 && t.contains("#EXTINF:")), !(segments > 0 && !variants.isEmpty) else { throw OnlineFailure.parse }
        return OnlineManifest(variants: variants)
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
    func fetch(_ url: URL, cap: Int, headers: [String:String] = [:], body: Data? = nil) async throws -> Data {
        try Task.checkCancellation()
        guard OnlineSource.allCases.contains(where: { OnlinePolicy.metadata(url, source: $0) }) || OnlinePolicy.embed(url) || OnlinePolicy.media(url) else { throw OnlineFailure.unsafe }
        var request = URLRequest(url: url); request.timeoutInterval = 12
        if let body {
            guard url.host == "www.av01.media", url.path == "/api/v1/videos/search", body.count <= 4096 else { throw OnlineFailure.unsafe }
            request.httpMethod = "POST"; request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue(OnlinePolicy.ua, forHTTPHeaderField: "User-Agent")
        for (key,value) in headers where ["User-Agent","Referer"].contains(key) { request.setValue(value, forHTTPHeaderField: key) }
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
            return urls.indices.map { OnlineLine(source: source, recordID: exact, code: exact, version: "原始版本", lineKey: String($0)) }
        }
        if source != .thirdPartyAVDB { return try await discoverAdditional(source, number: exact) }
        let list = try Self.records(try await transport.fetch(Self.api(number: exact), cap: 1024*1024))
        return list.flatMap { record -> [OnlineLine] in
            guard let code = record["movie_code"] as? String, let version = OnlineIdentity.version(code, number: exact, allowVersions: versions), let id = Self.identifier(record) else { return [] }
            return Self.episodes(record).map { OnlineLine(source: source, recordID: id, code: code, version: version, lineKey: $0.0) }
        }
    }
    func resolve(_ line: OnlineLine, number: String, versions: Bool) async throws -> OnlinePlaybackPlan {
        try Task.checkCancellation()
        guard OnlineIdentity.version(line.code, number: number, allowVersions: versions) != nil else { throw OnlineFailure.noMatch }
        if line.source != .javmenu && line.source != .thirdPartyAVDB { return try await resolveAdditional(line, number: number) }
        let media: URL; let referrer: URL
        if line.source == .javmenu {
            referrer = try Self.page(number)
            let fresh = try Self.javmenu(try await transport.fetch(referrer, cap: 2*1024*1024), number: number)
            guard let index = Int(line.lineKey), fresh.indices.contains(index) else { throw OnlineFailure.noMatch }; media = fresh[index]
        } else {
            let records = try Self.records(try await transport.fetch(Self.api(id: line.recordID), cap: 1024*1024))
            guard let record = records.first(where: { Self.identifier($0) == line.recordID }), let code = record["movie_code"] as? String, code == line.code,
                  OnlineIdentity.version(code, number: number, allowVersions: versions) != nil,
                  let embed = Self.episodes(record).first(where: { $0.0 == line.lineKey })?.1 else { throw OnlineFailure.noMatch }
            referrer = embed
            media = try Self.config(try await transport.fetch(embed, cap: 2*1024*1024, headers: OnlinePolicy.headers(referrer: URL(string: "https://avdbapi.com/")!))))
        }
        return try await validatedPlan(media:media, referrer:referrer, line:line, number:number)
    }
    func validatedPlan(media: URL, referrer: URL, line: OnlineLine, number: String) async throws -> OnlinePlaybackPlan {
        guard OnlinePolicy.media(media, source:line.source) else { throw OnlineFailure.unsafe }
        let headers = OnlinePolicy.headers(referrer: referrer)
        let master = try OnlineManifest.parse(try await transport.fetch(media, cap: 512*1024, headers: headers), at: media, root: media)
        // Validate ALL allowed variants; no unvalidated adaptive branch can be played.
        for variant in master.variants {
            let child = try OnlineManifest.parse(try await transport.fetch(variant, cap: 512*1024, headers: headers), at: variant, root: media)
            guard child.variants.isEmpty else { throw OnlineFailure.blocked }
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
