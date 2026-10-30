# Build 282: getting DMM HQ covers reliably

The report: the MILK-311 detail page showed **封面来源：JavDB**. Build 282 replaces the hand-written DMM CID guessing with a learned resolver and switches DMM fetches to awsimgsrc's full-resolution images.

## Diagnosis (MILK-311)

1. **CID guess:** the static rule had no prefix for MILK, so it guessed `milk00311`. The real FANZA CID is `h_1240milk00311`, which gives a 404.
2. **Admission:** `TenhowPoster.cid` only admitted known namespaces, so `h_1240` was rejected even when a source supplied it.
3. **avbase record:** avbase did return the right CID, but only as pics.dmm.co.jp URLs:
   - ps is 147×200, which is too small.
   - pl is 800×541, a wrap that was not a "known wrap", so it was never cropped.
   - As a result, the JavDB crop (~378×541) won.
4. **Not the cause:** negative caching was already short (300 s / 30 s).
5. **DMM search** needs the `age_check_done` cookie. The project does not auto-confirm age gates, so search is **not used**.
6. **JavDB detail pages** contain no DMM links.

## Measured DMM facts

| Source | Result |
|---|---|
| `awsimgsrc.dmm.co.jp/pics_dig/digital/video/{cid}/{cid}ps.jpg` | Full portrait front, e.g. 745×1081, no watermark |
| `…/{cid}pl.jpg` | 1600×1081 jacket. The front is the right 0.69·h (x = 855, 745 wide) |
| `awsimgsrc …/pics_dig/mono/movie/{cid}/…` | The mono (DVD) CID, same images |
| `awsimgsrc …/digital/amateur/{cid}/{cid}jp.jpg` | Square 900–2184 px (counted as HQ, but not a portrait) |
| `pics.dmm.co.jp` ps / pl | 147×200 / 800×541 |
| Missing item | awsimgsrc returns 404 with a 2,732-byte body. pics redirects to `pics.dmm.com/mono/noimage/now_printing.jpg` |

## Resolver (`AVDB/Services/DMMCoverResolver.swift`, `DMMLabelSeed.swift`)

CID strategies, in order:

1. Exact learned mapping (number → CID, persisted in UserDefaults, cap 2000).
2. An avbase record. Its `digitalCID` and DMM image paths are learned, and the record is upgraded to the awsimgsrc ps/pl pair.
3. Learned label→prefix table (persisted, cap 3000), seeded with 82 rules taken from a 510-title sample, e.g. `milk → h_1240, 5`.
4. 5-digit and 3-digit zero-pad variants.

Other parts:

- **URL patterns:** awsimgsrc digital ps/pl, mono, amateur jp, and the legacy pics URL. `upgrade()` maps any pics or awsimgsrc DMM URL to the awsimgsrc pair.
- **Validation:** the placeholder check catches now_printing / noimage URLs, the 2,732-byte body, 147×200, a 590×800 pl, and any portrait pl. Jackets (pl ≥ 760 wide, ratio 1.35–1.65) are cropped with the 0.69 front ratio. A portrait ps must be ≥ 360×500 with ratio 0.5–0.82.
- **Fetching:** iPhone UA, concurrency 2, one retry with 0.35·2ⁿ s backoff on 5xx, 429 or transport errors, all inside the detail time budget. A 404 is final, and the negative TTL is ≤ 300 s.
- **Wiring:**
  - Detail candidates (`DetailPosterPolicy`), list cards and history (`ListCoverPolicy`), and `CoverURLBuilder` all go through the resolver.
  - `TenhowPoster.cid` admits learned or seeded prefixes.
  - `DetailPosterResolver` rejects DMM placeholders.
  - An original DMM portrait beats any crop, so provenance reads **封面来源：DMM**.

## Hit rate

The sample: 510 titles from JavDB censored list pages, rankings and home, plus h_ / older / amateur labels. FC2 is excluded.

| Rule | DMM HQ |
|---|---|
| Before (static rule) | 322 / 510 = **63.1%** |
| After: table + learned avbase CIDs + awsimgsrc | 481 / 510 = **94.3%** (414 via the ps portrait) |
| After, counting amateur square jp HQ | 489 / 510 = **95.9%** |
| Seed table alone (no network CID source) | 412 / 510 = 80.8% |

The 21 remaining misses are MGS-only or not on DMM (GANA, LUXU, SIRO, SAN, etc.). Those keep the MGS / Tenhow / JavDB paths.

## MILK-311

- **Before:** JavDB crop.
- **After:** `https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/h_1240milk00311/h_1240milk00311ps.jpg` gives 745×1081. The seed table alone resolves it, and avbase confirms it. The detail page shows 封面来源：DMM.

## Tests

`scripts/test-dmm-covers282.py` compiles the resolver together with the production `DetailPosterPolicy` and `TenhowPoster` and checks:

- CID resolution, persistence and caps
- URL patterns, admission and upgrades
- placeholder, jacket and portrait classification
- the front crop and the retry policy
- the MILK-311 winner and its provenance
- source-wiring asserts

A live MILK-311 probe also runs; it is informative only, and `DMM_LIVE_STRICT=1` makes it fatal.
