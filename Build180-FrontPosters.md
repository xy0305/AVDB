# Build 180 — list front posters

Based on main `7cd47a3` (build 179); previous feature worktrees are untouched.

## Reference verified

Amane commit `e2148c0f8880fff53e7983424ae0366e64902491`:
- `src/amane/media/images.py::should_crop_poster`: compare candidate poster height against thumb height; default skip threshold 0.9.
- `crop_poster`: take the right-hand rectangle, width `floor(height * 0.7)`, retaining full height; already-narrow images stay whole.
- `src/amane/media/pipeline.py::materialize_images`: use existing poster candidates, derive a cached poster from thumb when absent/too small; derived resources do not overwrite the source.
- `src/amane/crawlers/sites/javdb.py`: web video-cover supplies `thumb_urls`, not an invented portrait API.
- License is GPL-3.0. AVDB's short Swift geometry and source-selection policy is independently implemented; no Amane source copied or bundled.

No face detector is used by this automatic Amane crop path. Optional upscaling elsewhere is not ported. This is not AI single-person extraction.

## Actual AVDB metadata

The existing production-search fixture has `thumb_url` in `small_covers` and `cover_url` in `covers`. Read-only CDN dimension verification for that same entry returned 147x200 (portrait) versus 800x538 (DVD wrap). Only dimensions were printed; no artwork was added to the repository. The model has no `poster_url` field. Never assume the small thumbnail is a high-resolution portrait.

## Implementation

`MoviePosterImage` centralizes list rendering. Known JAVDB cover paths prefer high-resolution cover, and standard DVD aspect ratios 1.35–1.65 produce a right-front portrait 0.7 times the height. Other sources prefer provided thumbnail metadata; portrait images remain intact. Unknown/nonstandard horizontal images are not automatically sliced: try available portrait fallback, otherwise fit the full image. Known-source ratio is a conservative heuristic, not semantic proof of a DVD jacket; nonstandard sources may remain landscape.

EXIF orientation is applied by existing ImageIO downsampling first. JavDB XOR decoding is retained. Derivatives are processed off the main thread, request-coalesced and cached separately with 180-item/48-MiB limits; original cache and metadata are unchanged. No per-item movie-detail requests, source scraping or guessed third-party portrait URLs.

Applies to shared grid (home latest, rankings, category, search, actor works, watch later), legacy movie cards/related works, home book flip, top-250 left poster, daily/triple draw and draw history. Landscape home banners, detail original cover, preview galleries and ranking preview carousel remain unchanged. No layout, filter, navigation, badge, button or gesture redesign.

A front cover may itself contain multiple people. This implementation cannot promise one person in every poster and does not generate images, remove people or edit censorship.

## Verification

`scripts/test-front-posters.py` extracts the actual Swift policy and production ImageIO downsample into a macOS runtime test, using only neutral red/green fixtures. It checks source order, duplicate/empty handling, trusted host matching, actual right-front crop pixels, portrait/square/wide guards, untouched originals, EXIF rotation and invalid data. CI runs this before the Release build. Existing iPad navigation suite remains enabled on the changed shared grid.

No real 115 writes are performed. Device visual quality remains subject to real-device review; CI and simulator checks are not claims of iPhone/iPad on-device validation.
