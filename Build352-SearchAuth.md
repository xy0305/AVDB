# Build 352 — Search Auth (search and five more endpoints behind the JWT gate)

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
- `GET /api/v2/search_image` — same family, same rejection.
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

Still anonymous (re-checked in the same session): movies/latest,
movies/recommend, movies/recommend_periods, actors list/detail/recommend,
series detail/letters, makers list, directors list, v2/tags, articles,
lists/related, lists/{id}, movies/{id}/magnets. `reviews/hotly` answered
inconsistently (once success, then ParameterInvalid asking for a
`period` parameter the SDK never sent) — that is a parameter issue, not
an auth gate, and is left alone in this build. `publishers/{id}` and
`codes/{id}` could not be harvested anonymously; publishers got the
token anyway as part of the same detail family.

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
  pages, the series tab and maker/director pages work again (they were
  calling newly-gated endpoints anonymously). What changes for a
  logged-out user is that search now explains itself and offers login
  instead of failing silently.
