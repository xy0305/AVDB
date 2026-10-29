# Build 275 — LUT anti-overexposure (mobile washout)

Base tip: `feat/lut4-online-from269` @ 274 (`51fd1e2`). Version **1.0.2 / 275**.

## Problem
User screenshots (warm indoor, lit skin, white lockers/walls) showed LUT blowing highlights / washing midtones after 开启.

## Cause (engine)
- Desktop v6.7.8 `HL_FINAL_MIN = -7` caps highlight compression even when autoHlComp / high-hl search want deeper negative.
- Mid-bright scenes with meaningful `full_hl_ratio` still search bright toward +18 (`高光放行提亮` / +0.09 lum target).
- `highHlScene.brightMaxExtra: 5` widened bright ceiling on already-hot frames.
- `autoHlComp` only kicked in above bright 15 @ strength 0.5.

## Change (deliberate mobile divergence; 6.7.8 spirit kept)
- **washoutRisk** gate: high-hl scene **or** `(hl≥0.16 & lum≥0.46)` **or** `(hl≥0.22 & lum≥0.40)`.
- On washoutRisk: lower bright-search uplift (+0.03 / cap 0.50), **tighten** bright max (`brightCapDelta: 8`, no `brightMaxExtra`), skip `高光放行提亮`, allow highlight search/final down to **−14**, force highlight floor (−9 / −12 by hl severity).
- Global: `autoHlCompBrightThreshold` 15→**10**, `autoHlCompStrength` 0.5→**0.85**; `highHlScene.brightMaxExtra` 5→**0**; broader 高光钳制 (×0.4 raise cut).
- Extreme-dark path unchanged in intent; classifiers / sampleSkinStats / cube bake order stay 6.7.8.
- Tests: anti-OE fixtures (bright / warm mid-hl); cube self-consistency; 6.7.8 param equality where unchanged; extreme mode still exact vs oracle.
- Packaging: `package-lut275.py` / `lut4-online275.yml`; docs `NATIVE-LUT.md`.

## Not claimed
- Pixel-identical to browser WebGL / desktop MPV on bright SDR.
- Removing user strength slider or changing default strength.
