# Build 353 — External boards match AVFan (JavDB zero-request)

Author: Muse (Kai), for the AVDB owner. Artifact: AVDB-353-release
(unsigned IPA AVDB-unsigned-1.0.2-353-avfanboards.ipa).

## What changed

The five external ranking boards — DMM (daily/weekly/monthly/actress),
JAV Ranking, MissAV, JAVLibrary, 中指通 — keep their existing live
list sources untouched (FANZA GraphQL/WebView, javranking.cc direct,
MissAV direct, the VPS JAVLibrary snapshot, the bundled 中指通
catalog). Only the matching layer changes: the frozen JavDB
pre-matching feed (RankingFeedState) is retired on these five boards,
and entries now match **avfan** by exact code (the DMM actress board
by exact name):

- Posters and titles come from the avfan match; unmatched entries
  show the code placeholder.
- Tapping a matched entry opens the new `AvfanMovieDetailView`
  (hero cover, metadata, casts, avfan magnets with sizes; magnets
  can be pushed to the user's own 115 via the existing Pan115Client).
- Tapping an unmatched entry says 「AVFan 暂无此作」. It never falls
  back to a JavDB search.
- Hard rule: no `JavDBSDK` call and no `VerificationThrottle`
  verification anywhere in the five boards' render, scroll,
  prefetch or tap paths (grep-verified; the poster cards' HQ upgrade
  is disabled on these grids for the same reason).

## New avfan layer (ported from AVFan)

- `AVDB/Services/AvfanClient.swift` — models, the HTML parser subset
  (search cards, detail, magnets, cast search, session signals),
  the client (mobile Safari UA, shared cookie storage, WKWebView
  fallback when URLSession is blocked by Cloudflare), the cookie
  bridge and the session store. Public pages only; never `/api/`,
  `/autocomplete`, `/user/` or any login-gated account page.
- `AVDB/Services/AvfanMatchStore.swift` — the matching engine:
  3 concurrent workers, AvfanClient's 3 lanes keep ~0.4 s spacing
  per lane; FIFO priority queue (visible entries first, then
  background fill); results persist on disk (code → pathID/cover/
  title, actor name → href/avatar) and are never re-queried; misses
  are session-only; a 403/429 degrades to serial and pauses
  prefetch with a low-key status line. MissAV codes are stripped of
  `-UNCENSORED-LEAK` / `-CHINESE-SUBTITLE` before matching; DMM
  entries match by the maker code DMMRankingStore resolved (never
  derived from the CID).

## avfan login (supplement)

Settings （我的 page) gains an 「avfan 账号」 section (status / login /
logout), and the avfan detail page shows a subtle login hint while
signed out. The flow is AVFan's locked scheme: a native-looking
form whose real submission runs inside a WKWebView on avfan's real
sign-in page (the captcha is completed in the WebView — that is
normal). On success the cookies land in AvfanClient's shared cookie
storage, so board matching and detail fetches carry the login state
automatically. Logout clears both cookie stores. Login only makes
public-page fetches carry the session (magnet completeness); it
does not widen what is fetched, and credentials pass through the
WebView page itself — the password is never handled or stored.

## Not verified

avfan scraping and the login flow under the owner's real network
(Cloudflare behaviour, cookie carry-over, magnet completeness) need
on-device verification; no live avfan or JavDB requests were made
from the build sandbox.
