# Build 329 — Unblurred home floor & 3-column cover grids

Base: Build 328 / `fde4b83f15d927339a283ece40be5310daf920d9`, `feat/home-hot-328`. MARKETING 1.0.2, build 329. Branch `feat/home-hot-329`.

This build was planned jointly with Muse and Kai after the user installed Build 328 and recorded the homepage (the hero titles changed while the image stayed a smear; lower rails flashed the film-icon placeholder and were inconvenient to browse horizontally). Kai’s diagnosis, which this build implements exactly: the two 328 failures are the same mistake — applying **quality rules** to the **floor layer**. 「地板层只管有没有图（有就以最清晰版本原样画出，不设门槛、不加效果）；画质档位只管升级竞速和最终定案。」 The 3-column vertical grid is Kai’s layout (grok-muse’s earlier 2-column lean was withdrawn).

## What changed

1. **Hero floor is always sharp and unfiltered.** `HomeHeroPage` never applies blur or a brightness dim on the main image layer. The floor is the sharpest available list/DTO cover, painted as-is. HQ sharp (A/B) crossfades in with a plain fade ≤ 0.45s when it arrives. Blur is not used on the information layer (it remains allowed only on the post-scrim ambient decorative wash, which has no information role).

2. **6s is a provisional settle, not a cancel.** Hero state `finished` / `retryable` is replaced by 「已定案（可升级）」, keyed by movie id. In-flight sharp loads may continue after the deadline (upgrade timeout 20s) so a CDN that answers at 15s still upgrades the floor. After eviction, unblurred floor bitmaps are kept in a small in-memory cache and sharp covers are restored from `HeroCoverDisk` / `HQPosterDiskCache` so a swipe back is never a smear. Prefetch order is current → +1 → −1 → +2 → −2; decoded sharp bitmaps are kept for current ±1. If a playback DTO has no DMM CID, a lightweight detail fetch + mapping cache fills it for the cap-10 hero list without blocking first floor paint.

3. **Rail floor paints DTO thumbs immediately.** Typical JavDB 147×200 `small_covers` are legal floor images. 360 px is a preference among already-decoded candidates only, never a discard gate (`RailCoverFloor.prefers`). `film.stack` appears only when there is no cover/thumb URL at all; a URL that failed to load is a gray field with tap-to-retry. When home data returns, `HomeRailThumbPreheat` starts the immediate list-thumb loads in section order (往期推薦, 最新上架, 近期磁鏈更新, 我的關注) so a fast scroll to 我的關注 does not flash film icons on cards that have a DTO image. VisibleHQ stays on the 2 (cellular) / 5 (Wi-Fi) scheduler.

4. **Lower rails are 3-column vertical grids.** 往期推薦, 最新上架, 近期磁鏈更新, and 我的關注 reuse `MoviePosterCard` (the `MoviePosterGrid` cell) in a 3×3 grid, capped at 9 posters on the home page. Title-row 「>」 / 更多 opens the existing full list (往期 → `PastRecommendView`; 最新上架 / 近期磁鏈 → `CatalogListView`; 我的關注 → the selected tag’s existing following list). No horizontal cover-rail swipe. Shortcuts stay a horizontal icon row; TOP250 stays the existing banner; the tab bar is unchanged. The home page is not a fullscreen vertical feed and the hero is not merged with the rails.

5. **換一組** stays only on 最新上架 and 近期磁鏈更新, rotating the next batch of 9 (next API page, as 328 already did). 往期推薦 and 我的關注 do not get 換一組.

Unchanged on purpose: 看熱播日榜 hero source (`filterBy=high_score`, `period=daily`, cap 10), the 328 swipe-arbitration table, 「更多」, the light home aligned with the detail sheet, 往期推薦 as a normal section under shortcuts, live CoverSR off, 327 auth behavior, and the 7-tab bar. Out of scope: 7→3 tab merge, live CoverSR, 327 failure-page seed, token refresh, 403-as-auth.

## Tests

- `scripts/test-home-hot329.py` — static source contracts.
- `HomeHot329Tests` — constructed stuck/delayed sources, not only happy-path live data:
  - (i) CDN delayed 15s → sharp unblurred floor at t0, auto-upgrade at 15s
  - (ii) DTO thumb preheat for 我的關注 (no film-icon placeholder policy on cards that have a URL)
  - (iii) offline cold start restores a sharp floor from `HeroCoverDisk`, not a smear
  - 147×200 is paintable as the rail floor; 360 is not a discard; CID mapping from a DTO URL
- `test329HomeHotChrome` — 3×3 cap, 換一組 only on the two sections, 我的關注 更多.
- Wired as CI job `home-hot-329` and into the release regression list the same way 328 was.

## Residual risk

- The IPA is unsigned (`AVDB-unsigned-1.0.2-329-home-hot.ipa`); device install still needs the usual signing/trust step.
- Device QA of the 328 video issues (hero smear, film-icon flash, vertical browsing of the lower covers) is outstanding until this build is installed and checked on a phone.
- `ai-cover-settings-screenshots` has been flaky historically and is unchanged in this build.

`scripts/package-lut329.py` → `AVDB-unsigned-1.0.2-329-home-hot.ipa`; workflow artifacts `AVDB-329-*`; dedicated `home-hot-329` job.
