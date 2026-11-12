# Build 347 — the monthly actor ranking no longer wears the 作品 period bar

Base: Build 346 / `c27140c`, `feat/list-paging-repeat-346`. MARKETING 1.0.2, build 347. Branch `feat/actor-ranking-period-347`. Unsigned IPA: `AVDB-unsigned-1.0.2-347-actor-ranking-period.ipa` (CI artifact `AVDB-347-release`). This build stacks on 346 (and therefore 345/344/343), so its package also contains the paging-repeat fix, the western monthly actor ranking, the poster-grid bottom clearance and the landscape-cover fix.

Context: on Build 346 the user opened 排行榜 → 歐美 → 演員月榜 and reported (2026-11-12 23:22, with a screenshot): 「欧美演员月榜不应该分日榜 周榜 总榜，只有作品有这三个分类」. He was right about the structure AVDB presented: since Build 345 the boards with an actor ranking showed two stacked bars — 日榜 / 周榜 / 月榜 on top, 作品 / 演員月榜 below — and the period bar stayed visible and selectable in actor mode. The actor list itself never actually split by period: the actor loader has always requested period "monthly" from `GET /api/v1/rankings/actors`. So in actor mode the 日榜 / 周榜 chips were decoration that reloaded the identical monthly list under a different label.

## Change (RankingsView.swift, view layer only)

- New `showingActorRanking` helper: the segment is on "actors" AND the board has a genuine actor ranking (Build 345's `actorRankingType(for:)` — 有碼 0, 無碼 1, 歐美 2; FC2 has none).
- The 日榜 / 周榜 / 月榜 `CapsuleChipBar` renders only when NOT `showingActorRanking`. In actor mode the only bar left above the grid is 作品 / 演員月榜.
- `reload()` pins the request period to `.monthly` in actor mode, so the request identity says what the loader already did. The user's selected 作品 period stays in state and comes back untouched when switching back to 作品.

## What did NOT change

- 作品 rankings: 日榜 / 周榜 / 月榜 exactly as before, on every board.
- 看熱播： its own 高評價 / 全部 + 日榜 / 周榜 / 月榜 bars are a works ranking and stay as they are. TOP250 unchanged. FC2 has no actor segment (Build 345) and keeps its period bar.
- The actor endpoint, the loader, the actor grid, pagination, pull-to-refresh and tap-through to ActorDetailView are all untouched; the same monthly list shows, now without the misleading period bar above it.

## Visible scope for the user

排行榜 → 歐美 (also 有碼 / 無碼） → 演員月榜： the 日榜 / 周榜 / 月榜 bar is gone; only 作品 / 演員月榜 remains above the actor grid. Tapping 作品 brings the period bar back with the previously selected period.

Planned and implemented jointly with Muse and Kai.
