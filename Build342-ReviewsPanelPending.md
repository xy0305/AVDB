# Build 342 — reviews panel no longer shows a fake empty state before the first load

Base: Build 341 / `b141775`, `feat/reviews-first-load-341`. MARKETING 1.0.2, build 342. Branch `feat/reviews-panel-pending-342`. Unsigned IPA: `AVDB-unsigned-1.0.2-342-reviews-panel-pending.ipa` (CI artifact `AVDB-342-release`).

Context: on Build 341 the user screen-recorded the draggable reviews panel on a detail page whose header read 评论 112: the first expansion rendered 「暂无评论」, and a few seconds later — with no sort tap — reopening the panel showed the reviews. Code audit confirmed a race, not a load failure. The panel's only initial load trigger is MovieDetailView's `.task`, which awaits `reloadDetail()` (plus ingest/autoLaunch steps) before it finally calls `reviewsVM.load(movieID:)`; the panel overlay becomes interactive as soon as `vm.movie != nil`, well before that load starts. Build 341 gave `ReviewsListViewModel` a failure flag (`loadFailed`) but no "pending / never loaded" state, and the panel rendered its empty state whenever `reviews.isEmpty && !isLoading` — so the not-yet-loaded window was indistinguishable from a genuinely empty result, and Build 341's expansion self-heal, keyed on `loadFailed` only, could not rescue it (nothing had failed; nothing had even started).

## Changes

1. **`ReviewsListViewModel`** gains `@Published private(set) var hasLoadedOnce`. `fetch` sets it on any successful fetch, at the same place it clears `loadFailed` (a successful EMPTY result counts — the movie may genuinely have no comments). A failure never sets it. Nothing else in the view model changes: `load`/`loadMore`/`fetch` semantics, sorting and pagination are untouched.
2. **`DraggableReviewsPanel` empty state** is now three mutually exclusive derived states (`showReviewsRetry` / `showReviewsPending` / `showReviewsEmpty`), evaluated only while the list is empty: the Build 341 retry row （评论加载失败 / 重试， force reload) when `loadFailed && !isLoading`; a pending placeholder — `ProgressView` + 「加载中」 in the same vertical footprint — while `!hasLoadedOnce`, which covers "load not started yet", "first load in flight", and "retry in flight after a failure"; and 「暂无评论」 only when `hasLoadedOnce && !loadFailed && !isLoading`, i.e. a successful load genuinely returned empty. The `ForEach` and the loadMore footer are unchanged (a reload in flight after a successful empty load shows just the footer's spinner, as any load does).
3. **Panel expansion self-heal widened:** the `.onChange(of: isContentVisible)` hook from Build 341 now fires when the content becomes visible while the list is empty, not loading, and `(loadFailed || !hasLoadedOnce)` — expanding the panel starts the first load itself if the `.task` chain has not reached it yet, instead of only repairing failures.

## What did NOT change

- `JavDBSDK.swift` (the 341 endpoint fix stands), the sort picker and its `onChange`, `loadMore` semantics, `ReviewRow`, the panel's drag/snap logic and header, the standalone `ReviewsListView`, and all auth/session code (`AVDBApp.swift` untouched).
- MovieDetailView's `.task` chain: the reviews load call stays where it is — the panel-side trigger and the pending state make the ordering non-critical, so the detail load sequence was not restructured.
- The Build 341 contracts: a failed first load still records `loadFailed`, still shows the retry row instead of a fake empty, and still self-heals on expansion.

## Visible scope for the user

Opening a detail page and immediately expanding the 评论 panel now shows 「加载中」 until the comments arrive, instead of a bogus 「暂无评论」. A movie that genuinely has no comments still shows 「暂无评论」 once the load completes, and a failed load still shows 「评论加载失败 / 重试」, exactly as in Build 341.

Planned and implemented jointly with Muse and Kai.
