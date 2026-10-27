# Build 271 — Online 未匹配 for IPX-697 (Jable / MissAV / MemoJav)

## Live probes (anonymous, 2026-10-27)

| Source | Probe | Result |
|---|---|---|
| MissAV `missav.fans/en/search/IPX-697` | 200 | Cards: **only** `/en/ipx-697-uncensored-leak` (no primary card) |
| MissAV `missav.fans/en/ipx-697` | 200 | Primary detail exists; og:title carries `IPX-697` |
| MissAV `missav.fans/cn/search/IPX-697` | 200 | Both `/cn/ipx-697` and leak (policy still declares `/en/` only) |
| Jable `fs1.app/search/IPX-697/` (+ async block) | 200 | Card `/videos/ipx-697ntum/` title `IPX-697 …` |
| Jable `fs1.app/videos/ipx-697ntum/` | 200 | canonical + `var hlsUrl = 'https://…m3u8'` |
| Jable `fs1.app/videos/ipx-697/` | 404 | Exact slug without opaque suffix is absent |
| MemoJav `memojav.org/video/IPX-697` | **404** | Site search form posts to Google; no in-site hit API |
| MemoJav `memojav.org/video/IPX-698` | 200 | Neighbouring title present — IPX-697 absence is catalogue, not host |

## Root causes

1. **MissAV (adapter)** — Discover used `/en/search/` and `OnlineIdentity.version(..., allowVersions:false)`. EN search listed only the labelled `…-uncensored-leak` card, which is rejected when the labelled toggle is off → empty rows → 未匹配, even though `/en/ipx-697` is live.
2. **Jable (adapter)** — Live slugs append opaque letters after the serial (`ipx-697ntum`). `CatalogueIdentity.parts` / `OnlineIdentity.key` require a digit-only serial, so `version("ipx-697ntum")` was nil → search card dropped → 未匹配, despite heading/canonical identity.
3. **MemoJav (genuine)** — Exact `/video/IPX-697` is 404. No adapter bug; keep 未匹配. Do not invent a Google-site search or fake candidate.

## Fixes

| Item | Change |
|---|---|
| `OnlineIdentity.version` | Accept Jable-style opaque alphabetic suffix immediately after the **exact** serial (`DEMO-123NTUM` → 原始版本). Still reject `DEMO-1230`, `DEMO-123-LEAK` (hyphenated labels remain opt-in). |
| `MissAVAdapter.lines` | When search HTML has number evidence under `allowVersions:true` but no 原始版本 row, synthesize primary `https://missav.fans/en/<code>` (declared host; no mirror rewrite). |
| Neutral fixtures | Jable search/detail use `demo-123ntum`; MissAV search lists labelled-only so synthesis is exercised. |
| MemoJav | No behaviour change; documented. |

## Limits

- First-frame playback is not claimed by HTML/HLS validation.
- MissAV primary synthesis requires labelled (or other) search evidence for that number; empty search stays 未匹配.
- Opaque-suffix matching requires the full serial digit run; partial serials (`ipx-69…` vs `IPX-697`) still fail.
- MemoJav inventory holes remain 未匹配 until the site publishes `/video/<number>`.
