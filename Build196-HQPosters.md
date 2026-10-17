# Build 196: verified native Amazon primary-image originals

## New behavior (not a new Tenhow/Amazon scraper)
Existing exact-record CID → ASIN → canonical Amazon product → landingImage binding now removes **only** the proven `._AC_SL<2–4 digits>_.jpg` / `._SL<2–4 digits>_.jpg` size rendition. It retains the exact host and image identifier and requests the bare JPEG. Unknown transformations remain unchanged. This is an independently implemented URL convention, not AI generation, sharpening, synthetic enlargement or a Google/title search. The primary-image candidate occupies the same single reserved Amazon slot. If fetching fails, the already competing Tenhow/official/catalog sources provide normal fallback; no extra hidden request is made.

Native effective pixels now decide quality even above 1800, rather than tying there. The **retained rendering raster remains capped at 1800 pixels** to preserve memory behavior; raw metadata dimensions remain in quality scoring. Native portrait preference within 5% is unchanged. Width/height cannot establish a single-person image; a real multi-performer product stays that product's own artwork.

## Public mature implementation research
- MDCx, pinned `58e3f930f2e864fceb8a53ceef818716e2a6413d`, https://github.com/sqzw-x/mdcx/blob/58e3f930f2e864fceb8a53ceef818716e2a6413d/mdcx/base/web.py#L325-L329 explicitly removes Amazon AC image transformations then checks actual image dimensions. We adopt only the URL fact with stricter exact-ASIN primary-image binding, narrower rendition recognition, and native Swift implementation; no external code copied. MDCx's Google discovery is NOT adopted.
- MDCx jacket treatment: https://github.com/sqzw-x/mdcx/blob/58e3f930f2e864fceb8a53ceef818716e2a6413d/mdcx/core/image.py#L89-L149 distinguishes copy/center/right-front crop. Arbitrary landscape/person crops are NOT adopted.
- Amane, pinned `27825d1bb642f9eb6c46f4635d5e7f52752a4ee4`, https://github.com/sqzw-x/amane/blob/27825d1bb642f9eb6c46f4635d5e7f52752a4ee4/src/amane/media/images.py implements right-side `height × 0.7` derived DVD fronts and candidate-size checks. GPL source inspected as conceptual reference only; no copying, no super-resolution adopted.
- mdc-ng https://github.com/mdc-ng/mdc-ng/tree/8d73d513397427187aa61361d4b9b2b14be9c6cb publishes README/public assets, not a verifiable scraper implementation at that tree. Its feature descriptions are not evidence of a working new HD source and no hidden implementation is claimed.

## Actual complete GET + JPEG decode, normal TLS, no credentials
`hq-amazon-evidence.json` retains text-only URLs, dimensions and hashes; no adult image files committed.

| Complete number / same-record ASIN | Tenhow independent front | Previous Amazon front | Bare original / effective front |
|---|---:|---:|---:|
| WAAA-113 / B09HS8HBR7 |1054×1500|1054×1500|1778×2530 (no crop)|
| MLMM-014 / B0B92LKJT8 |1063×1500|1063×1500|1778×2529 (no crop)|

WAAA-113 original: https://m.media-amazon.com/images/I/91ktf3uskCL.jpg ; previous: https://m.media-amazon.com/images/I/91ktf3uskCL._AC_SL1500_.jpg
MLMM-014 original: https://m.media-amazon.com/images/I/81N2rlJarrL.jpg ; previous: https://m.media-amazon.com/images/I/81N2rlJarrL._AC_SL1500_.jpg
Both originate in https://www.tenhow.net/hasumi_kurea.html exact CID retail/digital links; Amazon fixtures contain matching canonical/ASIN/landingImage, not recommendations. Full GETs showed genuine original pixels (about 1.69× image height, 2.8× pixel area), not inference from an SL2560 label or byte count. No claim that either image has exactly one person: WAAA-113 is a multi-performer example and must never be substituted with an unrelated single-actor picture.

## Sources deliberately not newly added
DMM digital ps/pl complete GETs: SSIS-001, SSNI-001 and SSIS-497: 147×200 ps; 800×538 pl, only **376×538** effective front. STARS-001: 147×200 vs 800×535, only 374×535 front. URE-013: 800×499 wrap would yield 349×499 and fails the unchanged eligibility threshold. ABF-295 AWS retail pl is 2184×1477, but its existing native ps is already 1032×1477, approximately the same usable resolution; adding pl would not improve it and would spend a fair candidate slot. None are misreported as new 2184-pixel-wide front portraits. Text-only DMM evidence is `hq-evidence.json`.
R18 thumbnail-only patch is NOT merged: no measured native-HD benefit. No new Javbus/Javlibrary image source; no WAF/captcha/region bypass.

## Safety and tests
Exact complete number including numeric series prefix remains mandatory; no weakening of 13DSVR → 3DSVR or edition rejection. Main-image URL is admitted only after original same-record ASIN and Amazon canonical/ASIN checks. Same-host/path redirect guard, HTTPS CA verification, no 115 cookie/auth, 8MB image ceiling, six-image/two-job/12s budget, cancellation, generation and single-winner publication/cache remain untouched. Uncensored/Western/FC2 original policy unchanged.
Tests add original rendition/ID checks, malformed/foreign/query URLs, unknown-rendition preservation, real ASIN fixture expectations and 2530-vs-1800 winner selection. iOS image tests retain native 1778×2530 metadata while verifying cached raster height stays 1800. Local Linux runs are static checks only; runtime Swift and UIKit are assessed by macOS/iOS CI, not claimed from Linux.
