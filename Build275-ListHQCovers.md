# Build 275 — List / small covers: HQ first, JavDB fallback

Base tip includes Build 274 糖心 trailing-slash. Version stays 1.0.2 / project build 266 (preview artifact naming unchanged).

## Answer: are list small covers already HQ?

**No (before this build).** Home / grid `MoviePosterImage` used only JavDB metadata:

| Field | Typical CDN path | Observed size |
|---|---|---|
| `thumb_url` | `…/small_covers/…` | ~147×200 |
| `cover_url` | `…/covers/…` | ~800×538 DVD wrap → right-front crop ~376×538 |

Detail screens already resolve Amazon `MAIN._SCRM_` / DMM / Tenhow / MGS via `DetailPosterResolver`. List grids did not use those winners.

## Change

1. **`ListCoverPolicy.sources(movie:)`** — for censored catalogue rows, order is:
   - warm tip from `ListHQCoverCache` (Amazon / DMM / MGS / Tenhow URL learned after a detail win)
   - catalogue-bound public images already on the movie
   - one guessed `DetailPosterPolicy` portrait (DMM `ps` / MGS `pf_e`)
   - then existing JavDB `FrontPosterPolicy.sources` (cover → thumb / thumb → cover)
2. **`MoviePosterImage`** passes up to three candidates (`url` / `fallback` / `secondFallback`). Uncensored / Western / FC2 / HEYZO stay original-only (no guessed HQ).
3. **`ListHQCoverCache`** — memory-only number→HQ URL; detail store on winner; list reads sync (no Tenhow scrape per cell).
4. **`ImageLoader.isExternalCover`** also treats `awsimgsrc.dmm.co.jp` so NOW 147×200 placeholders fail fast and fall back to JavDB.

## Speed / safety

- No per-row Tenhow/Amazon discovery on scroll.
- At most one guessed public portrait attempt before JavDB.
- Existing ImageLoader cache / posterCache / request coalescing unchanged.
- Detail layout, badges, gestures, and JavDB enhance toggle untouched.

## Tests

- `scripts/test-list-hq-covers275.py`
- `scripts/test-front-posters.py` (contracts updated)
