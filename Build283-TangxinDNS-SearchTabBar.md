# Build 283: 糖心 under Loon/Surge/Clash fake-ip, and search hides the floating tab bar

## 1. 糖心 fails: "查询/DNS：安全策略拒绝 · public=0 synthetic=1 private=1"

### Root cause

`OnlineMediaScope.validateAddresses` runs before every online request (糖心 pages, covers, HLS playlists and keys, and the other online playback sources). It required **every** DNS answer to be public. The only exception was 198.18.0.0/15, and only when the user had turned on the 兼容 switch.

Loon (the user's proxy) runs in fake-ip mode by default:

- `tangxinvlog.app` and `t.5gcdn.xyz` resolve to 198.18.x.x, which counts as `synthetic=1`.
- A second answer comes back that looks private: a virtual-interface or LAN-style address (e.g. 172.19.0.x / 10.x), or an IPv6 ULA fake-ip (`fd…`). Because of it the check reported `private=1`.
- So strict mode stopped the request. The 兼容 switch would not have helped either, because the private-looking answer is always refused.

After the user added Loon `real-ip = tangxinvlog.app`, the pages loaded but covers and playback still failed. They are served from **`t.5gcdn.xyz`**, which still got fake-ip answers. The cover view swallowed the error (`catch { }`), so covers stayed blank without any message.

### Fix (`AVDB/Services/OnlineDNSPolicy.swift`)

- **Classification** of each DNS answer:
  - public
  - fake-ip 198.18/15, including `::ffff:` and NAT64-wrapped forms
  - NAT64: `64:ff9b::/96` decodes to the embedded IPv4; `64:ff9b:1::/48` is local-use
  - proxy ULA `fc00::/7`
  - benchmarking `2001:2::/48`
  - LAN (RFC1918), CGNAT `100.64/10`
  - loopback, link-local (including 169.254.169.254), unspecified, multicast, reserved (documentation, 6to4 and similar)
- **Decision rules:**
  - **Always blocked**, for every host and proxy state: loopback, link-local, unspecified, multicast, reserved.
  - **Pinned source hosts** (糖心: `tangxinvlog.app` and `*.tangxinvlog.app`, `t.5gcdn.xyz` and `*.5gcdn.xyz`; plus fs1.app, missav.fans, 123av.com, memojav.org, video10.memojav.net, javday.app, `*.javday.homes`, sadie-shop.site):
    - fake-ip, NAT64, proxy ULA and 2001:2:: answers are allowed.
    - A LAN-looking answer is allowed only with proxy evidence: a fake-ip answer in the same set, a detected system proxy/VPN, or the 兼容 switch.
    - This covers the reported `synthetic=1 private=1` case.
  - **Page-issued origins** (Jable / MissAV surrit / 123AV edges):
    - Never allowed to resolve to LAN or CGNAT.
    - Synthetic answers are allowed only with proxy evidence.
- **Proxy/VPN detection** is read-only and never changes any setting. It checks `CFNetworkCopySystemProxySettings` (`__SCOPED__` utun/ipsec/ppp keys, HTTP/SOCKS/PAC enabled) and looks for an IPv4-addressed utun/ipsec/ppp interface via `getifaddrs`.
- **Why this is safe:** every request is still HTTPS on 443 with full certificate validation and no redirects. A pinned name that resolves to a LAN device cannot pass TLS for that name.
- **Diagnostics:** the address summary now ends with `local=N tunnel=0|1`. The error hints name Loon/Surge/Clash Fake-IP and say what to check.
- **糖心 CDN:**
  - `TangxinPolicy.image` / `stream` accept the `5gcdn.xyz` CDN apex (edge rotation).
  - Covers show a visible failure tile (and retry once) instead of staying blank.
- **Other sources:** the same `OnlineTransport` / `OnlineMediaScope` path is used by every online playback source, so it is fixed in one place. DMM/JavDB cover loading never did a DNS pre-flight, so it was not affected.

### Cover / media hosts used by 糖心 (observed 2026-10-29)

- Pages: `tangxinvlog.app`
- Covers: `https://t.5gcdn.xyz/videos/<id>/cover.jpg`
- HLS: `https://t.5gcdn.xyz/videos/…/*.m3u8`

Loon workaround for builds before 283:

```
real-ip = tangxinvlog.app, *.tangxinvlog.app, t.5gcdn.xyz, *.5gcdn.xyz
```

From 283 on, no real-ip entry is needed.

## 2. Search shows the tab bar above the keyboard

### Root cause

The custom six-tab bar (since Build 263; this is not a 280/281 regression) lives in the root container's bottom `safeAreaInset`. That inset follows the keyboard safe area, so when the search field took focus the bar rose above the keyboard and covered the 近期熱搜 chips. `SearchView`'s `.toolbar(.automatic, for: .tabBar)` only controls the system tab bar, not the custom one.

### Fix (`AVDB/Views/TabBarChrome.swift`)

- `FloatingTabContainer` now owns the bar. It is hidden while a search screen is active in the selected tab (`HidesFloatingTabBar` on `SearchView`, counted per tab) or whenever a software keyboard is docked. That second rule applies to every screen with a text field; hardware keyboards' short accessory bar does not count.
- The bar animates out and back in (move + fade, 0.22 s) and returns on cancel or keyboard dismiss.

## Tests

- **`scripts/test-tangxin-dns283.py`** runs the classification and decision regression, including:
  - the reported answer shape `198.18.x + 172.19.0.1` → allowed
  - Loon IPv6 ULA fake-ip
  - NAT64 / local NAT64
  - 2001:2::
  - LAN only with proxy evidence
  - loopback, link-local, metadata and reserved addresses always blocked
  - page-issued origins never LAN
  - fixed-host suffix spoofing
  - source wiring and version checks
- **`scripts/test-tab-ui283.py`** (CI job `tab-ui-screenshots`) is an XCUITest on the production container, bar and modifiers. It checks:
  - the bar is visible on home
  - it is hidden in search with the keyboard up
  - it comes back after 取消
  - it is hidden when another screen's text field has the keyboard up
