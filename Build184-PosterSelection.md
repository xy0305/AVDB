# Build 184 — one-shot detail poster quality selection

Version: 1.0.2 (184), iOS 17+, iPhone and iPad. Preserves the uncommitted 183 layout/cache repair rather than discarding it.

## Selection contract

- Warm **winner decision** cache is synchronous: portrait or explicit negative/landscape; unknown is a separate resolving state. Positive TTL 120s, negative TTL 30s, max 24 identities. Account SHA-256 + movie ID/type/code/exact source URLs scope each decision. Coalesced requests have independently cancellable leases; abandoned flights cannot cache a negative or overwrite a newer flight.
- Cold resolution validates/deduplicates at most six source URLs, with two image requests in flight, at most five seconds per image and one monotonic twelve-second collection deadline. Timeout cancels outstanding requests and retains successful completions. Decode and final backdrop processing may add a small non-network scheduling/CPU tail; no promise of a hard real-time UI deadline.
- Sources: current movie's allowed JavDB cover/thumb, plus exact catalog-code-derived DMM `ps.jpg` or MGS `pf_e`/`pf_o1` public paths already evidenced by supplied Pan115.js/jable.js naming rules. MGS zero-padded/unpadded variants are bounded. Small-cover thumbnails are skipped. Arbitrary official metadata URLs are rejected unless equal to a generated candidate. Redirects stay HTTPS and same-host. No page scraping, scripts, CAPTCHA/WAF bypass, account cookies or 115 writes.
- All successful decoded candidates within this bounded search are compared, not just the first eligible image or a cached 376×538 jacket crop. General ImageLoader source caches are not quality evidence and cannot short-circuit selection.
- ImageIO validates complete data and real raw pixel dimensions (max 10,000 on either axis / 40 million pixels / 12 MiB downloaded bytes). EXIF transform occurs before crop/eligibility. Known wrap fronts are cropped first; score never counts the rear cover. Minimum real front is 360×500 with width/height 0.50…0.82. No upscaling.
- Score = `min(frontWidth / 0.7, frontHeight, 1800)` in native oriented pixels. Take the maximum. Prefer an untouched portrait if its score is at least 95% of that maximum; among that subset take the highest score, then untouched over crop, then lexicographic source URL. Rendering caps height at 1800. This is usable resolution, not a claim about compression/detail, image byte size, people count or a globally best poster.
- Uncensored / Western / FC2 and other original-policy titles never use an official substitute or crop. An eligible original JavDB portrait is allowed; otherwise the original landscape detail remains.

## Presentation contract

A keyed, generation-checked state goes `resolving → portrait(winner)` or `resolving → landscape` once. Pending uses the final portrait geometry with a neutral placeholder, never an old landscape hero or speculative source. Real metadata, play, resource, list and review actions remain available. Publication disables animations; repeated/late old-account/movie/generation completions are ignored. Known landscape and warm positive/negative outcomes are direct on first render.

## Tests

Production Swift policy/cache/scheduler regression covers source validation, geometry, account isolation, shared leases, TTL/negative distinction, cancellation, stale movie/generation, one-shot publication and delayed high-quality versus early low-quality candidates under a cancelled timeout.

Simulator-hosted XCTest uses neutral actual JPEGs through production ImageIO decode: 800×538 wrap → 376×538 front; EXIF-6 1000×700 → 700×1000 portrait; 147×200 rejection; HTML rejection; no crop in original policy; 1400×2000 ranking with 1800 render; similar-resolution original preference and deterministic ties; delayed high-later winner, partial-success timeout and cancellation.

Neutral production-detail UI test checks pending has live actions without legacy landscape, stable play-button geometry after one winner publication, immediate warm-cache reentry and known-wide fallback. Existing build-183 navigation/detail tests remain and run on iPad, with detail/catalog/quality tests also on iPhone. Release IPA and simulator tests are required before declaring this release complete.
