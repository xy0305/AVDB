# Build 344 — poster grids reserve bottom clearance for the floating tab bar

Base: Build 343 / `de4bb13`, `feat/list-landscape-cover-343`. MARKETING 1.0.2, build 344. Branch `feat/list-tabbar-clearance-344`. Unsigned IPA: `AVDB-unsigned-1.0.2-344-list-tabbar-clearance.ipa` (CI artifact `AVDB-344-release`).

Context: on Build 343 the user screen-recorded the 第610期 recommend-period list and pointed out a problem unrelated to Build 343's cover fix: the last row (KSBJ-416, IPZZ-809) rests underneath the floating tab bar — IPZZ-809 is entirely hidden at rest, and the row only becomes fully visible while the user holds a rubber-band overscroll; releasing snaps it back behind the bar. The floating bar (a ~60 pt pill floating above the home-indicator zone) overlays the bottom ~94 pt of the screen. It is hosted in the tab container's bottom `safeAreaInset`, and the home root page's scroll view receives that inset (its code keeps the bottom safe area on purpose, so its last rail scrolls clear). The grid pages do not: `PeriodMoviesView` and every other page built on `MoviePosterGrid` use a plain `ScrollView` whose content rests at the physical bottom of the screen, and the grid itself reserved no bottom space at all — so whenever a list's total height lands within a row of the viewport, the last row is trapped under the bar. The user approved the shared fix over a period-page-only patch.

## Changes

1. **`MoviePosterGrid` reserves the clearance** (JAVDBUI.swift, the one change): a documented constant `tabBarBottomClearance = 100` pt (bar zone ≈94 pt plus a small margin), applied once as `.padding(.bottom, …)` after the grid's existing horizontal padding. Every page that renders this grid — period lists, list/catalogue pages, actor filmographies, category movie pages, search results, rankings movie grids, library pages — gains the same resting clearance with no per-page edits.

## What did NOT change

- The grid's columns, spacing, cell content, navigation destinations, and the `onAppear` pagination hook; the loading spinners that host pages place after the grid still render after it.
- Build 343's cover rendering (the user asked whether it should be rolled back: no — that was a separate, evidence-verified rendering bug, a landscape cover centre-sliced in the middle of a list; this build's issue is purely the resting position of the last row. The two fixes are independent and stack).
- The home page and its rails (`HomePosterGrid` is a different component and the home scroll view already keeps the bottom safe area), the tab bar itself, detail pages, and all network behaviour.

## Visible scope for the user

In any poster-grid list, scrolling to the end now lets the last row rest fully above the floating tab bar instead of hiding behind it; the period-610 list from the recording is the reported case. Lists gain ~100 pt of extra scrollable range at the very end; nothing else moves.

Planned and implemented jointly with Muse and Kai.
