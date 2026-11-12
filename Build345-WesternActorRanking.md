# Build 345 — the monthly actor ranking reaches the 欧美 (and 无码) boards

Base: Build 344 / `e8d6f42`, `feat/list-tabbar-clearance-344`. MARKETING 1.0.2, build 345. Branch `feat/western-actor-ranking-345`. Unsigned IPA: `AVDB-unsigned-1.0.2-345-western-actor-ranking.ipa` (CI artifact `AVDB-345-release`). This build stacks on 344, so its package also contains the poster-grid bottom clearance.

Context: the user supplied a screenshot of the official JavDB app's 排行榜 → 歐美 board, whose period row offers 日榜 / 周榜 / 月榜 / 演員月榜， and asked for the 欧美 monthly actor ranking endpoint to be fetched from JavDB and added to AVDB, "related operations included". Audit first: the endpoint — `GET /api/v1/rankings/actors` — already existed in `JavDBSDK.actorRankings`, and a 演員月榜 segment already existed in `RankingsView`, but only on the 有碼 board, with the API type hardcoded to `"0"` in the view model's default loader and both the chip row and the fetch branch gated on `tab == .censored`. The endpoint was verified live before any code changed (anonymous request signed with the app's own scheme, 2026-11-12): type 2 （歐美） returns 80 actors whose first rows match the official app's screenshot exactly (Kendra Sunderland, Melody Marks, Angela White, Lena Anderson), type 1 （無碼） returns its own distinct list, type 0 （有碼） returns its list — and type 3 (FC2) merely echoes the censored board's list, so no genuine FC2 actor ranking exists server-side.

## Changes (all in RankingsView.swift)

1. **One source of truth**: `RankingsViewModel.actorRankingType(for:)` maps a board to its actor-ranking API type — 有碼 `"0"`, 無碼 `"1"`, 歐美 `"2"`, everything else (TOP250, 看熱播， FC2) `nil`.
2. **The 作品/演員月榜 chip row** now appears on every board the helper covers, instead of only 有碼.
3. **The view model follows the helper everywhere**: `showingActors`, the fetch branch, and the default actor loader (which now passes the current board's type instead of the hardcoded `"0"`).

## Related operations

Everything the segment needs rides the machinery the 有碼 segment already used, unchanged: the shared actor grid (`ActorRankingGridContent`, rank chips, avatar artwork with the silhouette fallback), pagination via the last cell's `onAppear`, pull-to-refresh, the error/retry surface, and tap-through to `ActorDetailView` (actor detail + filmography via the existing endpoints). The endpoint itself needs no login token (verified anonymously), matching how the movie rankings already behave.

## Deliberate exclusion

FC2 does not get the segment: its endpoint answer is the 有碼 list verbatim, so an FC2 演員月榜 would present the censored ranking under the wrong label. If JavDB ever serves a real FC2 list, adding it is a one-line case in the helper.

## What did NOT change

The movie rankings (all boards and periods), TOP250 and its filter sheet, the playback board, the other ranking sources (JAV Ranking, DMM, MissAV, 中指通， JAVLibrary), the SDK (the endpoint was already there), actor detail pages, and all network/throttling behaviour. This is a user-driven list call, one request per page, like the movie rankings.

## Visible scope for the user

排行榜 → 歐美 (and 無碼） now shows the 作品/演員月榜 chip row under the period row; 演員月榜 displays the monthly actor ranking grid, matching the official app's content and order for 歐美. Switching boards while 演員月榜 is selected carries the mode across the covered boards. 有碼 behaves exactly as before.

Planned and implemented jointly with Muse and Kai.
