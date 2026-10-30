import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Build 283: DNS pre-flight classification that survives iOS proxy apps (Loon / Surge /
/// Clash / Shadowrocket / Stash) in fake-ip mode and NAT64/DNS64 networks, while still
/// refusing genuine loopback / link-local / multicast / LAN targets for page-issued hosts.
enum DNSAddressClass: String, Sendable, CaseIterable {
    case publicAddress          // global unicast (incl. NAT64 of a public IPv4)
    case fakeIP                 // 198.18.0.0/15 (RFC 2544) – Loon/Surge/Clash default fake-ip pool
    case nat64Local             // 64:ff9b:1::/48 local-use NAT64 (RFC 8215)
    case proxyULA               // fc00::/7 – proxy IPv6 fake-ip pools (e.g. fdfe:dcba:9876::/64)
    case benchmarkV6            // 2001:2::/48 (RFC 5180) – some proxies' IPv6 fake-ip pool
    case lan                    // 10/8, 172.16/12, 192.168/16 (also proxy virtual-interface answers)
    case cgnat                  // 100.64/10 (Tailscale / carrier NAT / some VPN DNS)
    case loopback, linkLocal, unspecified, multicast, reserved, invalid

    /// Proxy/VPN-synthesized answer: the connection is carried by the tunnel, never
    /// delivered to that literal address on the wire.
    var synthetic: Bool { [.fakeIP, .nat64Local, .proxyULA, .benchmarkV6].contains(self) }
    /// Private-looking but possibly a proxy's virtual DNS answer (Loon utun 10.x / 172.19.x).
    var privateLike: Bool { self == .lan || self == .cgnat }
    /// Never acceptable for any host, any proxy state (SSRF hard floor).
    var forbidden: Bool { [.loopback, .linkLocal, .unspecified, .multicast, .invalid].contains(self) }
}

enum OnlineDNSPolicy {
    /// Fixed, compiled-in source hosts (not page-issued). Their DNS answers under a
    /// proxy cannot redirect the app to an attacker-chosen host; the name itself is pinned.
    static let fixedHosts: Set<String> = [
        "tangxinvlog.app", "t.5gcdn.xyz",                  // 糖心 pages + CDN
        "fs1.app", "missav.fans", "123av.com", "memojav.org", "video10.memojav.net",
        "javday.app", "sadie-shop.site",
    ]
    static let fixedApexes: [String] = ["javday.homes", "5gcdn.xyz", "tangxinvlog.app"]   // 糖心 CDN edges (covers + HLS)

    static func fixedSource(_ host: String?) -> Bool {
        guard let h = host?.lowercased(), !h.isEmpty else { return false }
        return fixedHosts.contains(h) || fixedApexes.contains { h == $0 || h.hasSuffix("." + $0) }
    }

    // MARK: classification

    static func bytes(_ address: String) -> [UInt8]? {
        let a = address.split(separator: "%", maxSplits: 1).first.map(String.init) ?? address  // drop zone id
        if a.contains(":") {
            var v = in6_addr()
            guard inet_pton(AF_INET6, a, &v) == 1 else { return nil }
            return withUnsafeBytes(of: &v) { Array($0) }
        }
        let parts = a.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var out: [UInt8] = []
        for p in parts {
            guard !p.isEmpty, p.count <= 3, p.utf8.allSatisfy({ (48...57).contains($0) }), let n = Int(p), n <= 255 else { return nil }
            out.append(UInt8(n))
        }
        return out
    }

    static func classify(_ address: String) -> DNSAddressClass {
        guard let b = bytes(address) else { return .invalid }
        return b.count == 4 ? classifyV4(b) : classifyV6(b)
    }

    static func classifyV4(_ b: [UInt8]) -> DNSAddressClass {
        let (a, c, d) = (Int(b[0]), Int(b[1]), Int(b[2]))
        switch a {
        case 0: return .unspecified
        case 127: return .loopback
        case 10: return .lan
        case 224...239: return .multicast
        case 240...255: return .reserved
        default: break
        }
        if a == 169 && c == 254 { return .linkLocal }                 // incl. 169.254.169.254 metadata
        if a == 172 && (16...31).contains(c) { return .lan }
        if a == 192 && c == 168 { return .lan }
        if a == 100 && (64...127).contains(c) { return .cgnat }
        if a == 198 && (c == 18 || c == 19) { return .fakeIP }
        if a == 192 && c == 0 && (d == 0 || d == 2) { return .reserved } // IETF / TEST-NET-1
        if a == 192 && c == 88 && d == 99 { return .reserved }
        if a == 198 && c == 51 && d == 100 { return .reserved }
        if a == 203 && c == 0 && d == 113 { return .reserved }
        return .publicAddress
    }

    static func classifyV6(_ b: [UInt8]) -> DNSAddressClass {
        if b.allSatisfy({ $0 == 0 }) { return .unspecified }
        if b.prefix(15).allSatisfy({ $0 == 0 }) && b[15] == 1 { return .loopback }
        if b.prefix(10).allSatisfy({ $0 == 0 }) && b[10] == 0xff && b[11] == 0xff { return classifyV4(Array(b.suffix(4))) } // ::ffff:v4
        if b.prefix(12).allSatisfy({ $0 == 0 }) { return .reserved }   // deprecated IPv4-compatible
        if Array(b.prefix(12)) == [0,0x64,0xff,0x9b,0,0,0,0,0,0,0,0] {    // 64:ff9b::/96 NAT64
            let inner = classifyV4(Array(b.suffix(4)))
            return inner == .fakeIP ? .fakeIP : inner
        }
        if Array(b.prefix(6)) == [0,0x64,0xff,0x9b,0,1] { return .nat64Local } // 64:ff9b:1::/48
        if b[0] == 0xff { return .multicast }
        if b[0] == 0xfe && b[1] & 0xc0 == 0x80 { return .linkLocal }   // fe80::/10
        if b[0] & 0xfe == 0xfc { return .proxyULA }                     // fc00::/7
        if Array(b.prefix(6)) == [0x20,0x01,0,0x02,0,0] { return .benchmarkV6 } // 2001:2::/48
        guard b[0] & 0xe0 == 0x20 else { return .reserved }             // global unicast only
        if b[0] == 0x20 && b[1] == 0x02 { return .reserved }            // 6to4
        if b[0] == 0x20 && b[1] == 0x01 {
            if b[2] == 0x0d && b[3] == 0xb8 { return .reserved }        // documentation
            if b[2] == 0 && b[3] <= 0x2f { return .reserved }           // Teredo / ORCHID / special
        }
        return .publicAddress
    }

    // MARK: decision

    enum Verdict: Equatable, Sendable {
        case allow
        case empty
        case tooMany
        case synthetic   // proxy-synthesized answers for a page-issued host with no proxy evidence
        case privateTarget
    }

    /// `tunnelActive`: a system proxy / VPN (utun, ipsec, ppp) is configured right now.
    /// `mode == .systemProxy`: the user's explicit 兼容 toggle.
    static func evaluate(_ addresses: [String], host: String?, mode: OnlineDNSMode, tunnelActive: Bool) -> Verdict {
        guard !addresses.isEmpty else { return .empty }
        guard addresses.count <= 32 else { return .tooMany }
        let classes = addresses.map(classify)
        if classes.contains(where: \.forbidden) { return .privateTarget }
        if classes.allSatisfy({ $0 == .publicAddress }) { return .allow }
        if classes.contains(.reserved) { return .privateTarget }
        let proxyEvidence = tunnelActive || mode == .systemProxy || classes.contains(.fakeIP)
        if fixedSource(host) {
            // Pinned source name: fake-ip / NAT64 / proxy ULA are always fine; a LAN-looking
            // answer (Loon's virtual DNS / utun gateway, e.g. 172.19.0.x / 10.x) only with proxy evidence.
            if classes.contains(where: \.privateLike) && !proxyEvidence { return .privateTarget }
            return .allow
        }
        // Page-issued media origins (Jable / MissAV surrit / 123AV edges): never a LAN answer;
        // synthetic answers only with proxy evidence.
        if classes.contains(where: \.privateLike) { return .privateTarget }
        return proxyEvidence ? .allow : .synthetic
    }

    static func summary(_ addresses: [String], tunnelActive: Bool) -> String {
        let classes = addresses.map(classify)
        let pub = classes.filter { $0 == .publicAddress }.count
        let syn = classes.filter(\.synthetic).count
        let local = classes.filter(\.forbidden).count
        let priv = classes.count - pub - syn - local
        return "public=\(pub) synthetic=\(syn) private=\(priv) empty=\(addresses.isEmpty ? 1 : 0) local=\(local) tunnel=\(tunnelActive ? 1 : 0)"
    }

    // MARK: system proxy / VPN detection (read-only, never changes settings)

    /// Overridable for tests.
    static var tunnelProbe: @Sendable () -> Bool = { systemTunnelActive() }

    static func systemTunnelActive() -> Bool {
        #if canImport(Darwin)
        if let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] {
            if let scoped = settings["__SCOPED__"] as? [String: Any],
               scoped.keys.contains(where: { k in ["utun", "ipsec", "ppp", "tun", "tap"].contains { k.hasPrefix($0) } }) { return true }
            for key in ["HTTPEnable", "HTTPSEnable", "SOCKSEnable", "ProxyAutoConfigEnable"] where (settings[key] as? NSNumber)?.boolValue == true { return true }
        }
        #endif
        return interfaceTunnelUp()
    }

    static func interfaceTunnelUp() -> Bool {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return false }
        defer { freeifaddrs(first) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let item = cursor {
            let name = String(cString: item.pointee.ifa_name)
            let flags = Int32(item.pointee.ifa_flags)
            if ["utun", "ipsec", "ppp", "tun"].contains(where: { name.hasPrefix($0) }),
               flags & Int32(IFF_UP) != 0, let addr = item.pointee.ifa_addr, Int32(addr.pointee.sa_family) == AF_INET {
                return true   // iOS's own utun0-3 carry only IPv6 link-local; a NE tunnel carries IPv4
            }
            cursor = item.pointee.ifa_next
        }
        return false
    }

    /// User-facing hint for a remaining DNS refusal.
    static func hint(_ verdict: Verdict) -> String {
        switch verdict {
        case .synthetic: return "DNS 返回代理/Fake-IP 合成地址（Loon/Surge/Clash Fake-IP 或 NAT64），但未检测到系统代理/VPN；请确认代理已连接，或在 糖心 › 网络 开启“系统代理/Fake-IP兼容”"
        case .privateTarget: return "DNS 返回非公网地址（回环/链路本地/局域网/保留）；请求已停止。若使用 Loon/Surge/Clash Fake-IP，请确认代理已连接、该域名走代理规则（非 DIRECT 到局域网）后重试"
        default: return ""
        }
    }
}
