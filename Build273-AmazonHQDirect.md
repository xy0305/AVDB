# Build 273 — Amazon HQ via exact-ASIN MAIN._SCRM_ CDN

Base tip includes Build 272 JavDB cover enhance. Version stays 1.0.2 / project build 266 (preview artifact naming unchanged).

## Behavior vs prior Tenhow→Amazon path (Build 186 / 196)

- **Before:** Tenhow exact record → `images/{ASIN}.jpg` → at most one `amazon.co.jp/dp/{ASIN}` HTML fetch → `landingImage` `data-old-hires` / dynamic metadata → strip `._AC_SL####_` / `._SL####_` → bare `/images/I/{id}.jpg`. Captcha / 503 / 1.5s timeout = Amazon miss; Tenhow/DMM remain.
- **Now:** Same exact-record ASIN identity, then the Amazon candidate is the public CDN URL  
  `https://m.media-amazon.com/images/P/{ASIN}.01.MAIN._SCRM_.jpg`  
  (calibre Kindle hi-res / bookfere / Cover-Downloader-for-Amazon convention). Product-page HTML fetch is removed from the resolver hot path (captcha/503 prone). `AmazonPoster.images` / fixtures remain for offline SL-strip regression.
- Still **no** title/keyword/Google/ASIN search, no login, no PA-API, no guessed SL upscale of foreign images. Uncensored/Western/FC2 original policy unchanged. Six attempts / two jobs / 12s budget and two Tenhow+Amazon reserved opportunities unchanged.

## Public research (URL facts only; no code copied)

- Amazon PAAPI image docs: `/images/P/{ASIN}.{country}._SL{N}_.jpg`; JP country `09`.
- calibre-amazon-hires-covers: `images/P/{ASIN}.01.MAIN._SCRM_.jpg`.
- bookfere / Greasy Fork Cover Downloader: same MAIN._SCRM_ form.
- MDCx `58e3f930` strips Amazon AC renditions after a real URL is known; Google discovery is **not** adopted (Build 196 stance retained).

## Measured complete GET (normal TLS, no credentials)

| Number / ASIN | SCRM URL | Pixels | sha256 (matches Build196 original I/) |
|---|---|---:|---|
| WAAA-113 / B09HS8HBR7 | `…/P/B09HS8HBR7.01.MAIN._SCRM_.jpg` | 1778×2530 | `2f82486b…c0f827` |
| MLMM-014 / B0B92LKJT8 | `…/P/B0B92LKJT8.01.MAIN._SCRM_.jpg` | 1778×2529 | `53729fef…c937104ab` |

Text-only evidence: `scripts/hq-amazon-evidence.json` (`direct_scrm`). Adult image bytes are not committed.

## Limits

- Requires a Tenhow same-record ASIN (actor page + exact CID). No ASIN ⇒ no Amazon candidate (unchanged).
- Some ASINs may lack MAIN._SCRM_ (placeholder/tiny); eligibility 360×500 still rejects them; other sources compete normally.
- Does not claim every early JavDB cover has an Amazon counterpart.

## Tests

- `AmazonPoster.directHQ` / `/images/P/…MAIN._SCRM_` allowlist admit/reject in `scripts/test-tenhow-posters.py`.
- Resolver must emit `directHQ` / `MAIN._SCRM_` in discover path (static guard).
- Existing HTML fixture + originalImage SL-strip tests retained.
