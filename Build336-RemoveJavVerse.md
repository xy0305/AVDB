# Build 336 — Remove the JavVerse ranking

Base: Build 335 / `278c535`, `feat/detail-api-335`. MARKETING 1.0.2, build 336. Branch `feat/remove-javverse-336`. Unsigned IPA: `AVDB-unsigned-1.0.2-336-remove-javverse.ipa` (CI artifact `AVDB-336-release`).

Requested by the user on 2026-11-12: 「移除 javverse 榜单」 — remove the JavVerse ranking from the app.

## What was removed

- **Rankings source menu**: the 「JavVerse」 section (「原站名单 · 实时优先」, `javverse-source-entry`) and its navigation destination; the `RankingSourceDestination.javVerse` case is gone. The other sources (JavDB, JAV Ranking, DMM, MissAV, 中指通， JAVLibrary) are untouched.
- **The JavVerse view** (`JavVerseView.swift`) with its boards, Grok actress board and live/snapshot modes.
- **The live source**: `JavVerseLiveClient.swift` (site scraping + HTML parser) and the bundled snapshot resource `JavVerseSnapshot.json`; from `JavVerseSource.swift` the snapshot/board/Grok model types, the HTTP probe and `JavVerseReleaseProbe` are gone, as are the probe's branches in `AVDBApp.swift` (the app root is plain `ContentView()` again).
- **Dedicated test/CI surface**: `UITests/JavVerse{Behavior,Identity,Navigation}Tests.swift`, `scripts/test-javverse*.py`, `scripts/verify-javverse-provenance.py`, `scripts/register-javverse.rb`, `scripts/javverse-fixtures/`, and the `javverse-acceptance` / `javverse-schema247` workflows (both only ever triggered on a legacy branch).

## What deliberately stays

The ranked-entry **resolution layer** is shared infrastructure, not the JavVerse ranking: `JavVerseEntry`, `JavVerseIdentity`, `JavVerseFailure`, `JavVerseMapper` (in `JavVerseSource.swift`) and `JavVerseMovieResolver` / `JavVerseActorResolver` (in `JavVersePolicy.swift`, trimmed of pagination and the DEBUG neutral fixture). `DMMRankingView` builds its rows on the mapper and entry types, so they remain — removing them would have broken the DMM ranking, which the user did not ask to touch. The mapper's probe guard went with the probe: resolution now always runs.

Planned and implemented jointly with Muse and Kai.
