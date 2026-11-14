# Build 350 — Rankings Auth (rankings endpoints behind the JWT gate)

Delivered by Muse (Kai) for the AVDB project. This package is **unsigned**
(`AVDB-unsigned-1.0.2-350-rankings-auth.ipa`).

## Why

The user reported on 2026-11-14: 「排行里所有都要求登录」 — every board in
the Rankings tab asked for a login — and scoped the fix: 「排行里 看热播
有码 无码 欧美 fc2 都要有」 (the playback board and all four catalogue
types must all work).

## Live audit (2026-11-14, official signature, no token)

Every rankings request now requires the account JWT:

- `GET /api/v1/rankings` — types 0 （有码） / 1 （无码） / 2 （欧美） / 3 (FC2),
  daily / weekly / monthly: all return `success=0`,
  `action=JWTVerificationError`, 「請登錄帳號」.
- `GET /api/v1/rankings/actors` — same.
- `GET /api/v1/rankings/playback` （看热播） — same.

The full-interface re-check the user asked for found one more flip since
the Build 335 audit: `GET /api/v1/search_magnet` now also returns
JWTVerificationError anonymously. Everything else the SDK calls without a
token still answers anonymously (recommend, latest, recommend_periods,
movies/tags, actors list/detail/recommend, series letters/list/detail,
makers list/detail, tags, articles, startup, helps, about, ads,
magnet_apps, plans), and `/api/v4/movies/{id}` already carried the token
in the SDK. Detail endpoints for publishers/directors/codes/lists could
not be harvested anonymously and were not re-tested.

## Change

`JavDBSDK` only, following the exact Build 335 pattern (`useToken: true`):

- `rankings(type:period:page:)` — covers 有码 / 无码 / 欧美 / FC2 movie boards.
- `actorRankings(type:period:page:)` — covers the 有码 / 无码 / 欧美 actor
  boards (FC2 has no actor board, unchanged from Build 345).
- `playbackRankings(filterBy:period:page:)` — the 看热播 board, also used
  by the home hero and the rankings tab.
- `searchMagnet(_:page:)` — the audit-found extra flip, same one-line fix.

Nothing else changes: the feed pre-fill (349), VerificationThrottle and
FollowUpdates are untouched, and guests without an account still cannot
load the rankings — that is the server's rule now, surfaced by the
existing error path instead of a silent empty board where the SDK checks
`isSuccess`.
