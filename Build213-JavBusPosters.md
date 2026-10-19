# Build 213 — JavBus main-jacket candidate discovery

## Baseline and scope

Local baseline `3b67b3c6f5e997ef5c162419f1007dd135786127`, build 212, branch `fix/subtitle-position-201`; working tree was clean before this change. No playback, menu, detail UI, Tenhow actor mapping, exact-CID/ASIN rules, DMM or MGStage URL rules are replaced. Version is 1.0.2 (213), minimum iOS 17.

## Public research and licensing

- Public implementation reference: https://github.com/z291173301/MDCx/blob/e037880e0add4433bcf0ab8c926b836ec04801f1/mdcx/crawlers/javbus.py (`getWebNumber`, `getCover`). The public rules identify the catalog number from a header span's sibling, and the main jacket from `a.bigImage.href`, not a small poster or gallery image.
- License checked: https://github.com/z291173301/MDCx/blob/e037880e0add4433bcf0ab8c926b836ec04801f1/LICENSE — GPL-3.0. AVDB contains no copied implementation or GPL fixture. The new Swift parser independently uses AVDB's existing JRHTML tree and freshly observed factual page fields.
- Official public details verified with the ordinary local browser on 2026-10-19: https://www.javbus.com/SSIS-794 and https://www.javbus.com/WAAA-113 . Both yielded the exact visible record identity and a single `a.bigImage` under `.movie`.
- Minimal `scripts/fixtures/javbus-*.html` preserve those factual structural fields, with names, descriptions, scripts and cookies removed; these are not fabricated successful network responses.

## Actual image GET + full decode

| Record | Main href observed in exact detail | HTTP | Bytes | Native oriented raster | Effective right-front |
|---|---|---:|---:|---:|---:|
| SSIS-794 | https://www.javbus.com/pics/cover/9s9e_b.jpg | 200 | 152069 | 800×538 | 376×538 |
| WAAA-113 | https://www.javbus.com/pics/cover/8ihl_b.jpg | 200 | 221277 | 800×538 | 376×538 |

Downloaded via normal browser HTTPS fetch, transferred as bytes for full Pillow decode and EXIF transpose; images are not embedded in this report. No CAPTCHA/WAF solver, TLS override, VPS or personal-cookie export was used. Total local successful image downloads are well below 20 MB, serial (at most two allowed).

Comparison: normal verified HTTPS DMM `awsimgsrc.dmm.co.jp/pics_dig/digital/video/ssis00794/ssis00794ps.jpg` decoded 147×200, 12262 bytes (ineligible). WAAA-113 `waaa00113/waaa00113ps.jpg` decoded 1032×1468, 485992 bytes (wins over JavBus's effective 376×538). JavDB WAAA-113 `https://c0.jdbstatic.com/covers/8q/8QJB9.jpg` was freshly downloaded and decoded 800×538, 231794 bytes (same effective 376×538). The previously captured SSIS-794 JavDB Blu-ray record `/v/MmemxP` had 800×438 artwork: it is an edition comparison only, not proof of identical DVD product identity.

## Important access limitation

Shell's normal GET redirected to the site's Age Verification page. A normal public age form POST (`Submit=確認`) returned the site's public `age=verified` cookie, but the next shell GET still redirected to age verification; this was not counted as detail success. The existing local browser, using its normal session, independently accessed both actual details and downloaded images successfully. No browser cookie is installed in the app or retained in evidence.

Production intentionally remains cookie-free and does not silently submit age acceptance: in age-gated regions its single metadata request fails closed for 30 minutes. The browser success is NOT a claim that the new URLSession path is live-verified universally. A future opt-in first-party age-consent UX or a site change may be required there. No CAPTCHA attempt is made. Only the actually observed first-party `www.javbus.com/pics/cover/*_b.jpg` host/path is admitted; unevidenced photo/CDN domains are excluded rather than guessed.

## Selection and budgets

JavBus only discovers a supplemental candidate; no provider priority or first-success rendering. Existing six image attempts, two concurrent image jobs, 12-second monotonic deadline and all original Tenhow/Amazon reserved opportunities remain. One JavBus metadata request runs in parallel, max 1.2 seconds / 768 KiB, uses no credentials/cookies and rejects any redirect except the identical clean HTTPS URL. It never waits after baseline completion. Its image may use only a slot left after the baseline originals and exact-record Tenhow/Amazon/DMM enrichment; it never displaces them. When all six slots are occupied, no JavBus image is attempted — a deliberate conservative opportunity limitation.

Only complete numbers with exact prefix and digit string match (no substring, padding normalization, URL alias, FC2, inferred CID). A single `.movie` / `.info` identity and single main anchor are required. URL userinfo, port, query, fragment, percent encoding, HTTP, arbitrary hosts and private IPs are rejected. Any age/captcha/WAF markers fail closed. Negative metadata cache is 30 minutes, positive 6 hours, independent of account secrets.

The existing full native decode applies EXIF first, then the existing geometric standard DVD right-front rule (ratio 1.35–1.65, front width floor(height×0.7)). The new validated-jacket flag is used only by detail decode on an allowed JavBus main path; list policies are unchanged. Actual cropped front must meet the unchanged 360×500 / 0.5–0.82 ratio threshold. Portraits can pass untouched; arbitrary landscapes, scene frames and thumbnails cannot. Existing quality winner keeps a much higher-pixel Japanese Amazon/DMM candidate, no enlargement or face crop. Only final winner is published.

## Tests and delivery verification

`test-detail-posters.py` now invokes `test-javbus-posters.py` in the existing build-ipa workflow (no workflow permission change). Independent production Swift parser/selection tests cover two observed fixtures, exact identity and false-prefix/padding/FC2 rejection, href versus thumbnail, duplicate record ambiguity, URL allowlist/private IP/redirect identity, age/WAF rejection, effective crop quality, Japanese Amazon winner, unchanged six attempts and provider reservations, and cancellation/no metadata latency wait. Existing front-poster tests execute actual ImageIO EXIF and neutral right-front pixels; detail cache tests cover cancellation/stale generation/account isolation/negative cache. Local Linux static suites pass; actual Swift and ImageIO execution is performed by macOS CI. Build result, immutable SHAs, artifact hash and IPA checks are recorded separately in delivery evidence. No real-device visual or regional URLSession access test has been performed.
