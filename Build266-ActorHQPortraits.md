# Build 266 — high-quality single-person actor portraits

Extends the Build 252 / 253 actor avatar pipeline without changing winner order:
AVDB artwork → JavBus exact star portrait → **Gfriends curated agency portraits** → TMDB.

## Inventory (unchanged movie-cover path)

Detail front covers remain DMM / JavBus jacket / Tenhow→Amazon primary / TPDB / Avbase /
catalogue-bound images via `DetailPosterResolver`. This change does **not** add a new
movie-jacket scraper.

## Actor portrait sources after this build

| Priority | Source | Notes |
|---|---|---|
| 1 | Existing AVDB `avatar_url` / `cover_url` | Decoded via ImageLoader; valid originals always win |
| 2 | JavBus `/pics/actress/*_a.jpg` | Exact number + alias; public headers 253; CF/verify still may fail |
| 3 | Gfriends curated agency collections | Expanded beyond sole `6-Tpowers` |
| 4 | TMDB person profile | Now `h632` (was `w185`) when the in-app Read Access Token is set |

## Gfriends expansion

Public `Filetree.json` is still the only index. URL hosts remain
`raw.githubusercontent.com/gfriends/gfriends/master` only; redirects rejected; exact
filename match on canonical/verified aliases; conflicting targets inside one collection
rejected; actor-ID URL guessing still forbidden.

**Newly whitelisted** (priority order after `6-Tpowers`): `1-FALENO`, `0-Hand-Storage`,
`2-Juicy-Honey`, `3-MUTEKI`, plus other agency/card collections (`4-Kawaii`, `5-Premium`,
`5-Ebody`, `7-S1`, `7-Madonna`, `7-Moodyz`, `8-Ideapocket`, `8-GRAPHIS`, `v-Prestige`,
`v-Attackers`, `v-Fitch`, …). Selection walks groups in that order and takes the **first
collection with a unique exact hit**.

**Deliberately still excluded**: wiki/scrape dumps such as `y-Minnano`, `y-AVDC`,
`z-DMM(步/骑)`, `z-Derekhsu`, `9-Javrave`, `9-AVDBS`, `8-Warashi` — not treated as
high-fidelity single-person agency portraits.

Native size samples (complete GET, text-only evidence): `6-Tpowers` ~1160² JPEG;
`1-FALENO` ~1500×2125 JPEG. Image ceiling remains 2 MiB; index 8 MiB.

## TMDB

`ActorAvatarFallback.imageBase` uses `https://image.tmdb.org/t/p/h632` for larger official
profiles. Keychain token policy unchanged; no bundled secret.

## Tests / CI

- `scripts/test-javbus-actors251.py` + `JavBusActorsRegression251` multi-group selects
- `scripts/test-actor-hq-portraits266.py` static contract
- `scripts/test-actor-avatar243.py` expects `h632`
- Wired into `dmm-preview266.yml`

No main/win force-push; no WAF/captcha bypass; no jacket-to-face crop; no unsafe eval.
