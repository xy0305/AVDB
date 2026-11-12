# Build 348 — actor ranking grid scroll jank: two causes, both fixed

Base: Build 347 / `5514533`, `feat/actor-ranking-period-347`. MARKETING 1.0.2, build 348. Branch `feat/actor-grid-scroll-348`. Unsigned IPA: `AVDB-unsigned-1.0.2-348-actor-grid-scroll.ipa` (CI artifact `AVDB-348-release`). This build stacks on 347 (and therefore 346/345/344/343).

Context: on Build 347 the user asked (2026-11-13 00:58): 「为什么有码演员月榜，上下滑动会卡顿」. Diagnosis was evidence-checked before coding:

- **Not the images.** Sampled actor avatars from the rankings endpoint decrypt to 100×100 – 320×320 JPEGs of 5–110 KB; fetch/decrypt/downsample runs in a detached task inside `ImageLoader` and results are NSCache-cached. The grid is a proper `LazyVGrid`; `ClippedAspectFill` is trivial.
- **Cause 1 (pervasive): the alias catalog was rebuilt for every cell, on the main thread.** `ActorAvatarArtwork.identity` — evaluated on every body pass to key the cell's `.task` — calls `JavBusActorService.names(actor)`, which called `ActorAliasCatalog.bundled()`, which re-read the bundled `ActorAliasIndex.json` from disk, re-decoded all 8,115 records (922,092 bytes) and rebuilt the record/alias/conflict dictionaries. No caching existed anywhere in that chain. Scrolling creates cells continuously, so the main actor kept paying a full catalog rebuild per new cell; every `RankingsViewModel` republish (loading toggles, page appends) made all visible cells pay it again at once.
- **Cause 2 (amplifier at the bottom): the actor endpoint ignores `page`, and paging never ended.** Verified live 2026-11-13 with the app's own signing: pages 1, 2 and 3 of `GET /api/v1/rankings/actors` return the identical list （有碼 94, 歐美 80). `RankingsViewModel.fetch` deduped the appends (so no visible duplicates) but set `hasMore = !list.isEmpty`, which stayed true forever — every pass over the last cell fired another page request, toggling `isLoading` and republishing the whole grid, which fed straight back into Cause 1.

## Changes

- `ActorAliasCatalog.bundled()` now returns a `private static let cached` catalog, built exactly once (the bundled index is immutable at runtime; the one call site, `JavBusActorService.names()`, is unchanged). This fixes every user of `ActorAvatarArtwork` — rankings, the actors tab, search results and detail cast rows — not just the ranking grid.
- `RankingsViewModel.fetch`, actors branch only: `hasMore` is now decided by what a page actually appended — page 1 by the list itself, later pages by the fresh (non-duplicate) count, so a zero-new page ends paging, the same rule Build 346 gave the shared movie-list view model. The movies branch of the same fetch (TOP250 / playback / 作品 rankings, whose endpoints genuinely paginate) is byte-for-byte unchanged.

## What did NOT change

- The avatar fallback chain (JavBus / Gfriends / Avbase / TMDB), the actor endpoint, the grid layout, rank chips and tap-through to ActorDetailView.
- 作品 rankings pagination, TOP250, playback.

## Visible scope for the user

排行榜 → 有碼 （及無碼 / 歐美） → 演員月榜： scrolling no longer rebuilds the alias catalog per cell, and reaching the bottom no longer refetches forever. The list content is identical — same actors, same order, same avatars.

Planned and implemented jointly with Muse and Kai.
