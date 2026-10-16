# Build 186 — bounded Tenhow / exact-ASIN Amazon poster candidates

Base: authenticated GitHub main `07f9f4ef2aad430e0b651f2a7726150e40712b7a`, build 185. Version 1.0.2 / build 186 (both project configurations and Info.plist).

## Production behavior

- Adds explicit Tenhow actor-navigation mapping; no romanization or title search. Original API actor `name`, `other_name`, and optional `keyword` are checked together; conflicting aliases miss. `actor_names` is the fallback when structured actors are absent. Localized `displayName` / `name_zht` is not identity.
- Reads at most two allowlisted actor pages, then matches the requested catalog number to Fanza/DMM CID links inside the **same** Tenhow product record. Unknown manufacturer prefixes, mixed codes, conflicting ASINs, thumbnails and unrelated links miss.
- Uses the record's actual `images/{ASIN}.jpg` enlargement link. Requests at most one `https://www.amazon.co.jp/dp/{ASIN}` page; requires matching main-product ASIN inputs and canonical URL. Reads only `landingImage` actual `data-old-hires` / dynamic image metadata, not recommendation images or guessed size suffixes.
- Keeps existing JavDB/DMM/MGS sources and the existing uncensored/western/FC2 original-art policy. Tenhow/Amazon have two reserved candidate opportunities, not a year/source score bonus. Missing new candidates return their slots to old candidates.
- Six distinct image attempts, two image jobs, a single 12-second monotonic budget including discovery. Discovery is bounded to four seconds inside that same budget. Page/image requests use isolated cookie-free credential-free sessions, HTTPS host/path allowlists and bounded responses; login/captcha/mismatch/errors are normal misses.
- All successful images run through the existing ImageIO native decode / EXIF / usable crop sizing, then the existing deterministic quality policy (1800 raster ceiling and near-resolution original preference). No incremental source publication; one final winner.

## Evidence and tests

- Nine real Tenhow records across three actor pages are replayed by production Swift parser. Actual downloaded originals include CJOD-499 / B0GPVJJLPF 1055×1500; WAAA-697 / B0HHCVVYSW 1032×1468; OFES-035 / B0H3NKNKK6 1055×1500. Prior direct samples MEYD-575 1054×1500, MEYD-388 1055×1500, JUFD-437 1058×1500 are in the research evidence.
- Actual public Amazon main-product metadata subsets are checked in as fixtures (scripts/recommendations removed). Direct CDN image downloads on 2026-10-16: B09HS8HBR7 (release 2021-11-02), `91ktf3uskCL._AC_SL1500_.jpg`, 1054×1500; B0B92LKJT8 (release 2022-09-13), `81N2rlJarrL._AC_SL1500_.jpg`, 1063×1500. Both HTTP 200 and fully decoded with Pillow. These verify real metadata/pixels, **not** a claim that Amazon always beats Tenhow or that 2023–2024 has been sampled.
- `test-tenhow-posters.py`: production Swift mapping/parser, exact CID and ASIN, ambiguous record rejection, HTTPS/redirect/CDN restrictions, main-product-only metadata, captcha misses, reserved candidate fairness, delayed high-resolution winner, six/two limits, shared budget/cancellation, one publication.
- `DetailPosterQualityTests`: real UIKit/ImageIO decode, EXIF/crop/invalid images and original-category exclusion; raw keyword/alias/actor_names identity checks.
- On iSH, existing Python/static regressions pass; Swift, CoreImage and simulator execution are explicitly deferred to macOS CI, not claimed as local runtime passes.
