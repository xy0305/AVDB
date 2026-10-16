# Build 187 — exact DMM retail covers

## Scope
- `TenhowPoster.LinkedCID` retains retail/digital storefront. Anchored CID rules recognize the documented retail examples `118abf295`, `1sods098`, `d2gvh891`, `h_1059godr1287`; `13dsvr01968` retains **13DSVR** only on the digital storefront. Unknown suffixes/unsupported maker combinations fail closed. Actor navigation, alias matching and exact record ASIN binding remain unchanged.
- After a whole record's identities agree, add only one exact retail (otherwise digital) CID pair. Retail standard uses `/mono/movie/adult/{cid}/{cid}ps.jpg`; AWS uses `/pics_dig/mono/movie/{cid}/{cid}ps.jpg`. Official metadata permits adult/japanese category removal only on these exact known paths. Directory and filename CIDs must agree with the movie before transformations.
- Exact official metadata can change pl to ps and remove numeric `w/h/width/height` transforms and a fragment. Unknown queries, encoded paths, credentials, non-exact hosts, amateur images and jp-N stills fail closed. This does not normalize Amazon URLs.
- Selection remains six image attempts, two concurrent image jobs, twelve-second total deadline, actual decoded portrait pixel scoring and one final publication. During discovery only two legacy jobs start; Tenhow and exact-ASIN Amazon are inserted before up to two DMM entries, replacing only unissued legacy candidates. No source resolution bonus and no assumption AWS is clearer. Both CDN candidates are retained for 404/failure fallback.
- Same-path redirect guard still rejects `/now_printing/`; ImageIO/geometry reject HTML and 147x200 thumbnails. No speculative visual detector or unverified 200-placeholder hash.

## Non-scope
No disk pipeline, AI upscale, solver, player/ranking/UI rewrite, added HEAD request or universal Referer. Original uncensored/western/FC2 policy, account cache namespaces, cancellation, memory cache and unified artwork remain. Existing limited maker rules are not broadened generically. Numeric-prefix support is only 13DSVR inside this poster identity parser, not a cross-app catalog rewrite. Unsupported editions remain uncovered rather than guessed.

## Provenance / license boundary
Behavioral research: Amane v0.21.0, public fix #424, commit `7468d8e201fbd2a633435c5e13432da1d017373f`:
- https://github.com/sqzw-x/amane/blob/v0.21.0/src/amane/crawlers/sites/dmm_cdn.py
- https://github.com/sqzw-x/amane/blob/v0.21.0/src/amane/crawlers/sites/dmm.py
- https://github.com/sqzw-x/amane/blob/v0.21.0/tests/crawlers/test_dmm.py

Amane is GPL-3.0. No source code, dependency or line-by-line translation was imported. Native Swift uses AVDB's existing HTML parser, URLComponents, scheduler and ImageIO. Only public site URL facts and observable expected behavior informed this independent implementation; narrower transform/identity admission is deliberate.

## Verification
Run `python3 scripts/test-dmm-posters.py`, `test-detail-posters.py`, `test-tenhow-posters.py`, `test-front-posters.py`. Linux reports static checks only when Swift is unavailable. The IPA workflow runs actual production Swift parsers and scheduler on macOS before Release compilation; native simulator tests additionally exercise decoder rejection and metadata/original-policy isolation. Synthetic scheduler inputs are controlled regression cases, not real-site success evidence. No live CDN success or true 200-placeholder hash is asserted without a verified sample.

## Click-to-detail latency scope
Diagnosis: the destination previously received only `movieID`; `vm.movie` stayed nil until `movieDetailFull` completed, so neither winner-cache snapshot nor the poster `.task` could start before unrelated full metadata. The image resolver already ran legacy downloads and Tenhow discovery concurrently; it was not serially waiting four seconds before all images.

The generic grids and Home banner now pass their clicked Movie. Only a matching id, explicit censored type, strict complete number, existing actor identities and eligible sources admit this seed. It seeds the detail immediately and supplies a stable poster identity throughout that visit; full metadata/reviews still load independently and cannot cancel/restart the already valid image selection. Incomplete records and other categories keep the metadata-first path. No list prefetch, extra network stage, low-resolution interim publication or ImageLoader thumbnail-quality promotion was introduced. Hot winner snapshots are synchronous on first body evaluation; cold image discovery/download still waits for all legal candidates (or the unchanged global deadline) before the one final winner. `test-poster-latency.py` records controlled production phase timings/overlap and proves early completion and zero warm-cache operation. Its timings are not a claimed live-network speed percentage.
