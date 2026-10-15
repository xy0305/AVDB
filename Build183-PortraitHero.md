# Build 183 — Conditional native portrait hero

Baseline: main 746d8c4 / build 182. Other worktrees, especially feature/javlibrary-174, are untouched.

## Behavior

Only a successfully decoded portrait image enables the new detail header. Source pixels must be at least 360×500 with width/height in 0.50...0.82. The previously proven right-front jacket crop remains limited to known JavDB/MGS wrap sources and 1.35...1.65 jacket geometry. An 800×538 jacket produces 376×538, not fabricated high-resolution pixels. A 147×200 thumbnail cannot enable this layout. No people counting, semantic classification, person removal, image generation, or screenshot image reuse occurs; portrait does not guarantee one person.

The phone layout follows the supplied reference hierarchy: full-bleed upper portrait, lower sampled-color gradient/static preblurred bitmap, large bottom-left multiline white title, real code/date/tags/duration, white rounded play button, download/list/want-watch/watched icons, centered real summary, then horizontal native resource cards. Back/search remain 44pt and clear the status-bar safe area. iPad uses its available scene width and bounded header geometry. Original information, actors, tags, trailer, previews, magnets, relatives, lists and expandable reviews remain below. In portrait mode reviews are below the compatibility sections instead of floating over resource cards; wide/failure mode keeps the original layout.

Buttons use the original Pan115PlayerView, MyListsView and review APIs. Download opens the original resource chooser/MagnetRow rather than writing an offline task on entry. Resource cards do not claim a file, format, bitrate, size, 1080p/720p or external stream that has not actually been resolved. Original native/external magnet logic is unchanged; no bulk push is restored. Review failures are now visible in an alert.

## Reference evidence (static inspection only)

Actual uploaded files were Pan115.js (241967 bytes) and jable.js (95498 bytes), not filenames with appended byte counts. Neither was executed. No credential fields or script bodies are included in this project.

* jable.js loadDetail, lines 1383–1406: GET the supplied detail link, parse `meta[property="og:image"]` / `meta[name="twitter:image"]`, prefer rule-derived poster/backdrop. It also requires a stream in that widget; native AVDB does not inherit that requirement.
* jable.js buildCoverUrlsFromVideoId / parseJavCodeParts, 1582–1621: content-ID numeric prefix table, number padded to five digits, MGS maker mapping.
* jable.js buildMgstageCoverCandidatesFromParts, 1624–1634: `image.mgstage.com/images/{maker}/{prefix}/{parseInt(number)}/pf_e_{prefix}-{number}.jpg`, then `pf_o1_`; `pb_e_` is backdrop, not portrait.
* jable.js buildDmmCoverCandidatesFromParts, 1637–1647: `awsimgsrc.dmm.co.jp/pics_dig/digital/video/{cid}/{cid}ps.jpg`, then `pics.dmm.co.jp/digital/video/{cid}/{cid}ps.jpg`; `pl.jpg` is backdrop.
* Pan115.js readVerifiedCoverForDetail, 1816–1819: prefer the verified `{p,b,s,t}` cover entry, not file thumbnails.
* Pan115.js metadata mapping, 2671–2672: `jacket_thumb_url` and `jacket_full_url` are metadata fields; they are not themselves proof of sufficient pixel dimensions.
* Pan115.js buildDmmCoverCandidatesFromContentId, 5229–5241: same AWS/pics ps/pl paths.
* Pan115.js buildMgstageCoverCandidatesFromParts, 5249–5266: unlike Jable, use `number3`; native candidates include both evidenced integer and three-digit spellings when different.
* Pan115.js dmmhdPosterUrl/dmmhdProbeUrl, 5326–5332 / 5360–5379: AWS poster URL, bounded Range probe and tri-state status. Native code instead validates actual decoded image pixels; it does not treat a 200 HTML/WAF page as a poster.

We add the independently implemented official image naming rules, not the uploaded modules or their auth/encryption/media code. No Jable page search/OG scraping, LibreDMM, r18.dev metadata calls, guessed search results, stream extraction or 115 thumbnail crawl is introduced. Existing JavDB image decryption is reused only for its exact CDN host. Additional sources fail closed to original detail when inaccessible.

## Resource boundaries

Detail-only resolver: reuse decoded front/original cache first, skip known small_covers downloads, at most four actual image downloads, twelve-second total budget, five-second per-request cap, twelve-MiB input cap and 1800px decode cap. Cookie-free ephemeral session, no credential storage, HTTPS exact-host allowlist and same-host-only redirects. No 115 cookie or Authorization header is sent to public image providers.

Memory-only account-hashed identity keys, movie/code/source keys, 24-entry cache, 120-second positive / 30-second negative TTL, concurrent request dedup, independent cancellation leases, cancellation of the last caller's underlying request, and flight UUID guards prevent late overwrites. Detail task guards movie/account identity and cancels on disappearance or account epoch change. Static blur/tint render off-main once, not on each scroll. Existing list rendering and caches remain unchanged apart from a read-only cache accessor.

## Tests

`scripts/test-detail-posters.py` compiles the actual production Swift policy and cache on macOS: complete-code rejection, exact official candidate paths including zero-padding variants, geometry and low-resolution rejection, hostile domains, account isolation, dedup, TTL, negative caching, final-lease cancellation, surviving subscribers, and late-flight protection. Local Alpine runs static safety checks only; it cannot compile UIKit.

The existing simulator workflow runs `testConditionalPortraitHeroRealDetailAndWideFallback` on iPad and iPhone using actual MovieDetailView with self-authored geometric artwork and fictional metadata. It checks title/button geometry, safe reachable back, resource chooser, return, and original wide fallback, and exports native screenshots. Fixtures are DEBUG-only and network/write disabled; fixture artwork/metadata are CC0. No real credentials/media or user screenshot is copied into fixtures.

IPA and simulator CI must finish successfully before claiming delivery. Native simulator screenshots demonstrate geometry, not real-device performance, actual provider availability, or pixel-identical matching with variable content. iOS 17 remains the deployment target. The final IPA must be independently checked for CFBundleVersion 183 and version 1.0.2.
