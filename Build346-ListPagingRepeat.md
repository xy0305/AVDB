# Build 346 — shared list paging can no longer repeat a fixed list forever

Base: Build 345 / `3580893`, `feat/western-actor-ranking-345`. MARKETING 1.0.2, build 346. Branch `feat/list-paging-repeat-346`. Unsigned IPA: `AVDB-unsigned-1.0.2-346-list-paging-repeat.ipa` (CI artifact `AVDB-346-release`). This build stacks on 345 (and therefore 344/343), so its package also contains the western monthly actor ranking and the poster-grid bottom clearance.

Context: on Build 344 the user screen-recorded the 第610期 recommend-period page: its movies repeated endlessly while scrolling (the same ten titles cycling). Root cause was verified live before coding, using the app's own API signing: `GET /api/v1/movies/recommend` ignores the `page` parameter for a period query — pages 1, 2 and 3 for period 610 return the identical ten movies (XV-465, DIGI-211, APNS-121, YMDD-230, MIDE-991, GVH-337, DASS-481, MIDV-967, KSBJ-416, IPZZ-809) — because a period is one fixed list. `MovieListViewModel.loadMore`, the shared paging view model behind the period page and many other lists, appended each page verbatim and only stopped on an empty page, so every "next page" re-appended the whole period. The defect stayed invisible while the last row was trapped under the floating tab bar; Build 344's clearance let the last cell rest in view and fire `onAppearLast` at rest, which surfaced it. Build 344 itself is not at fault — the recording's final frames show its fix working.

## Change (MovieListViewModel.swift, `loadMore` only)

- Appends are filtered through a seen-id set: ids already shown (earlier pages, or repeated within the same page) are dropped before appending.
- A page that contributes zero new movies now sets `hasMore = false` — the list ends there instead of fetching the same page forever. This is the same rule `CatalogListViewModel` in the same file already applies (`hasMore = !result.isEmpty && appended > 0`).

## What did NOT change

- Properly paged endpoints behave exactly as before: their pages keep contributing new ids until an empty page ends the list. `refresh()`, sort selection, error handling and the `onAppearLast` trigger are untouched.
- The recommend endpoint call itself (the app cannot make the server paginate a fixed period list; robustness belongs in the paging layer, and now every list on this view model — categories, lists, search, collections, following tags — is protected against the same class of server behaviour).
- Builds 343/344/345 changes.

## Visible scope for the user

The 第610期 page (and every other period page) now shows its ten movies once and stops at the end. No list can duplicate entries while scrolling anymore.

Planned and implemented jointly with Muse and Kai.
