# Build 272 — Fast JavDB-native cover clarity (早期封面清晰化)

## Scope (hard)

Only **JavDB native movie covers** on `tp.spfcas.com` / `c0.jdbstatic.com` whose path contains `/covers/` or `/small_covers/`.

**Never enhanced:** DMM, Amazon, JavBus, Tenhow, TPDB, Avbase, MGS, actor portraits / Gfriends / TMDB, or any other host.

## Approach

- System **Core Image** `CISharpenLuminance` (sharpness `0.35`), same filter family as player `NativeLUT` mild sharpen — **no ML / Core ML / Metal custom kernel** for covers.
- Off by default (`UserDefaults` / `@AppStorage` key `javdb.cover.enhance.enabled`).
- Settings → 详情显示 → **「JavDB 早期封面清晰化」** toggle; flipping clears `ImageLoader` + detail poster caches.
- Skip when `max(width, height) ≥ 1200` (already high-res).
- Async off the main path inside existing `ImageLoader` / detail `artwork` utility work; enhanced raster is cached under an `e0`/`e1` tag so toggle is reversible.
- List/grid (`load` / `loadPoster`) and detail winner (`DetailPosterResolver.artwork`) share the same gate.

## Perf notes

- Target: a few tens of ms for a typical ≤800px JavDB jacket on modern iPhone (Core Image GPU); well under ~200ms. No UI freeze — runs in the existing detached utility task before cache publish.
- High-res skip avoids work when HQ DMM/Amazon already won (those sources are also host-rejected).

## Tests / CI

- `scripts/test-javdb-cover-enhance272.py` — static host allow/deny, defaults off, CISharpenLuminance, wiring, Build note.
- Wired into `dmm-preview266.yml` before the IPA build.

No main/win force-push; no new image hosts; no WAF bypass; actor portrait pipeline unchanged (Build 266).
