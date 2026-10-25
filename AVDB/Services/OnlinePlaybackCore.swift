// Independently implemented from bounded anonymous public responses. No AvPlay code.
import Foundation
import CryptoKit
#if canImport(Darwin)
import Darwin
#endif

enum OnlineSource: String, CaseIterable, Identifiable, Sendable {
    case jable, missav, av123, memojav
    var id: String { rawValue }
    var label: String { switch self { case .jable: return "Jable"; case .missav: return "MissAV"; case .av123: return "123AV"; case .memojav: return "MemoJav" } }
}
enum OnlineFailure: Error, LocalizedError, Equatable {
    case noMatch, blocked, tls, parse, timeout, unsafe, resolver, tooLarge, cancelled, unsupported, incomplete, drm, keyUnavailable, http(Int)
    case safe(PlaybackDiagnostic)
    case diagnostic(stage: String, host: String, reason: String)
    var errorDescription: String? {
        switch self {
        case .safe(let value): return value.display
        case .diagnostic: return presentation(at: .unknown).display
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
        case .resolver: return "来源域名暂时无法解析（未判定地址不安全，也未固定 DNS）"
        case .tooLarge: return "响应超出大小限制"
        case .cancelled: return "已取消"
        case .http(let status): return "来源 HTTP \(status)"
        }
    }
    static func classify(_ error: Error) -> OnlineFailure {
        if let e = error as? OnlineFailure { return e }
        if error is CancellationError { return .cancelled }
        let system = error as NSError
        guard system.domain == NSURLErrorDomain else { return .safe(.system(error, stage: .unknown)) }
        let code = system.code
        if code == NSURLErrorCancelled { return .cancelled }
        if code == NSURLErrorTimedOut { return .timeout }
        if [-1200,-1201,-1202,-1203,-1204,-1205,-1206].contains(code) { return .tls }
        if [NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed].contains(code) { return .resolver }
        return .safe(.system(error, stage: .unknown))
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
    static let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    static func secure(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.fragment == nil,
              url.port == nil || url.port == 443, let h = url.host?.lowercased(), OnlineMediaScope.publicHost(h) else { return false }
        return !url.absoluteString.contains(where: { $0.asciiValue.map { $0 < 32 || $0 == 127 } == true })
    }
    static func addressRejection(_ url: URL) -> String {
        if url.scheme != "https" || url.user != nil || url.password != nil || url.fragment != nil || !(url.port == nil || url.port == 443) { return "地址格式：仅允许无凭据、无片段的 HTTPS/443" }
        guard let host = url.host, OnlineMediaScope.publicHost(host) else { return "host：域名格式或范围不允许" }
        return "path/query：不符合此来源的精确公开路由或参数规则"
    }
    static func metadata(_ url: URL, source: OnlineSource) -> Bool {
        guard secure(url), !url.path.contains(".."), !url.absoluteString.lowercased().contains("%2e") else { return false }
        let p = url.path, parts = p.split(separator: "/")
        switch source {
        case .jable:
            guard url.host == "jable.tv", parts.count == 2 else { return false }
            if p.hasPrefix("/videos/") { return url.query == nil }
            guard p.hasPrefix("/search/"), OnlineIdentity.key(String(parts[1])) != nil else { return false }
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            return items.isEmpty || items == JableAdapter.searchItems(String(parts[1]))
        case .missav:
            return url.host == "missav.ws" && url.query == nil && (p.hasPrefix("/en/") || p.hasPrefix("/dm339/en/")) && (parts.count == 2 || parts.count == 3 || parts.count == 4)
        case .av123:
            guard url.host == "123av.com" else { return false }
            if p.hasPrefix("/en/v/") { return parts.count == 3 && url.query == nil }
            let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            return p == "/en/search" && q.count == 1 && q[0].name == "keyword" && OnlineIdentity.key(q[0].value ?? "") != nil
        case .memojav:
            guard url.host == "memojav.org" else { return false }
            if p.hasPrefix("/video/") || p.hasPrefix("/embed/") { return parts.count == 2 && url.query == nil && OnlineIdentity.key(String(parts[1])) != nil }
            let q = URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems ?? []
            return p == "/hls/get_video_info.php" && q.count == 3 && Set(q.map(\.name)) == Set(["id","sig","sts"]) && q.allSatisfy { ($0.value?.count ?? 0) <= 64 }
        }
    }
    static func embed(_ url: URL) -> Bool {
        guard secure(url), url.host == "sadie-shop.site" else { return false }
        let parts = url.path.split(separator:"/")
        let q = URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems ?? []
        if url.path == "/stream" { return q.count <= 2 && Set(q.map(\.name)).isSubset(of:Set(["id","poster"])) && q.contains { $0.name == "id" && safeID($0.value ?? "") } }
        return parts.count == 2 && parts[0] == "e" && safeID(String(parts[1])) && q.count <= 1 && q.allSatisfy { $0.name == "poster" && ($0.value?.count ?? 0) < 2048 }
    }
    static func safeID(_ raw:String) -> Bool { !raw.isEmpty && raw.count <= 64 && raw.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 95 } }
    static func media(_ url: URL) -> Bool { media(url,source:.memojav) || media(url,source:.av123) }
    static func media(_ url: URL, source: OnlineSource) -> Bool {
        guard secure(url), url.path.hasSuffix(".m3u8"), !url.path.contains("..") else { return false }
        switch source {
        case .memojav: return url.host == "video10.memojav.net" && url.path.hasPrefix("/stream/")
        case .av123: return url.host == "jzxz.freeboldspirit.site" && url.path.hasPrefix("/oo5/")
        default: return false
        }
    }
    static func bound(_ child: URL, to root: URL) -> Bool { secure(child) && child.host?.lowercased() == root.host?.lowercased() }
    static func discoveredMedia(_ url: URL, source: OnlineSource) -> Bool {
        guard secure(url), url.path.lowercased().hasSuffix(".m3u8"), !url.path.contains("..") else { return false }
        if source == .jable { return true } // Exact page-issued HTTPS origin, DNS and all HLS children checked; no wildcard list.
        if source == .missav { return url.host?.hasPrefix("surrit.") == true }
        return media(url,source:source)
    }
    static func headers(referrer:URL) -> [String:String] {
        var h = ["User-Agent":ua,"Referer":referrer.absoluteString]
        if let host=referrer.host, ["jable.tv","missav.ws"].contains(host) { h["Origin"]="https://"+host }
        return h
    }
}
// A media origin is either an existing per-provider allowlist entry, or the exact
// public HTTPS origin explicitly issued by an identity-validated Jable detail page.
// No suffix/domain wildcard; requests never follow redirects. DNS preflight is not
// DNS pinning and cannot guarantee the native player's later redirect/DNS behavior.
// Immutable per-transport policy. Only the on-device preference opts in; never
// changes system DNS/proxy settings, hostname, TLS evaluation or redirect policy.
enum OnlineDNSMode: String, Sendable { case strict, systemProxy }

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
                guard a.count == 16 else { return false }
                // Apple may return IPv4-mapped IPv6. Classify the embedded IPv4,
                // never accept mapped private/reserved addresses as public IPv6.
                if a.prefix(10).allSatisfy({ $0 == 0 }) && a[10] == 255 && a[11] == 255 {
                    return publicAddress(a.suffix(4).map(String.init).joined(separator: "."))
                }
                // Well-known NAT64 prefix on IPv6-only Apple networks (RFC 6052).
                if Array(a.prefix(12)) == [0,100,255,155,0,0,0,0,0,0,0,0] {
                    return publicAddress(a.suffix(4).map(String.init).joined(separator: "."))
                }
                guard a[0] & 0xe0 == 0x20 else { return false } // global unicast only
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
    static func dnsRejection(_ address: String) -> String? {
        if publicAddress(address) { return nil }
        let a = address.lowercased()
        if a.hasPrefix("198.18.") || a.hasPrefix("198.19.") || a.hasPrefix("fd27:") || a.hasPrefix("::ffff:198.18.") || a.hasPrefix("::ffff:198.19.") {
            return "DNS 返回代理/基准测试保留地址（可能由 VPN 合成）；严格模式已在请求前停止。如信任当前系统代理，可在本面板开启“系统代理/Fake-IP兼容”（仅支持 198.18.0.0/15）；应用未更改网络设置"
        }
        return "DNS 返回非公网、私网或保留地址；已在请求前停止"
    }
    // Only RFC 2544's exact /15 is recognized. No fd27/ULA exception.
    // Decode mapped and well-known NAT64 wrappers before classifying the IPv4.
    static func syntheticAddress(_ address: String) -> Bool {
        if address.contains(":") {
            #if canImport(Darwin)
            var value = in6_addr()
            guard inet_pton(AF_INET6, address, &value) == 1 else { return false }
            return withUnsafeBytes(of: &value) { bytes in
                let a = Array(bytes)
                let mapped = a.prefix(10).allSatisfy { $0 == 0 } && a[10] == 255 && a[11] == 255
                let nat64 = Array(a.prefix(12)) == [0,100,255,155,0,0,0,0,0,0,0,0]
                return (mapped || nat64) && syntheticAddress(a.suffix(4).map(String.init).joined(separator: "."))
            }
            #else
            return false
            #endif
        }
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let a = Int(parts[0]), let b = Int(parts[1]), let c = Int(parts[2]), let d = Int(parts[3]),
              [a,b,c,d].allSatisfy({ (0...255).contains($0) }) else { return false }
        return a == 198 && (b == 18 || b == 19)
    }
    static func validateAddresses(_ addresses: [String], root: URL, mode: OnlineDNSMode = .strict, approvedOrigin: Bool = false) throws {
        guard OnlinePolicy.secure(root) else { throw diagnostic(root, stage: "DNS", reason: "域名格式不被允许") }
        guard !addresses.isEmpty else { throw diagnostic(root, stage: "DNS", reason: "解析无结果（空地址集）") }
        guard addresses.count <= 32 else { throw diagnostic(root, stage: "DNS", reason: "解析地址数量超限") }
        for address in addresses {
            if mode == .systemProxy && approvedOrigin && syntheticAddress(address) { continue }
            if let reason = dnsRejection(address) { throw diagnostic(root, stage: "DNS", reason: reason) }
        }
    }
    static func diagnostic(_ url: URL, stage: String, reason: String) -> OnlineFailure {
        .diagnostic(stage: stage, host: url.host.flatMap { publicHost($0) ? $0 : nil } ?? "无效域名", reason: reason)
    }
    func validateDNS(mode: OnlineDNSMode = .strict, approvedOrigin: Bool = false, resolver: (@Sendable (String) async throws -> [String])? = nil) async throws {
        guard let host = root.host, Self.publicHost(host) else { throw Self.diagnostic(root, stage: "DNS", reason: "域名格式不被允许") }
        if let resolver {
            let addresses = try await resolver(host)
            try Task.checkCancellation()
            try Self.validateAddresses(addresses, root: root, mode: mode, approvedOrigin: approvedOrigin)
            return
        }
        try await Task.detached(priority: .utility) { [root] in
            #if canImport(Darwin)
            var result: UnsafeMutablePointer<addrinfo>?
            var hints = addrinfo(); hints.ai_family = AF_UNSPEC
            hints.ai_socktype = SOCK_STREAM; hints.ai_protocol = IPPROTO_TCP
            let status = getaddrinfo(host, nil, &hints, &result)
            guard status == 0, let first = result else {
                throw Self.diagnostic(root, stage: "DNS", reason: "解析无结果（getaddrinfo=\(status)）")
            }
            defer { freeaddrinfo(first) }
            var cursor: UnsafeMutablePointer<addrinfo>? = first; var count = 0; var addresses: [String] = []
            while let item = cursor {
                guard count < 32 else { throw OnlineFailure.tooLarge }
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let value = item.pointee
                guard value.ai_family == AF_INET || value.ai_family == AF_INET6,
                      let address = value.ai_addr else { throw Self.diagnostic(root, stage: "DNS", reason: "解析返回未知地址族") }
                let numericStatus = getnameinfo(address, value.ai_addrlen, &buffer, socklen_t(NI_MAXHOST), nil, 0, NI_NUMERICHOST)
                guard numericStatus == 0 else { throw Self.diagnostic(root, stage: "DNS", reason: "数值地址转换失败（getnameinfo=\(numericStatus)）") }
                addresses.append(String(cString: buffer))
                count += 1; cursor = value.ai_next
            }
            try Self.validateAddresses(addresses, root: root, mode: mode, approvedOrigin: approvedOrigin)
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
    var ladder: [HLSVariant] = []
    init(variants: [URL], keys: [URL], ladder: [HLSVariant] = []) {
        self.variants = variants
        self.keys = keys
        self.ladder = ladder
    }
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
        var variants: [URL] = []; var ladder: [HLSVariant] = []; var keys: [URL] = []; var expectsVariant = false
        var pendingVariant: HLSVariant?; var segments = 0; var streamOrder = 0
        func scoped(_ raw: String) throws -> URL {
            if raw.lowercased().hasPrefix("skd:") { throw OnlineFailure.drm }
            guard !raw.contains("{$"), !raw.contains("\\"), !raw.contains(where: { $0.isWhitespace }),
                  let child = URL(string: raw, relativeTo: url)?.absoluteURL.standardized,
                  OnlinePolicy.bound(child, to: root) else { throw OnlineFailure.unsafe }
            return child
        }
        func appendVariant(_ child: URL, capture: Bool = false) throws {
            guard !variants.contains(child) else { if capture { pendingVariant = nil }; return }
            guard variants.count < 6 else { throw OnlineFailure.tooLarge }
            variants.append(child)
            if capture, var meta = pendingVariant {
                meta.url = child; meta.order = streamOrder; streamOrder += 1; ladder.append(meta)
            }
            if capture { pendingVariant = nil }
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
                guard !expectsVariant else { throw OnlineFailure.parse }
                let a = try attributes(String(line.split(separator: ":", maxSplits: 1)[1]))
                pendingVariant = try HLSVariant(attributes: a, order: streamOrder)
                expectsVariant = true; continue
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
            if expectsVariant { try appendVariant(child, capture: true); expectsVariant = false } else { segments += 1 }
        }
        guard !expectsVariant, pendingVariant == nil, !variants.isEmpty || (segments > 0 && t.contains("#EXTINF:")),
              !(segments > 0 && lines.contains(where: { $0.hasPrefix("#EXT-X-STREAM-INF:") })) else { throw OnlineFailure.parse }
        return OnlineManifest(variants: variants, keys: keys, ladder: ladder)
    }
}

/// Neutral HLS variant metadata. Selection never fetches another origin and never
/// treats an unbounded peak bitrate as “highest quality”.
struct HLSVariant: Equatable, Sendable {
    var url: URL?
    var width: Int?
    var height: Int?
    var bandwidth: Int?
    var averageBandwidth: Int?
    var codecs: String?
    var order: Int
    init(attributes: [String:String], order: Int = 0) throws {
        if let raw = attributes["RESOLUTION"] {
            let parts = raw.split(separator: "x", omittingEmptySubsequences: false)
            guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]), w > 0, h > 0, w < 100_000, h < 100_000 else { throw OnlineFailure.parse }
            width = w; height = h
        }
        func integer(_ name: String) throws -> Int? {
            guard let raw = attributes[name] else { return nil }
            guard let value = Int(raw), value >= 0, value < 1_000_000_000 else { throw OnlineFailure.parse }
            return value
        }
        bandwidth = try integer("BANDWIDTH")
        averageBandwidth = try integer("AVERAGE-BANDWIDTH")
        if let codecs = attributes["CODECS"] {
            guard !codecs.isEmpty, codecs.count <= 256, !codecs.contains(where: \.isNewline) else { throw OnlineFailure.parse }
            self.codecs = codecs
        }
        self.order = order
    }
    var pixels: Int? { guard let width, let height else { return nil }; return width * height }
    /// Device-decodable check for codecs named in the already-parsed master.
    /// Unknown/absent codecs are not rejected; only a known-unsupported video codec is skipped.
    static func videoCodecSupported(_ codecs: String?) -> Bool {
        guard let codecs, !codecs.isEmpty else { return true }
        let parts = codecs.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let video = parts.filter { $0.hasPrefix("avc1") || $0.hasPrefix("hvc1") || $0.hasPrefix("hev1") || $0.hasPrefix("dvh1") || $0.hasPrefix("dvhe") || $0.hasPrefix("av01") || $0.hasPrefix("vp09") || $0.hasPrefix("vp9") || $0.hasPrefix("mp4v") }
        guard !video.isEmpty else { return true }
        return video.contains { codec in
            let type: String
            if codec.hasPrefix("avc1") || codec.hasPrefix("mp4v") { type = "avc1" }
            else if codec.hasPrefix("hvc1") || codec.hasPrefix("hev1") { type = "hvc1" }
            else if codec.hasPrefix("dvh1") || codec.hasPrefix("dvhe") { type = "dvh1" }
            else { type = String(codec.prefix(4)) }
            return Self.platformSupports(type)
        }
    }
    private static func platformSupports(_ type: String) -> Bool {
        switch type {
        case "avc1", "mp4v": return true
        case "hvc1", "dvh1":
            #if os(iOS) || os(tvOS) || os(visionOS) || targetEnvironment(macCatalyst)
            return true
            #elseif os(macOS)
            return true
            #else
            return false
            #endif
        case "av01":
            if #available(iOS 17, macOS 14, tvOS 17, *) { return false } // Do not assume AV1 hardware.
            return false
        default: return false // vp09 and other named video codecs are not native AVPlayer codecs here.
        }
    }
    var supported: Bool { Self.videoCodecSupported(codecs) }
}

struct OnlineQualityChoice: Equatable, Sendable {
    enum Mode: String, Equatable, Sendable { case automatic, highest, specific, unavailable }
    var mode: Mode
    var variant: HLSVariant?
    /// Session hint only. Nil means do not constrain the player (existing automatic path).
    var peakBitRate: Double?
    var maximumResolution: CGSize?
    var label: String
    static let automatic = OnlineQualityChoice(mode: .automatic, variant: nil, peakBitRate: nil, maximumResolution: nil, label: "自动")
}

enum OnlineQualitySelector {
    /// Deterministic: largest legal resolution, then BANDWIDTH, then stable order.
    /// Variants without resolution compete by bandwidth only against each other.
    /// Unsupported codecs are skipped. Empty/all-unsupported falls back to automatic.
    static func select(_ ladder: [HLSVariant], preferHighest: Bool, manual: HLSVariant? = nil) -> OnlineQualityChoice {
        let indexed = ladder
        if let manual {
            guard manual.supported else { return .automatic }
            return choice(.specific, manual)
        }
        guard preferHighest else { return .automatic }
        guard !indexed.isEmpty else { return .automatic }
        let playable = indexed.filter(\.supported)
        guard !playable.isEmpty else {
            return OnlineQualityChoice(mode: .unavailable, variant: nil, peakBitRate: nil, maximumResolution: nil, label: "自动·无可用最高档")
        }
        let ranked = playable.sorted { a, b in
            switch (a.pixels, b.pixels) {
            case let (ap?, bp?) where ap != bp: return ap > bp
            case (.some, .none): return true
            case (.none, .some): return false
            default:
                let ab = a.bandwidth ?? -1, bb = b.bandwidth ?? -1
                if ab != bb { return ab > bb }
                return a.order < b.order
            }
        }
        guard let best = ranked.first else { return .automatic }
        if best.pixels == nil && best.bandwidth == nil { return .automatic }
        return choice(.highest, best)
    }
    private static func choice(_ mode: OnlineQualityChoice.Mode, _ variant: HLSVariant) -> OnlineQualityChoice {
        let peak: Double? = variant.bandwidth.map { Double($0) }
        let size: CGSize? = {
            guard let w = variant.width, let h = variant.height else { return nil }
            return CGSize(width: w, height: h)
        }()
        return OnlineQualityChoice(mode: mode, variant: variant, peakBitRate: peak, maximumResolution: size, label: label(mode, variant))
    }
    static func label(_ mode: OnlineQualityChoice.Mode, _ variant: HLSVariant) -> String {
        let grade: String
        if let h = variant.height, let w = variant.width {
            grade = PlaybackVideoMetrics(width: Double(w), height: Double(h), evidence: .track)?.grade ?? "\(min(w,h))p"
        } else if let bandwidth = variant.bandwidth {
            grade = "带宽 \(bandwidth)"
        } else { grade = "原清单" }
        switch mode {
        case .highest: return "最高·" + grade
        case .specific: return grade
        case .automatic: return "自动"
        case .unavailable: return "自动·无可用最高档"
        }
    }
}

/// On-device, non-sensitive preference. Default is highest for online playback only.
struct OnlineQualityPreference: Equatable, Sendable {
    static let storageKey = "online.preferHighestQuality.v1"
    var preferHighest: Bool
    init(preferHighest: Bool = true) { self.preferHighest = preferHighest }
    init(preferences: UserDefaults) {
        if preferences.object(forKey: Self.storageKey) == nil { preferHighest = true }
        else { preferHighest = preferences.bool(forKey: Self.storageKey) }
    }
    func save(_ preferences: UserDefaults) { preferences.set(preferHighest, forKey: Self.storageKey) }
    var status: String { preferHighest ? "优先最高画质：已开启" : "优先最高画质：关闭 · 自动" }
}
final class OnlineTransport: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let dnsMode: OnlineDNSMode
    private let loader: (@Sendable (URLRequest) async throws -> Data)?
    private let resolver: (@Sendable (String) async throws -> [String])?
    init(dnsMode: OnlineDNSMode = .strict, resolver: (@Sendable (String) async throws -> [String])? = nil, loader: (@Sendable (URLRequest) async throws -> Data)? = nil) {
        self.dnsMode = dnsMode; self.resolver = resolver; self.loader = loader; super.init()
    }
    func withDNSMode(_ mode: OnlineDNSMode) -> OnlineTransport {
        OnlineTransport(dnsMode: mode, resolver: resolver, loader: loader)
    }
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
        let stage = scope != nil ? (url.path.hasSuffix(".m3u8") ? "清单" : "密钥") : (url.path.contains("/search/") || url.path == "/en/search" || url.path.hasPrefix("/video/") ? "查询" : "详情/嵌入/API")
        do { return try await fetchChecked(url, cap:cap, headers:headers, body:body, scope:scope) }
        catch {
            // Neutral loader retains historical error contracts; real requests gain
            // only bounded stage/host/reason, never URL path, query or credentials.
            if loader != nil { throw error }
            let failure = OnlineFailure.classify(error)
            if case .safe(let value) = failure {
                let context: PlaybackDiagnostic.Stage = scope != nil ? .manifest : (stage == "查询" ? .discovery : .document)
                throw OnlineFailure.safe(PlaybackDiagnostic(stage: context, category: value.category,
                    httpCode: value.httpCode, systemCode: value.systemCode,
                    host: PlaybackDiagnostic.resourceHost(url), dnsContext: value.dnsContext))
            }
            if case .diagnostic(let substage, _, let reason) = failure {
                throw OnlineMediaScope.diagnostic(url, stage: stage + "/" + substage, reason: reason)
            }
            throw OnlineMediaScope.diagnostic(url, stage: stage, reason: failure.localizedDescription)
        }
    }
    private func fetchChecked(_ url: URL, cap: Int, headers: [String:String], body: Data?, scope: OnlineMediaScope?) async throws -> Data {
        try Task.checkCancellation()
        if let scope {
            guard scope.contains(url) else { throw OnlineFailure.unsafe }
            if loader == nil || resolver != nil { try await scope.validateDNS(mode: dnsMode, approvedOrigin: true, resolver: resolver) }
        } else {
            guard OnlineSource.allCases.contains(where: { OnlinePolicy.metadata(url, source: $0) }) || OnlinePolicy.embed(url) || OnlinePolicy.media(url) else {
                if loader != nil { throw OnlineFailure.unsafe }
                throw OnlineMediaScope.diagnostic(url, stage: "URL", reason: OnlinePolicy.addressRejection(url))
            }
        }
        if (loader == nil || resolver != nil) && scope == nil { try await OnlineMediaScope(root:url).validateDNS(mode: dnsMode, approvedOrigin: true, resolver: resolver) }
        var request = URLRequest(url: url); request.timeoutInterval = 12
        guard body == nil else { throw OnlineFailure.unsafe }
        request.setValue(OnlinePolicy.ua, forHTTPHeaderField: "User-Agent")
        for (key,value) in headers where ["User-Agent","Referer","Origin","Accept"].contains(key) {
            if key == "Origin" && !["https://jable.tv", "https://missav.ws"].contains(value) { throw OnlineFailure.unsafe }
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
        if [401,403,429,451].contains(r.statusCode) || (300..<400).contains(r.statusCode) {
            throw OnlineFailure.httpResponse(r.statusCode, at: url)
        }
        if r.statusCode == 404 { throw OnlineFailure.noMatch }
        guard r.statusCode == 200 else { throw OnlineFailure.httpResponse(r.statusCode, at: url) }
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
    static func issuedPlaylist(_ raw: String, relativeTo page: URL, source: OnlineSource) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2048,
              !trimmed.contains(where: { $0.isWhitespace || $0.asciiValue.map({ $0 < 32 || $0 == 127 }) == true }),
              let parsed = URL(string: trimmed, relativeTo: page)?.absoluteURL.standardized,
              OnlinePolicy.media(parsed, source: source) || OnlinePolicy.discoveredMedia(parsed, source: source) else { return nil }
        return parsed
    }
    func validatedPlan(media: URL, referrer: URL, line: OnlineLine, number: String, pageIssued: Bool = false) async throws -> OnlinePlaybackPlan {
        guard OnlinePolicy.media(media, source: line.source) || (pageIssued && OnlinePolicy.discoveredMedia(media, source: line.source)) else { throw OnlineFailure.unsafe }
        let headers = OnlinePolicy.headers(referrer: referrer)
        let scope = OnlineMediaScope(root: media)
        var pending: [(URL,Int)] = [(media,0)]; var seen = Set<URL>(); var keys = Set<URL>(); var hasLeaf = false
        var rootLadder: [HLSVariant] = []
        // Validate every adaptive/rendition playlist, bounded across the whole graph.
        while !pending.isEmpty {
            let (url,depth) = pending.removeFirst()
            guard !seen.contains(url) else { continue }
            guard seen.count < 12, depth <= 3 else { throw OnlineFailure.tooLarge }
            seen.insert(url)
            let bytes = try await transport.fetch(url, cap: 512*1024, headers: headers, scope: scope)
            let manifest: OnlineManifest
            do { manifest = try OnlineManifest.parse(bytes, at: url, root: media) }
            catch { throw OnlineMediaScope.diagnostic(url, stage: "清单解析", reason: OnlineFailure.classify(error).localizedDescription) }
            for key in manifest.keys { keys.insert(key) }
            guard keys.count <= 16 else { throw OnlineFailure.tooLarge }
            if manifest.variants.isEmpty { hasLeaf = true }
            if depth == 0, !manifest.ladder.isEmpty { rootLadder = manifest.ladder }
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
        return OnlinePlaybackPlan(url: media, source: line.source, number: number, headers: headers, ladder: rootLadder)
    }
}
