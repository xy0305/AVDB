# Build 337 — de-risking automated JavDB traffic: 「为你推荐」 manual-only + shared verification throttle

Base: Build 336 / `2b14e7a`, `feat/remove-javverse-336`. MARKETING 1.0.2, build 337. Branch `feat/recommender-throttle-337`. Unsigned IPA: `AVDB-unsigned-1.0.2-337-recommender-throttle.ipa` (CI artifact `AVDB-337-release`).

Context: on 2026-11-12 the user posted JavDB's announcement — the site has enabled risk control against automated high-frequency scraping and is permanently banning accounts that exceed normal use. Auditing AVDB against that description, the 281 recommender's request volume was already budgeted, but two behavioural signatures were machine-like: it refreshed automatically when the page appeared, and its requests were spaced by an exact 1.0 s metronome. The user chose the fix over removal (2026-11-12): manual refresh + random slow spacing + a hard cap.

## Changes (`RecommendationStore.swift`, `RecommendationJavDBSource.swift`)

1. **Manual-only network.** Appearing on the recommendations page now performs a local recompute from the on-device cache only — the automatic network refresh (and its 6 h `autoRefreshInterval`) is gone. Pull-to-refresh (manual) is the only path that fetches; the non-manual budgets are 0, so even a stray non-manual run cannot issue a request.
2. **Random slow spacing.** `requestSpacing` is no longer a fixed 1.0 s: every gap is a fresh `Double.random(in: 2.5...5.0)` draw, so a run's cadence looks like a person pausing between taps.
3. **Hard total cap.** One manual run may issue at most **10 requests in total** (`totalRequestBudget`) across all three phases — seed details, sourcing lists, top-of-feed hydration — enforced by the shared request counter at every loop. The per-phase budgets drop to 6 list calls / 6 details (from 10/10 manual), so the phases share the cap instead of stacking to 30.

Unchanged: the on-device ranking model, signals, pools and their 12 h TTL, feedback actions, and the page's layout. Cached recommendations remain fully browsable offline.

## Also in this build (user, 2026-11-12): every external ranking source's automatic verification

The same audit found the same pattern in all remaining external ranking sources: rows appearing on screen were automatically verified against JavDB. All three verification engines now pass through one shared throttle, `VerificationThrottle` (`AVDB/Services/VerificationThrottle.swift`):

- **One at a time** — JAV Ranking's 3-wide match queue, MissAV/JAVLibrary/中指通's 2-wide metadata queue (one shared `MissAVMetadata` engine covers all three), and DMM's mapper batches are all serialized by the gate.
- **Random spacing** — after each automatic verification finishes, the next one waits a fresh random 1.5–3.5 s.
- **Global cap** — at most 20 automatic verifications start per rolling minute, shared across all sources (the site sees one client, so the budget is global, not per source).

User-initiated checks never pass the gate: JAV Ranking's interactive match taps, DMM rows' 「精确核对AVDB」 retry, and the MissAV verification sheet keep their direct path — they are the user's own actions. Existing caches are untouched (JAV Ranking keeps its 6 h match cache; the mapper keeps its shared cache), so re-opening a board still costs almost nothing; only a cold scroll advances at human pace now.

Planned and implemented jointly with Muse and Kai.
