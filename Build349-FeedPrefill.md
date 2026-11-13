# Build 349 — Ranking boards read the server pre-matching feed first

Muse / Kai. Build 349, version 1.0.2, unsigned IPA
(`AVDB-unsigned-1.0.2-349-feed-prefill.ipa`).

## What changed

The five ranking boards now read the server-side pre-matching feed
before doing any on-device verification. The VPS pipeline resolves
source codes to JavDB identities once a day and publishes one JSON
per board/term on this repo's `feed` branch
(`feed/<board>-<term>.json`, the pipeline's `write_feed` naming rule).
A new `RankingFeedClient` (with the session store `RankingFeedState`)
fetches each file from the GitHub raw base, validates board/term and
`generated_at`, keeps the last good copy in Caches, and never lets an
older `generated_at` rewind a newer one. Each board/term is fetched
at most once per app session.

### Coverage by board

- **JAV Ranking (explore)** — `javranking-explore.json` pre-fills
  `JavRankingSource.matches` by exact code; posters and tap-through
  read it through the existing `cachedMovie` path.
- **DMM (daily / weekly / monthly)** — `dmm-<term>.json` pre-fills
  `JavVerseMapper.movies` per visible entry, matched by maker code.
- **DMM actress** — `dmm-actress.json` pre-fills the actress mapper
  by name.
- **MissAV (today-hot / weekly-hot / monthly-hot)** —
  `missav-<term>.json` seeds `MissAVMetadata.results` by exact code.
  The pipeline does not publish a MissAV actress feed, so the actress
  board runs entirely on the device fallback for now.
- **JAVLibrary (mostwanted / bestrated / actors)** —
  `javlibrary-<term>.json` seeds the same metadata queue: movies by
  exact code, actors by source URL (the actor request key on this
  board).
- **中指通 (per month)** — `zhongzhitong-<YYYY-MM>.json` is the
  primary matching source for that month's codes; the bundled
  `ZhongZhiTongMonthly.json` still provides the code list itself.
  The catalog's old `remoteURL` (main branch) is unchanged: the feed
  branch carries no same-name catalog file (checked 2026-11-13), and
  feed matching takes priority over the device queue regardless.

At delivery time the feed branch carries `dmm-daily.json`,
`javranking-explore.json` and `zhongzhitong-2026-10.json`; the other
files appear as the pipeline's daily increments publish them. Any
board or term without a feed file simply runs fully on the fallback
below — no error, no empty board.

### Fallback rules (device side stays the safety net)

- Entries the feed does not cover, a feed that cannot be fetched,
  and uncovered entries of a feed older than 48 hours all keep the
  existing on-device verification, through the shared
  `VerificationThrottle`. Automatic verification is **not** disabled.
- A fresh feed's `miss` verdict ends the automatic lookup for that
  entry; an explicit manual retry/refresh still falls through to the
  throttled verification, exactly as before.
- A fresh feed's `ambiguous` verdict is fail-closed: the entry shows
  as unmatched and is never re-resolved automatically.
- `pending` entries (the server's daily JavDB budget ran out before
  resolving them) are not seeded at all, so the device fallback owns
  them until the server catches up.
- Manual 核对/重试 keeps its original direct path everywhere;
  `FollowUpdates` and `VerificationThrottle` themselves are untouched.

### Freshness display

Every board shows “数据更新于 X” taken from the feed's
`generated_at`. Past 48 hours the note gains “· 可能过期”: the data
still displays, and the fallback covers whatever the stale feed
cannot. Boards whose feed has not been fetched yet (or does not
exist yet) show no note.

### Timing

Feeds are fetched lazily when a board is opened (once per board/term
per session) and applied before that board's automatic verification
queue starts, so covered entries never produce a JavDB request.
