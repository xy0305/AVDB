# Build 270 — Jable online host: explicit fs1.app (403 root cause)

## Root cause

Online Jable (Build 254) issued search/detail on **`jable.tv`**. Live anonymous probes from this environment (URLSession-equivalent curl) consistently receive Cloudflare **HTTP 403** with title `Just a moment...` / managed challenge HTML for `/`, `/search/<code>/`, and `/videos/<slug>/`. Soft UA / Referer retries cannot complete the JS challenge. Headless probes of `jp.jable.tv` are likewise challenged.

By contrast, **`fs1.app`** (documented Jable.TV mirror used by FetchJAV / jable-desktop) returns HTTP 200 with real listing cards and detail pages under the same `/search/` + `/videos/` protocol. Verified for `EBWH-372`: async search lists `/videos/ebwh-372/`, detail serves canonical `https://fs1.app/videos/ebwh-372/` plus a single static `var hlsUrl = 'https://…mushroomtrack.com/…m3u8'` without a challenge page. `PRWF-017` search also returns `/videos/prwf-017/`.

`jable.vip` is a different CMS (vodtype/vodsearch) and is **not** used. No silent rewrite of blocked `jable.tv` response links.

## What changed

| Item | Change |
|---|---|
| `JableAdapter.search` | `https://fs1.app/search/<code>/` + existing async query items (declared host) |
| Search Referer / site | `https://fs1.app/` |
| `OnlinePolicy.metadata(.jable)` | Allow only `fs1.app` `/search/` and `/videos/`; reject `jable.tv` / other mirrors |
| Origin allowlist | `https://fs1.app` for Jable online requests |
| `jableMedia` relative base | `https://fs1.app/` (playlists remain absolute page-issued HTTPS) |
| Neutral fixtures | Search/detail on fs1; absolute `jable.tv` cards treated as wrong mirrors |
| Static guards | `scripts/test-jable270.py` |

No Cloudflare cookie import, no Safari shared jar, no remote JS execution, no captcha solve, no arbitrary CDN allowlisting. Media remains the exact page-issued `hlsUrl` HTTPS origin with existing DNS + all-rendition HLS validation.

## Limits

- Device/IP regions where `fs1.app` itself is challenged will still surface a clear blocked / HTTP error (no silent fallback to `jable.tv` or another apex).
- `jable.tv` is no longer the online adapter host; users who specifically need that apex must use a browser — native online play will not claim tv access.
- First-frame playback is not claimed by metadata/HLS validation alone.
