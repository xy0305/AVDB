# Build 341 — reviews first load can no longer fail silently into a fake empty state

Base: Build 340 / `1bde422`, `feat/session-revalidate-340`. MARKETING 1.0.2, build 341. Branch `feat/reviews-first-load-341`. Unsigned IPA: `AVDB-unsigned-1.0.2-341-reviews-first-load.ipa` (CI artifact `AVDB-341-release`).

Context: on Build 337 the user opened a movie detail page whose draggable reviews panel header showed the correct count （评论 8) while the list rendered 「暂无评论」; the comments only appeared after tapping the 最热/最新 sort segmented control. The chain, confirmed by code audit: `JavDBSDK.movieReviews` was the only detail-page endpoint still calling `client.get` WITHOUT `useToken` and WITHOUT an `isSuccess` guard — every sibling moved to token + success checks in Builds 327/335 — so an error envelope (`success=0`) silently became an empty list via `resp.data?.reviews ?? []`. `ReviewsListViewModel.fetch` then caught ALL errors and swallowed them: a failed first load left `reviews` empty with nothing recording the failure, and the panel's `reviewsList` renders 「暂无评论」 whenever `reviews.isEmpty && !isLoading`, indistinguishable from genuinely having no comments. The first load fires exactly once (MovieDetailView's `.task`); after that, the ONLY retry path in the whole UI was the sort picker's `onChange` → `load(force: true)` — precisely the user's workaround. Whatever the transient cause of a first-load failure (an auth-era error envelope, a network hiccup), the app converted it into a permanent fake "no comments".

## Changes

1. **`AVDB/Services/JavDBSDK.swift` — `movieReviews`** now calls `client.get(..., useToken: true)` and guards `resp.isSuccess`, throwing `JavDBError.apiError` on an error envelope — the same house pattern as `latestMovies`/`moviePlay`. A successful empty page still returns `[]` (genuinely no comments). The other caller, `MovieDetailViewModel.loadReviews()`, already goes through `try?` and is unaffected.
2. **`ReviewsListViewModel`** gains `@Published private(set) var loadFailed`. A successful fetch — including a successful EMPTY result — clears it; a throwing replace load sets it (loadMore failures only roll the page back, as before, and do not set it). `load()` also gained a plain-load overlap guard (`if !force, isLoading { return }`, mirroring loadMore's style); its retry semantics needed no other change — the existing `!reviews.isEmpty` guard already lets a plain `load()` refetch after a failure, because a failed replace leaves the list empty.
3. **`DraggableReviewsPanel` self-heal:** an `.onChange(of: isContentVisible)` hook retries once — `vm.load(movieID:)` — when the content becomes visible while `vm.reviews.isEmpty && !vm.isLoading && vm.loadFailed`. Expanding the panel repairs a failed first load on its own; a panel whose comments loaded fine never refires.
4. **Honest empty state:** in the panel's `reviewsList`, the empty region now branches on `vm.loadFailed`: failure shows a plain tappable row — 「评论加载失败」 over a semibold 「重试」 — that calls `load(movieID:, force: true)`; only a successful empty load reaches 「暂无评论」, unchanged in style. The standalone `ReviewsListView` page shares the view model and keeps working as before (its failure presentation is out of scope; the flag does not alter it).

## What did NOT change

- The sort picker behaviour (its `onChange` force-reload stays — now redundant, still harmless), pagination/`loadMore` semantics beyond the flag, `ReviewRow`, the panel's drag/snap logic, and the header count.
- `AVDBApp.swift` and all auth/session code — untouched in this build.

## Visible scope for the user

Comments now load on first open of the detail page. If a first load does fail, the panel no longer pretends the movie has no comments: it shows 「评论加载失败 / 重试」, and simply expanding the panel retries the load automatically. A movie that genuinely has no comments still shows 「暂无评论」, exactly as before.

Planned and implemented jointly with Muse and Kai.
