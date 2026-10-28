# Build 278 — avbase.net HQ covers + actor headshots

Base tip: `feat/lut83-full-from267` (MARKETING 1.0.2 / CURRENT_PROJECT_VERSION **268**). Version metadata stays 268; this note is the feature build id.

## Sources

Public HTML only (cookie-free, no `/api` probing, no browser state):

| Role | Request | Evidence field |
|---|---|---|
| Large cover | `GET https://www.avbase.net/works?q={番号}` → one `__NEXT_DATA__` | product `image_url` (`…pl.jpg`) preferred over `thumbnail_url` (`…ps.jpg`) |
| Actor avatar | `GET https://www.avbase.net/talents/{name}` → one `__NEXT_DATA__` | `talent.primary.image_url` / `actors[].image_url` → `https://pics.dmm.co.jp/mono/actjpgs/{slug}.jpg` only |

Declared hosts: **`www.avbase.net`** (HTML) and existing DMM/MGS image CDNs already admitted by `AvbaseMetadata.image` / `actorImage`. No silent undeclared host rewrite.

## Priority

### Movie covers (detail + list)

1. Warm `ListHQCoverCache` / Tenhow→Amazon / existing detail winners  
2. **avbase-bound catalogue images, HQ-first (`pl` before `ps`/`jp`; digital package preferred)**  
3. Guessed public DMM/MGS candidates  
4. JavDB cover → thumb (unchanged fallback)

`ListCoverPolicy` now admits `AvbaseMetadata.allowedDiscoveredImage` so catalogue `pl.jpg` is not dropped (public `DMMPoster.allowedImage` still rejects bare `pl` by design).

### Actor portraits

1. Existing AVDB `avatar_url` / `cover_url`  
2. JavBus exact star portrait  
3. Gfriends curated agency (HQ)  
4. **avbase talent → FANZA actjpgs**  
5. TMDB `h632`

## Limits

- Exact work / exact talent name match only; ambiguous product or conflicting headshots rejected.  
- No WAF/captcha bypass; redirects blocked on catalogue/portrait fetches.  
- List grids still do not scrape avbase per cell; they only consume already-bound catalogue metadata + detail tips.

## Tests

- `scripts/test-catalogue-metadata.py` (HQ image order + talent parser)  
- `scripts/test-avbase-portraits278.py`  
- `scripts/test-list-hq-covers275.py` (avbase discovered-image admit)
