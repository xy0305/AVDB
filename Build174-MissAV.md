# MissAV additional rankings — build 174

## Baseline / clarified scope
Fresh clone main `5cd19ddd29c7ac3bbdf20e8eef3aace615c34709` is build **173**, marketing **1.0.2**. Independent `/tmp/AVDB-missav-ranking` leaves existing user changes untouched. Build 174 adds, never replaces: all AVDB ranking tabs/filters, JAV Ranking and native search stay; default is still original AVDB. MissAV is a separate ranking entry. Uploaded JS was reviewed for list/title selectors, sort/page URLs, slug and detail number extraction, not embedded. Its missav.fans default and stale dm prefixes are not blindly copied; player/HLS/trailer/cover synthesis excluded.

## Read-only live facts, 2026-10-13 Asia/Shanghai
Browser root naturally resolved to `https://missav.ws/dm265/en`. No CAPTCHA clicked, account login or clearance-cookie export. Browser-session GET 200 verified:
- https://missav.ws/dm301/cn/today-hot
- https://missav.ws/dm170/cn/weekly-hot
- https://missav.ws/dm170/cn/weekly-hot?page=2
- https://missav.ws/dm273/cn/monthly-hot
- https://missav.ws/cn/mimk-288

12 `div.thumbnail` cards each; `a.text-secondary` title anchors, original fourhoi.com HTTPS covers, displayed duration. Actual rel=next page links increment to page 2/3, distinct page-two cards. Source navigation advertises day/week/month. Other site sort/filter options are deliberately not exposed. Preserve source DOM order, no invented ranks/scores/magnets or AVDB secondary sorting.

curl GET root, /cn/weekly-hot and /cn/monthly-hot returned Cloudflare **403**. Browser 200 is NOT native URLSession or device proof. Native transport errors are visible with retry/settings; no verification bypass or cookie import. Independent HTTPS-root domain setting cancels old tasks/generation; cross-host redirects rejected. Scriptless successful fixtures remove temporary public CSRF tokens; original byte hashes/sizes/URLs in scripts/missav-fixtures/capture.json. Blocked fixture retained.

## Number → AVDB → 115
Conservative full code from slug with observed edition suffixes only; title conflicts disable mapping. Missing code only may request source detail to extract explicit 番号; there is no independent full MissAV detail/player. Never use source path/slug as JavDB ID. Native card images/titles remain source metadata, using MoviePosterCard/adaptive columns. Refresh/period/page/reset tasks have cancellation + generation/revision guards; same-route next links, stable dedup, repeated pages rejected.

Tap calls existing SDK Movie search (`type=movie`, NOT `type=code`) and decoder via optional `exactMovie(...verifyAllPages:true)`. Strict mode searches up to 3 returned pages, stopping at short final page, requires exact normalized complete number + valid movie ID. Different IDs same number → explicit ambiguity; same ID dedup. This is bounded search, not exhaustive beyond page 3. Default existing SDK fast/cache behavior unchanged. Account change/cancellation blocks stale matches. No fuzzy first-hit navigation. Unique match enters existing MovieDetailView; otherwise retry + original AVDB number search results for manual verification and unavailable-115 notice.

115 operation: existing 我的 settings Cookie/target directory → MissAV ranking → exact AVDB match → original movie detail magnets → user chooses real resource and existing cloud-arrow push UI. Reuses original cookie normalization, folder, offline result/UI and playback cache. No credentials reach MissAV. Original magnet row gains pure preflight: valid BTIH 40-hex/32-base32 or complete ed2k file/hash only; HTTP webpage/m3u8/malformed links rejected before client runs. No fabricated links. No change to 115 endpoints/signing/crypto. No live push/login/write/delete executed in tests.

## Tests / limitations
scripts/test-missav.py compiles shipping Swift parser + MissAVSource and replays real day/week/month/page-two/detail/403 captures: DOM order, number/suffix/conflict/missing code, route/image allowlists, real next links, no fabricated metadata. URLProtocol mocked 200/403/200-challenge/reset/cancellation exercises shipping URLSession. Pure 115 resource tests never touch network. Existing production Movie/SDK replay adds cross-page ambiguity and same-ID dedup; default request/cache regressions remain.

macOS IPA CI executes these Swift runtime tests, existing parser/mapping/performance/iPad/layout/player/gesture/audio/seek/Metal/LUT/115 crypto regressions, and actual iphoneos Release build. iSH has no Swift: local Python/static checks alone are NOT Swift runtime proof. Existing iPad simulator navigation workflow may be dispatched for original neutral regression, not claimed as live MissAV/115 validation.

No player, gesture, audio session, LUT, subscription or 115 playback implementation rewritten. Version remains marketing 1.0.2 / build174. Unsigned IPA requires signing/sideloading. CI/fixtures are not true-device/native visual/live URLSession/full-player or real-115 acceptance; these remain explicitly unverified.
