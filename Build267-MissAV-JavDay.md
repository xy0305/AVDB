# Build 267 — MissAV 403 mitigations + JavDay online source

## MissAV intermittent 403 (widget transfer assessment)

**Verdict: partial.** The Forward Widget’s transferable pieces that AVDB can adopt without a browser JS challenge solver:

| Widget pattern | Transferred? | Notes |
|---|---|---|
| Mobile Safari UA + Referer `host/` | Already present (ranking); online UA bumped to iOS 18.5 | Helps soft WAF / fingerprint gaps |
| `isCloudflareChallengeHtml` (title / human text; ignore passive `cdn-cgi` alone; don’t false-positive large pages with real cards) | Yes — `MissAVHTML.isChallenge` refined | Avoids treating success pages with jsd as blocks |
| `fetchHtmlWithRetry` on challenge/403/429/503 | Yes — `MissAVSource.html` retries up to 3 attempts with backoff | Helps intermittent soft blocks |
| Clear blocked status vs silent empty | Already present; retry exhaustion message clarified | Native cannot import browser CF cookies |
| Full Cloudflare managed JS challenge solve | **No** | URLSession / ephemeral cookies cannot run `chl_page` like a WebView host; we do not claim a bypass |
| WKWebView cookie warm-up | **No** | Ranking/online deliberately stay off WebKit cookie import (same safety line as Build 174/254) |

Live check from this environment: `missav.fans` list pages often return 200 with real cards; `missav.ws` search commonly returns CF “Just a moment” 403. Online MissAV remains on `missav.ws` per Build 254 (no silent fans mirror rewrite).

## JavDay online video source

New `OnlineSource.javday` (“JavDay”) alongside Jable / MissAV / 123AV / MemoJav.

- Search: `https://javday.app/search/wd/{code}/` (path form; widget’s `/search/?wd=` is allowlisted but often CF-challenged)
- Detail identity: `/videos/{slug}/` or `/index.php/videos/{slug}/` + `og:url` / `h1` / `og:title` catalogue match
- Media: page-issued `.m3u8` from `<source>`, DPlayer/Artplayer `url:` literals only — observed CDN apex `javday.homes` (edge hosts `*.javday.homes` allowed for HLS children)
- Headers: desktop Chrome UA + Referer/Origin `https://javday.app/`
- UI: appears via existing `OnlineSource.allCases` rows in the detail online panel

No remote JS execution, no cookie import, no captcha solve. Neutral fixture regressions updated to five sources; macOS CI still owns Swift runtime proof.

