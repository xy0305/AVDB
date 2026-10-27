# Build 269 — MissAV online host: explicit missav.fans (403 root cause)

## Root cause

Online MissAV (Build 254) issued search/detail on **`missav.ws`**. Live anonymous probes from this environment (URLSession-equivalent curl and headless Chrome) consistently receive Cloudflare **HTTP 403** with title `Just a moment...` / managed challenge HTML for `/`, `/en/search/<code>`, and ranking paths. Soft UA / Referer / Accept-Language retries (Build 267) and ephemeral cookies cannot complete the JS challenge. Headless WebKit/Chrome also stop on the interstitial here, so a DMM-style WKWebView HTML hydrator would not reliably clear `missav.ws` either.

By contrast, **`missav.fans`** (ranking default since Build 175) and **`missav.media`** return HTTP 200 with real thumbnail cards. Verified for `EBWH-372`: search lists `/en/ebwh-372` (+ edition) and detail serves canonical + packed `surrit.*` source table without a challenge page.

## What changed

| Item | Change |
|---|---|
| `MissAVAdapter.search` | `https://missav.fans/en/search/<code>` (declared host, not a silent rewrite of ws responses) |
| Search Referer | `https://missav.fans/` |
| `OnlinePolicy.metadata(.missav)` | Allow only `missav.fans` `/en/…` (and legacy `/dm339/en/…` path shape); reject `missav.ws` / other mirrors |
| Origin allowlist | `https://missav.fans` for MissAV online requests |
| Neutral fixtures | Search fixture on fans; absolute `missav.ws` / `missav.media` cards treated as wrong mirrors |
| Ranking / MissAVSource | Unchanged — still user-configurable domain, default fans |

No Cloudflare cookie import, no Safari shared jar, no remote JS execution, no captcha solve, no arbitrary CDN allowlisting. Media remains page-issued `surrit.*` HLS with existing bounds.

## Limits

- Device/IP regions where `missav.fans` itself is challenged will still surface a clear blocked / HTTP error (no silent fallback to another apex).
- `missav.ws` is no longer the online adapter host; users who specifically need that apex must use a browser — native online play will not claim ws access.
- First-frame playback is not claimed by metadata/HLS validation alone.

