# Build 308 — 底栏新增 ONE

User: 「AVDB 新增加一个底栏 one，这是别的应用脚本，适配到我的应用上来」
with `one-rex.js` — a Forward/Rex widget script for ONE 一个 (v2.2.0) written
for another app. The script is reference data only; nothing of it is evaluated.

## Protocol verification (before writing any Swift)

Replicated the script's protocol in Python against the live service:
- Guest `bootstrap` on the first seed host returns a token + domain tables.
- `article/discovery` (models 6+3, current month) and `article/search` work.
- With `app-version: 1.6.0` the detail payload carries the full MP4 in
  `video_download` (newer protocol versions only get the 4-minute preview);
  the MP4 answers Range requests (206, ftyp) on the `video` CDN hosts.
- Covers resolve to real JPEGs on the `flutter_img` hosts.

## Change

- New bottom tab **ONE** (7th, between 糖心 and 我的): `AppTab.one`,
  ContentView routes it to `OneRootView`. The bar already iterates
  `AppTab.allCases`, so no tab-bar layout code changes.
- `AVDB/Services/OneCore.swift` — native port of the protocol:
  AES-128-CBC (CommonCrypto) request encryption / response decryption,
  MD5 request signing (CryptoKit), guest session persisted in UserDefaults,
  host failover across seed + issued API hosts, one forced re-bootstrap on
  401. Feeds follow the script: newest/hot accumulate month by month
  (models 6+3, hot sorts each month by like_number); 日本/国产/欧美 classify
  each month locally (site tag tables first, then strong title markers,
  kana, code pattern, keyword tables, CJK/Latin ratio); 直播 pages through
  the `ONE直播` search. Playback lines prefer the full `video_download` MP4
  across up to 5 CDN hosts; HLS is kept only as a labelled fallback.
  Preview-only items are filtered out of the month feeds.
- `AVDB/Views/OneView.swift` — section chips （最新/热门/日本/国产/欧美/直播）,
  landscape grid, search screen (hides the floating tab bar like the app's
  own search), detail with cover-play hero, per-line picker, collection
  episodes and tag/author keyword navigation. Playback reuses
  `KSChromePlayer` with `progressID "one:<id>"`.
- Same age/consent screen as the Tangxin port (`TangxinPolicy.permitted`)
  is applied to ONE titles/tags in lists and detail.
- Playback history: ONE entries get the `one:` id prefix and a `.one`
  history route, so 我的 → 观看历史 reopens the ONE detail (poster via
  `OneImage`) instead of a JavDB detail; deleting an entry does not clear
  the shared 番号 resume book.
- Contracts: new test-one308 (wired into home-hq298.yml); exact-version
  pins moved 307 → 308 in test-ai-cover286, test-live297 (package script
  pin → package-lut308.py), test-playback-history, test-watch-history277.

## Not covered

- ONE account login (the tab is guest-only, like the script); live-replay
  collections whose full video needs a ONE account stay preview-only.
- Series （写真/漫画连载） and actor browsing from the script's detail
  resolver are not separate ONE sections in this build; article detail,
  episodes, tags and search are covered.
- Encrypted HLS manifests are listed as fallback lines only and may not
  play; the MP4 lines are the primary route.

## Version

CFBundleVersion / CURRENT_PROJECT_VERSION = 308
IPA: `AVDB-unsigned-1.0.2-308-one-tab.ipa`
