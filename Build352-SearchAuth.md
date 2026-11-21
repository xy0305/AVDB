# Build 352 — Search Auth (full endpoint sweep: every gated endpoint now sends the token)

Delivered by Muse (Kai) for the AVDB project. This package is **unsigned**
(`AVDB-unsigned-1.0.2-352-searchauth.ipa`).

## Why

The user reported on 2026-11-21: 「javdb 现在搜索也要求登录了，修改 AVDB」 —
JavDB now requires login for search too; fix AVDB. This build is based on
the rolled-back Build 351 line (`revert/to-build-351`); the archived
352/353/354 branches are untouched.

## Live audit (2026-11-21, official signature, no token)

Anonymous calls now rejected with `success=0`,
`action=JWTVerificationError`, 「請登錄帳號」:

- `GET /api/v2/search` — movie and actor types tested; the whole search
  family is gated. The SDK has sent the token here since Build 335, but
  with no stored token the request went out anonymously and failed, and
  the actor/named/list result tabs swallowed the error with `try?` and
  rendered a silent empty page.
- `GET /api/v2/search_image` — same family. (The anonymous probe with a
  sample image URL returned HTTP 404 rather than the JSON rejection, so
  the probe itself is inconclusive; the endpoint already sent the token
  since Build 335 and gets the same fail-fast as the rest of the family.)
- `GET /api/v1/movies/tags` — flipped since the Build 350 audit (it was
  still anonymous then). It backs category browsing, list pages and the
  recommender's tag path, and the SDK called it **without** the token,
  so those surfaces were broken for every user, logged in or not.
- `GET /api/v1/series` (list) — flipped; series detail and letters still
  answer anonymously.
- `GET /api/v1/directors/{id}` and `GET /api/v1/makers/{id}` — flipped;
  the list endpoints still answer anonymously.
- `GET /api/v4/movies/{id}` — anonymous now rejected too; the SDK already
  sends the token (since Build 327) and Build 340 already handles its
  auth errors, so no change was needed there.

Completion round (same day, after the user asked
「查看 javdb 哪些接口要 token 全补上」 — audit every endpoint and add the
token everywhere it is required). Every endpoint below was re-tested
anonymously three times:

- `GET /api/v2/tags` — rejected 3/3. Both SDK callers (`tagGroups`,
  `tags`) called it **without** the token; the filter options and the
  tag list were broken for every user.
- `GET /api/v1/movies/{id}/magnets` — rejected 3/3 (and 3/3 again in the
  first sweep). `movieMagnets` called it **without** the token, so the
  detail page's magnet list was broken for every user. (The magnet
  *search* endpoint was already fixed in Build 350; this is the
  per-movie list.)
- `GET /api/v2/users/{id}/reviews` — rejected 3/3; `userReviews` called
  it **without** the token.
- Rollout nuance: the series list and the maker/director detail
  endpoints answered `JWTVerificationError` in the first round and
  `success` in the final round — the gate looks like a progressive
  rollout rather than a single flip. They keep the token either way;
  sending it only matters when a token is stored.

Still anonymous (re-checked, three times each where an id was needed):
movies/latest, movies/recommend, movies/recommend_periods, actors
list/detail/recommend, series detail/letters, makers list, directors
list, articles, lists/related, lists/{id}, ads, startup, about,
magnet_apps, v3/plans, v4/plans. `reviews/hotly` and `helps` answer
`ParameterInvalid` (they now demand parameters the SDK never sent) —
that is parameter drift, not an auth gate, and is left alone in this
build. `publishers/{id}` and `codes/{id}` ids could not be harvested
anonymously; both got the token anyway as part of the same detail
family.

## Change

`JavDBSDK`:

- The search family (`search`, `searchActors`, `searchNamed`,
  `searchLists`, `searchImage`, `searchMagnet`) fails fast with
  `JavDBError.notLoggedIn` when no token is stored, instead of firing an
  anonymous request that is guaranteed to be rejected.
- `moviesByTag` (`/api/v1/movies/tags`), `series(type:)`
  (`/api/v1/series`), `directorDetail`, `makerDetail` and
  `publisherDetail` now send the account token (`useToken: true`), the
  exact Build 335/350 pattern.
- Completion round: `movieMagnets` (`/api/v1/movies/{id}/magnets`),
  `tagGroups` and `tags` (`/api/v2/tags`), `userReviews`
  (`/api/v2/users/{id}/reviews`) and `codeDetail`
  (`/api/v1/codes/{id}`) now send the token too. After this build every
  SDK endpoint the audit found gated sends the token; every endpoint
  verified anonymous stays anonymous.

`SearchView`:

- New shared `SearchLoginPrompt`: on an auth failure every result tab
  shows 「搜索需要登录」 with a 「去登录」 entry (sheet `LoginView`, the
  Build 340 pattern) instead of the server's raw error string or a
  silent empty page.
- The movie tab branches on `JavDBError.isAuthenticationMessage`;
  the actor/named/list tabs no longer swallow errors with `try?` — they
  record the error and whether it is an authentication failure.
- All four result tabs reload on `.avdbCatalogAccountChanged`, so a
  successful login continues the search automatically.

## Not changed

- Endpoints verified still anonymous keep their anonymous calls.
- No change to the rankings (350), detail auth (327/340), recommender
  throttling (337), enrichment (351) behaviour beyond the version roll.
- Logged-in search already sent the token since Build 335; what changes
  for a logged-in user in this build is that category browsing, list
  pages, the series tab, maker/director pages, the detail page's magnet
  list, the tag filter options and user review pages work again (they
  were calling newly-gated endpoints anonymously). What changes for a
  logged-out user is that search now explains itself and offers login
  instead of failing silently.
