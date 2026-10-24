# Build 252 — actor portrait delivery

Baseline verified: fix/subtitle-position-201 fafaeaeb8c66cdfc5fe846b998c2046ad5ad7d94. Version remains 1.0.2, minimum iOS 17; build is 252 in Info and both project configurations.

## Confirmed 251 causes

Native production API search for either 池田萬裡奈 or 池田マリナ returns the same actor zKPv4, empty avatar_url/cover_url, and the first six existing works DAZD-315, DSOD-010, DSOD-022, DSOD-006, DSOD-070, DASS-999. Search videos_count is 48, not necessarily the detail count shown in the screenshot; the diagnostic now also measures detail fields. This disproves a non-empty invalid existing URL as this actor's primary cause (but that separate defect is repaired).

251's bundled alias map contains only 池田マリナ, not 池田萬裡奈; exact-name matching therefore could not match the public page. The verified alias is added as data, not an actor ID/URL special case. 251 retained only two works, while the independently verified page DSOD-070 is fifth. Detail already restarts its task when the explicit works array changes; the actual gap was the window and registry-only cards receiving no update signal.

Native no-cookie URLSession measures DSOD-070, DAZD-315, DSOD-010, DSOD-022 all returning 302 to /doc/driver-verify?referer=... . The portrait URL previously visible in a browser returns 403 text/html natively. These are a verification gate, NOT a normal canonical redirect. Neither this release nor its tests follow the gate, send cookies, solve challenges or bypass WAF. Browser success does not prove app transport success.

## Delivery and bounds

- First actually decode existing AVDB artwork using the established ImageLoader; a completed failed load enables fallback, cancellation does not. Valid originals win. TMDB's default existing guard stays intact; only an explicit failed-existing path may proceed.
- JavBus parser stays exact-number/name/star-context based. Known already-loaded works expand to six, 25-second start budget, global max two JavBus fetches, shared bounded caches, negative cache, scope/cancellation checks. Challenges stop the sweep. Ordinary transport failure may try another known work. No additional actorMovies request, no 53-work scan.
- JavBus redirects allow at most three hops, HTTPS www.javbus.com only, exact same allowed work/portrait resource, no credentials/port/query/fragment/percent encoding. Requests are rebuilt without account credentials/cookies. Verification/login/unknown hosts/downgrades remain rejected.
- A narrow new fallback reads the real public Gfriends Filetree.json and ONLY its 6-Tpowers agency portrait collection. Exact canonical/verified-alias filename match; conflicting target photos rejected. URL is derived from the returned index, never actor-ID guessed. No adult jacket downloads or jacket-to-face cropping. Only whitelisted HTTPS raw.githubusercontent.com/gfriends/gfriends/master resources; redirects rejected. Index max 8 MiB, image max 2 MiB, exact MIME, JPEG/PNG signature then platform decode. Serialized public fetches, bounded 60-entry image cache, TTL/negative TTL, reset/epoch cancellation guards. Broader Gfriends collections are intentionally out of scope.
- Loaded work changes notify matching cards and form task identity; account changes clear public presentation/cache state.

## Verification contract

AvatarDiagnostics252 calls production APIClient/signatures and production JavBus/Gfriends service on macOS. Neutral parser/cache/redirect/alias tests and the existing integrated actor regression are separate from real network evidence. javbus-native252.json reports onlineSuccess only after actual downloaded bytes decode through ImageIO; saves SHA256 and dimensions. Success, if any, is the agency portrait fallback, never a claim that native JavBus verification was fixed. Dual-device UI acceptance and the user's real-device network are not proven by this probe.

250 maximum-work-count identity rules/single navigation, 247 aliases compatibility, subtitle/history/TMDB keychain logic remain. No main/win/VPS/Cloudflare changes; no force-push; no workflow dispatch.
