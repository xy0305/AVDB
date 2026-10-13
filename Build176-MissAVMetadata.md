# Build 176 — MissAV identity, AVDB presentation

Baseline: main 1cd2c02 / 1.0.2 (175). MissAV remains an additional source; existing AVDB/JavRanking entry points are unchanged.

## Video ranking
Visible cards enqueue full-number searches against the existing AVDB SDK, using its unique exact-number policy. Successful cards render the existing MoviePosterCard and JavDBImage pipeline using AVDB cover/title/data; source order is never sorted by response completion. Opening a resolved card routes to the existing native detail and its existing magnet/115 controls. Unresolved cards keep source identity and show a retry/manual search route, never fabricated cover URLs or unrelated first results.

## Actress ranking
Read-only HTTPS GET https://missav.fans/cn/actresses/ranking on 2026-10-13 returned HTTP 200, title `女优排行 OCT 2026`, and 100 h4 actress entries. This is the site's current monthly list; no fabricated daily/weekly parameters. Source names and path names are identity hints, not AVDB IDs. Search uses exact Unicode/width/case/whitespace-normalized names and explicit aliases; ambiguity is never auto-selected. Matched cards use AVDB avatar/name and native ActorDetailView. Unresolved candidates can be inspected manually.

## Request ownership
A view-owned queue has at most two active metadata requests, deduplicated by full number or actress path. Results are cached during the view lifetime with bounded eviction. Source/account changes invalidate results; disappearance cancels work and removes unfinished states, allowing subsequent appearances to enqueue again. Existing MissAV HTTP session, challenge classification, source validation, and original 115 resource preflight remain unchanged.

## Validation boundaries
Parser/identity runtime regression added to existing macOS Swift test runner; existing full iPhoneOS build and iPad workflows must pass before release. No real 115 task, account login, cloud deletion or subscription was performed. Live source availability is network-dependent; an exact AVDB match requires accessible backend data. Not a device image-loading/actress matching/115 acceptance claim. Source screenshots from the user show missing images in build175; build176 does not fall back to source covers pretending they are AVDB covers.
