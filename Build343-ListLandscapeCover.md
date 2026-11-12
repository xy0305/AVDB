# Build 343 — uncropped landscape covers in list cells are shown whole, not centre-sliced

Base: Build 342 / `bb87a28`, `feat/reviews-panel-pending-342`. MARKETING 1.0.2, build 343. Branch `feat/list-landscape-cover-343`. Unsigned IPA: `AVDB-unsigned-1.0.2-343-list-landscape-cover.ipa` (CI artifact `AVDB-343-release`).

Context: on Build 342 the user screen-recorded the 第603期 (2026-10-15) recommend-period list: one cover — HEYZO-2706 — rendered as a washed-out, magnified pale slice with neither the title nor the actress visible. Audit, verified against the live API payload and the actual image bytes: JavDB serves this title's cover as an 800×450 landscape promo (ratio 1.78, not a DVD jacket), and the recommend payload carries only `cover_url` — no portrait thumb. In the list pipeline, `FrontPosterPolicy.isKnownWrap` treats any JavDB-CDN `/covers/` URL as a jacket wrap, so `ListCoverPolicy` leads with the cover and enables front-poster cropping; but `PosterColorCrop`/`FrontPosterPolicy.cropRect` only crop jacket ratios 1.35…1.65, so this image passes through uncropped. `JavDBImage`'s candidate loop then finds no portrait candidate and publishes the landscape through its `landscapeFallback` path, where `MoviePosterImage`'s `.fill` content mode scales it to the portrait cell's height and shows only the centre ~41 % of its width — for this promo, the pale middle band. Simulating that exact centre crop reproduces the recording frame-for-frame. The same failure hits any original-type title (HEYZO systematically; other uncensored/FC2 titles case by case) whose only list artwork is a non-jacket landscape image, in any grid fed by `MoviePosterImage`. Detail pages are unaffected (wide hero presentation, separate resolver).

## Changes

1. **`JavDBImage` gains an opt-in `fitUncroppedLandscape` flag (default `false`)** and renders its image through a derived `displayedContentMode`: when the flag is on and the published image is landscape (`width > height`), the image renders `.fit` — the whole cover visible, letterboxed — otherwise the caller's `contentMode` is used verbatim. No loading, caching, candidate-selection or cropping behaviour changes.
2. **`MoviePosterImage` — the one shared list poster cell — opts in** (`fitUncroppedLandscape: true` appended to its existing `JavDBImage` call; every other argument byte-identical). The pre-existing portrait preference is untouched: whenever any candidate decodes as a portrait (a 147×200 thumb, a cropped jacket front), that is what the cell shows, exactly as before. The flag only governs the case where the landscape fallback is all there is.

## What did NOT change

- `FrontPosterPolicy` / `ListCoverPolicy` source ordering, the `isKnownWrap` definition, and the jacket crop band (1.35…1.65) and front ratio — genuine DVD jackets, censored or not, crop and fill exactly as before.
- The candidate loop in `JavDBImage`, `loadPoster` / `PosterColorCrop`, the HQ upgrade overlay (`VisibleHQPosterUpgrade` — its original-type candidates are catalogue portraits), the hero (`HeroCoverResolver`) and detail (`DetailPosterResolver`) pipelines, and every other `JavDBImage` caller (the flag defaults off).
- No network behaviour changes: no new requests, no new hosts; the same bytes are fetched and merely framed differently.

## Visible scope for the user

In grid lists (period lists, search, categories, home rails), a title whose only cover is a landscape promo — HEYZO-2706 in 第603期 is the reported case — now shows the complete cover with letterbox bands instead of an unreadable magnified slice. Titles with a portrait thumb or a real jacket look exactly as before, and detail pages are unchanged.

Planned and implemented jointly with Muse and Kai.
