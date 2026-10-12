# JavLibrary native source — build 174

Independent branch `feature/javlibrary-174`, based on `5cd19dd` (173). Existing 173 IPA is not replaced. No merge to main, player/115 code changes, remote list changes, or 115 writes.

## Native feature
- Ranking tab has a separate **JavLibrary** navigation entry, retaining JavDB and JAV Ranking.
- Default independently configurable source: `https://www.javlibrary.com`.
- MostWanted `/cn/vl_mostwanted.php`, HighlyRated `/cn/vl_bestrated.php`, ActorRankings `/cn/star_mostfav.php`.
- Movie filter labels/options are parsed from source HTML (supported mode 0/1/2); no fabricated time ranges. Actual source `page next` links are followed, constrained to same HTTPS host/path and monotonically advancing page number, with visited-page and identity deduplication.
- Native SwiftUI cards use existing aspect-fill helper, poster ratio and adaptive column policy for iOS 17 phone/iPad. Actor rows preserve source rank where present.
- A movie tap uses existing `exactMovie(code:)`; only a validated exact-code match enters existing `MovieDetailView(movieID:)`. Existing read-only 115 discovery/playback workflow is reused there. A missing/ambiguous/error match explicitly offers the source page, never a fabricated JavDB ID.
- Actor identity is **not** guessed or fuzzily matched. Actor row explicitly links its source actor page instead.

## Access and verification
Normal public GET checks on 2026-10-13 (Asia/Shanghai) returned HTTP 403 and `cf-mitigated: challenge` for **all three** URLs. See tracked `scripts/javlibrary-fixtures/access-evidence.json`. Live ranking data was not fetched successfully; source structure compatibility after verification is not proven by these checks.

Challenge status/header/body detection produces a visible explanation, ends loading, and offers an explicit user action to open a separate visible WK website-verification browser. It is not a native content wrapper. The user operates the website themselves. HTTPS main-frame navigation is limited to the configured host; provider subframes may load normally. No automated CAPTCHA solving, stealth, token creation, proxy or WAF bypass.

The browser uses a nonpersistent isolated website store. On explicit **完成并重试**, only secure, unexpired cookies whose normal domain applies to the configured host are accepted; they are kept only in memory, sent only to that exact HTTPS configured host with applicable path, and erased on domain change/session termination. No shared JavDB/115 cookie store or credentials are imported. Public posters also use independent ephemeral sessions without a cookie store. Cookie values are not logged or saved. No Keychain persistence is claimed or implemented.

**Actual Cloudflare completion and native-session reuse on a user's iOS device remain untested.** The website may still reject a valid browser session in URLSession. UI does not promise verification success or endlessly retry.

## Validation
`python3 scripts/test-javlibrary.py --require-swift` executes the actual Swift core on macOS CI, with route/domain/filter/pagination/identity/exact-code/challenge and cookie-domain cases. Static integration contracts additionally guard existing detail reuse, independent sessions, actor source fallback, no 115 calls, no JavaScript automation and project source registration.

Successful video/actor HTML fixtures are explicitly named **mock-***; they are contract fixtures, not claimed live captures. The real challenge sample is sanitized to remove all executable challenge code/nonces/identifiers. Existing JavRanking/auth/player/115 regressions remain CI gates. Real-device native UI, iPad gestures, actual source filter labels and verified-session success require device testing; an unsigned IPA cannot establish those results.
