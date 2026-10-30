import Foundation
// Build 283: proxy-aware DNS pre-flight (Loon/Surge/Clash fake-ip, NAT64, proxy ULA).
func check(_ c: @autoclosure () -> Bool, _ m: String, line: Int = #line) { if !c() { print("FAIL line \(line): \(m)"); exit(1) } }
typealias P = OnlineDNSPolicy
func v(_ a: [String], _ host: String = "tangxinvlog.app", mode: OnlineDNSMode = .strict, tunnel: Bool = false) -> P.Verdict {
    P.evaluate(a, host: host, mode: mode, tunnelActive: tunnel)
}
// classification
let expect: [(String, DNSAddressClass)] = [
    ("104.21.32.1", .publicAddress), ("2606:4700::6810:1", .publicAddress), ("64:ff9b::6815:2001", .publicAddress),
    ("198.18.0.12", .fakeIP), ("198.19.255.254", .fakeIP), ("::ffff:198.18.3.4", .fakeIP), ("64:ff9b::c612:0001", .fakeIP),
    ("64:ff9b:1::a", .nat64Local), ("fdfe:dcba:9876::12", .proxyULA), ("fd00::1", .proxyULA), ("2001:2::5", .benchmarkV6),
    ("10.0.0.1", .lan), ("172.19.0.1", .lan), ("192.168.1.1", .lan), ("::ffff:10.0.0.1", .lan), ("64:ff9b::a00:1", .lan),
    ("100.100.100.100", .cgnat), ("127.0.0.1", .loopback), ("::1", .loopback), ("::ffff:127.0.0.1", .loopback),
    ("169.254.169.254", .linkLocal), ("fe80::1%en0", .linkLocal), ("0.0.0.0", .unspecified), ("::", .unspecified),
    ("224.0.0.1", .multicast), ("ff02::1", .multicast), ("192.0.2.1", .reserved), ("2001:db8::1", .reserved),
    ("2002:a00:1::", .reserved), ("garbage", .invalid), ("1.2.3", .invalid), ("01.2.3.4444", .invalid),
]
for (a, c) in expect { check(P.classify(a) == c, "\(a) → \(P.classify(a)) expected \(c)") }

// Reported device case: "public=0 synthetic=1 private=1 empty=0" on tangxinvlog.app under Loon.
for second in ["172.19.0.1", "10.10.0.2", "198.18.0.1", "100.64.0.1"] {
    let answer = ["198.18.0.27", second]
    check(v(answer) == .allow, "Loon fake-ip + virtual \(second) on fixed host (strict, no tunnel detected)")
    check(v(answer, tunnel: true) == .allow, "with tunnel")
}
check(P.summary(["198.18.0.27", "172.19.0.1"], tunnelActive: true) == "public=0 synthetic=1 private=1 empty=0 local=0 tunnel=1", "summary keeps legacy prefix")
// Loon/Clash IPv6 fake-ip + IPv4 fake-ip, NAT64/DNS64, benchmarking v6
for answer in [["198.18.0.27", "fdfe:dcba:9876::1b"], ["fd00::27"], ["2001:2::1b"], ["64:ff9b::6815:2001"], ["64:ff9b:1::1b"], ["::ffff:198.18.0.27"]] {
    check(v(answer) == .allow, "fixed host synthetic \(answer)")
    check(v(answer, "t.5gcdn.xyz") == .allow, "tangxin CDN \(answer)")
    check(v(answer, "edge.javday.homes") == .allow, "javday apex \(answer)")
}
// 糖心 CDN (covers + HLS) on the reported answer shape, plus edge subdomains
for host in ["t.5gcdn.xyz", "v2.5gcdn.xyz", "img.tangxinvlog.app"] {
    check(v(["198.18.0.9", "172.19.0.1"], host) == .allow && v(["198.18.0.9", "fdfe:dcba:9876::9"], host) == .allow, "\(host) fake-ip answers")
    check(v(["127.0.0.1"], host, tunnel: true) == .privateTarget, "\(host) loopback blocked")
}
check(!P.fixedSource("5gcdn.xyz.evil.com") && !P.fixedSource("x5gcdn.xyz"), "apex suffix is label-bound")
// fixed host, LAN-only answer: only with proxy evidence
check(v(["192.168.1.20"]) == .privateTarget, "LAN without proxy blocked")
check(v(["192.168.1.20"], tunnel: true) == .allow && v(["10.0.0.5"], mode: .systemProxy) == .allow, "LAN with tunnel/toggle allowed for pinned host")
// hard floor, any host, any proxy
for bad in ["127.0.0.1", "::1", "169.254.169.254", "fe80::1", "0.0.0.0", "224.0.0.1", "::ffff:127.0.0.1", "192.0.2.1", "2001:db8::1"] {
    check(v([bad], mode: .systemProxy, tunnel: true) == .privateTarget, "\(bad) blocked even with proxy")
    check(v(["198.18.0.1", bad], tunnel: true) == .privateTarget, "\(bad) mixed with fake-ip still blocked")
}
// page-issued origin (not fixed): LAN never, synthetic only with proxy evidence
let issued = "cdn.issued-origin.com"
check(!P.fixedSource(issued) && P.fixedSource("TangXinVlog.app") && !P.fixedSource("evil-tangxinvlog.app") && !P.fixedSource("javday.homes.evil.com"), "fixed host matching")
check(v(["10.0.0.1"], issued, tunnel: true) == .privateTarget && v(["198.18.0.1", "192.168.0.10"], issued, tunnel: true) == .privateTarget, "issued origin LAN blocked")
check(v(["fd00::1"], issued) == .synthetic && v(["fd00::1"], issued, tunnel: true) == .allow, "issued ULA needs proxy evidence")
check(v(["198.18.0.1"], issued) == .allow, "issued fake-ip is self-evident proxy")
check(v(["64:ff9b::a00:1"], issued, tunnel: true) == .privateTarget, "NAT64 of private never")
check(v(["104.21.32.1", "2606:4700::6810:1"], issued) == .allow, "public allowed")
check(v([]) == .empty && v(Array(repeating: "1.1.1.1", count: 33)) == .tooMany, "empty / limit")
check(P.hint(.privateTarget).contains("Loon/Surge/Clash") && P.hint(.synthetic).contains("Loon/Surge/Clash Fake-IP"), "user hint names proxies")
_ = P.interfaceTunnelUp()
print("PASS dns283: fake-ip 198.18/15, NAT64 (64:ff9b::/96, 64:ff9b:1::/48), proxy ULA, 2001:2::/48, Loon synthetic=1 private=1 allowed for pinned hosts; loopback/link-local/metadata/reserved always blocked; issued origins never LAN")
