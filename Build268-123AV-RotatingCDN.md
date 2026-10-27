# Build 268 — 123AV rotating HLS CDN (fix 暂不支持)

## Root cause

Search/detail/embed still match Build 254: `/en/search`, `/en/v/<code>`, inert `player(JSON.parse(...))`, `sadie-shop.site` `/e/<id>` + `/stream`.

Live `/stream` JSON now returns **rotating** HTTPS origins under the same `/oo5/*.m3u8` path, for example:

| Code | Observed media host |
|---|---|
| FNS-249 | `jzxz.freeboldspirit.site` (Build 254 pin) |
| EBWH-372 | `85kq.cleartruevision.site` |
| PRWF-017 | `8vpr.deeptrueforce.site` |
| SSIS-001 | `jmv1.grayson-store.site` |

`OnlinePolicy.media(.av123)` only allowed `jzxz.freeboldspirit.site`, so `OneTwoThreeAVAdapter.stream` threw `.incomplete` → UI「详情: 暂不支持（适配或协议未完成）」after a candidate was found.

## Fix

- Treat 123AV HLS like other page/API-issued origins: `discoveredMedia(.av123)` accepts secure public HTTPS playlists whose path starts with `/oo5/` (exact observed protocol path).
- `stream()` validates with `discoveredMedia`, not a single pinned host.
- `media(.av123)` stays closed (`false`) so unscoped transport does **not** widen to arbitrary `/oo5/` URLs; only identity-validated detail → embed → `/stream` issuance plus `validatedPlan(pageIssued:)` binds DNS and HLS children to the **issued** origin.
- Multi-episode rows remain `.incomplete` (no implicit pick). Non-`/oo5/` or non-HTTPS stream URLs remain incomplete.
- No remote JS eval, no guessed tokens/paths, no arbitrary domain allowlist beyond the issued `/oo5/` shape.

Neutral fixture regressions cover rotating-host acceptance and non-`/oo5/` rejection. First-frame playback is still unverified by CI (manifest metadata only).
