# Build 330 — Home chrome, hero tap, official portrait, liquid-glass shortcuts

Base: Build 329 / `6a5e09301ebbd50e03b599fe91956aaac84efe56`, `feat/home-hot-329`. MARKETING 1.0.2, build 330. Branch `feat/home-chrome-330`.

This build was planned jointly with Muse and Kai after the user installed Build 329 and asked to shrink the top-right search button, make the home hero tappable into detail, use the same official high-res single-person poster as the iPhone detail page (fast first paint, then sharp), and restyle 稍後再看 / 新作提醒 / 三連挑戰 (and the rest of the shortcut row) from flat solid color to liquid glass.

## Smoking guns carried from 329

1. **Search button was 58 pt** — a large dark-glass circle (`homeGlass`) floating top-right, bigger than the user wanted.
2. **Shortcut row was solid color** — all 12 `quickAction` circles used `Color(.secondarySystemBackground)` despite a comment that promised frosted glass.
3. **Hero taps often never opened detail** — `HeroSwipeOverlay` is a hit-testable clear `UIView` on top of the SwiftUI `Button`, so taps frequently never reached `onOpen`. `onTouch(true)` (pan `.began`) also set `lastDragAt = Date()`, and the button required `timeIntervalSince(lastDragAt) > 0.35`, which swallowed a normal tap.
4. **Hero image and the iPhone detail page used divergent sources** — detail uses `portraitHero` from `DetailPosterResolver` / `FrontPosterPolicy` / `DetailPosterQuality` (typical official winner: DMM awsimgsrc digital `ps`, e.g. 745×1081). Home raced its own sharp-source list (including `pl` / jacket). `hdBackdropURL` / `pl` is the 1600-wide full jacket, not the 单人大图, and must not be the primary for this tall home hero. `DetailPosterResolver.resolve` already wrote accepted winners to `HeroCoverDisk`, but that only helped titles already opened on the detail page. `enrichHeroCIDs` learned CID only and did not merge cover / actors or run the resolver, so 看热播日榜 titles often never got the official portrait.

## Locked plan (implemented exactly)

1. **Search button (`HomeSearchButton`).** Visible circle 58 → 44 pt; hit area 44 pt (not below 44). Icon ~16 pt semibold, white. Chrome switched from dark `homeGlass` to existing `liquidGlassCircle`. Still floats top-right below the status bar and opens SearchView. If readability fails on the brightest daily-ranking poster, fall back the *material only* to `homeGlass`, not the size.

2. **Hero tap (hit-testing only; `HeroSwipePolicy` axis lock / paging unchanged).** Overlay tap is the sole navigation entry: `onOpen(current)` only when translation < 10 pt, duration < 0.3 s, and the pan did not consume a page change. `lastDragAt` is set only on page-commit (horizontal or vertical), then used to suppress a trailing touch for 0.35 s. It is not set on pan `.began` or mere touch-down. The underlying SwiftUI Button is hit-disabled and kept for VoiceOver (label/hint 「打開詳情」, `.isButton`, adjustable swipe). 「看熱播 · 日榜」 and 「更多」 keep their own hit targets above the overlay; taps there must not also open detail. One clean tap pushes the current movie’s detail once; swipe still wins over tap.

3. **Hero image = the same official portrait as the iPhone detail page.** Three-step floor with cross-fades (≤ 0.45 s, same 329 fade rhythm): ranking DTO image → enrich-merged detail `cover_url` (real cover, not `small_covers`) → `DetailPosterResolver` winner (raw official artwork, no `AICover` on the home hero). Build 329’s unblurred DTO floor stays; first paint is never blocked on enrich or poster resolve. The old home sharp-source list / hero-only DMM ps/pl race is no longer the authoritative sharp target. The independent queue is a resolver scheduler: (1) `HeroCoverDisk` or the DetailPosterResolver cache is used immediately as the sharp layer when present; (2) enrich merges cover / actors / CID into the hero movie before the resolver starts; (3) `DetailPosterResolver` runs and reuses its cache, coalescing in-flight work with the detail page *by movie id*; (4) scheduler order is current → +1 → −1 → +2 → −2, concurrency cap 2. The 6 s mark is a provisional floor-display rhythm point, not a cancel line; late resolver winners may still upgrade. State stays 「已定案（可升级）」 keyed by movie id. After eviction, sharp is restored from `HeroCoverDisk` / resolver cache. Decoded bitmaps for current ±1 stay as in 329.

   Unchanged on purpose: hero swipe, hero height, 3-column grids, 換一組, tab bar, and playback source (`playbackRankings` filterBy `high_score`, period `daily`, cap 10).

4. **Shortcut row (all 12).** Restyled with existing `liquidGlassCircle(interactive: true)` — neutral untinted glass + `.primary` icons. The iPhone row is wrapped in `LiquidGlassContainer`; iPad is not (GlassEffectContainer on iPad ate taps). Icon, caption, circle / item sizes, and horizontal scroll are unchanged. No new glass recipe; no dark `homeGlass` on the light rails; no solid-color fallback. If light/dark readability on the white section fails, the pre-authorized fix is a very light warm-gray via the existing `tint` parameter. Reduce Transparency keeps the existing modifier fallback.

Out of scope (not done): tab merge, live CoverSR, 327 failure-page seed, token refresh, 403-as-auth, sending CI to Kai, changing the tab bar, fullscreen vertical feed, changing the 3-column grids or 換一組.

## Tests

- `scripts/test-home-chrome330.py` — static source contracts for the locked rules.
- `HomeChrome330Tests` — constructed sources:
  - (a) a clean tap opens detail and a swipe / page-commit does not
  - (b) DTO floor paints immediately even if the resolver is delayed 15 s, then upgrades to the resolver winner
  - (c) a `HeroCoverDisk` / resolver-cache hit is used immediately
  - (d) an enrich-merged detail cover can appear as the middle step
  - (e) backdrop / `pl` is not chosen as the primary sharp over the official portrait winner
- Wired as CI job `home-chrome-330` (macos-26, same family as `home-hot-329`) and into the release regression list. Existing 328 / 329 jobs are kept.

## Residual risk

- The IPA is unsigned (`AVDB-unsigned-1.0.2-330-home-chrome.ipa`); device install still needs the usual signing/trust step.
- Device QA is outstanding until this build is installed and checked on a phone: search readability on the brightest daily-ranking posters, hero tap vs swipe (and that 看熱播 / 更多 do not also open detail), that the hero poster matches the iPhone detail-page official portrait, and shortcut glass readability / scrolling / taps on the light section.
- `ai-cover-settings-screenshots` has been flaky historically and is unchanged in this build.

`scripts/package-lut330.py` → `AVDB-unsigned-1.0.2-330-home-chrome.ipa`; workflow artifacts `AVDB-330-*` (release artifact `AVDB-330-release`); dedicated `home-chrome-330` job.
