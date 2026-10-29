# Build 276 — LUT shadow detail + skin guard

Base tip: `feat/lut4-online-from269` @ 275 (`0e7a680`). Version **1.0.2 / 276**.

## User feedback (275, LUT on)
1. Dark sheer stockings / dark fabric disappear (no shadow detail).
2. Skin tone looks strange.

## Screenshot numbers (two LUT-on frames, pillarbox removed; stats only)
| | frame A | frame B |
|---|---|---|
| luma p1 / p5 / p50 / p99 | 0.137 / 0.216 / 0.582 / 0.858 | 0.235 / 0.357 / 0.637 / 0.769 |
| share luma < 0.08 | 0.000 | 0.000 |
| skin (YCbCr mask) mean hue | 14° | **344° (pink/magenta)** |
| skin sat (max-min)/max | 0.36 | 0.25 |

Frame B skin is rotated past red into magenta. The frames have no true blacks,
but without LUT-off frames we cannot tell how much of that comes from the source.
The engine probes below show what the 275 cube does to shadows.

## Cause (engine probes, 275 cube)
- **Toe crush:** `contrast` pivots at 0.5. The white-fog step (白雾补偿) pushes contrast up to +6, which drives
  near-black to 0: luma 0.02 → 0.000, 0.05 → 0.026–0.042. Sheer dark fabric texture
  (0.02–0.08) merges into flat black. `bright` / `shadow` are multiplicative, so they do **not** lift pure black.
- **Skin hue/sat:** the standard template (`temp −20`, search down to −40, contrast-driven
  −3/−6 temp pull-back, face-box `tint` forced to +6) rotates skin hue 19° → 3°, pinkish 0° → 326°,
  and cuts skin saturation by up to 45% (0.43 → 0.25).

## Change (deliberate mobile divergence from desktop 6.7.8)
- **Shadow toe in cube bake** (`CONFIG.shadowToe`, `applyShadowToe`). For input luma below 0.10 the output is
  the *source colour × bounded slope*. The slope is the neutral pipeline gain at luma 0.20, clamped to
  [0.92, 1.05]; extreme-dark templates with shadow > 10 may go up to 1.25. The toe smoothsteps back to
  the untouched 6.7.8 pipeline at 0.20. Results:
  - black stays exactly 0
  - luma below 0.08 is lifted by at most 5% and crushed by at most 8%
  - dark-fabric hue/chroma is not hit by the skin-targeted temp/tint
  - the neutral cube is still identical to 275
- **Skin guard** (`CONFIG.skinGuard`, `skinGuardParams`, non-extreme paths, plausible skin samples only).
  After the parameter search, it walks `tint` → `temp` → `sat` until all of these hold:
  - mean skin hue rotation ≤ 6°
  - skin hue does not go below min(4°, original), i.e. no magenta wrap
  - skin saturation stays within ×0.80–×1.15
- Graded-reference retune (see below): TARGETS, the shadow cap and near-neutral damping for in-band frames.
- Unchanged: 275 anti-overexposure (`washoutRisk`), classifiers, `sampleSkinStats`, extreme-dark params,
  analysis / multi-frame / scene-guard, and the default strength (1.0). The engine changes were enough,
  so strength was not lowered.

## Graded reference calibration (whos.tv stills, stats only; images not committed)
- Sample: 261 stills downloaded with throttling (249 `/en/frames` listing frames, 1 per video, plus 12 homepage intro stills). Stored on the box under `/workspace/lut-ref/whostv/`.
  259 contained skin under the engine's own `sampleFrame` (center fallback, no MediaPipe box).
- Outputs: summary in `/workspace/lut-ref/whostv-summary.json` and per-image values in `whostv-stats.csv`.
- Percentiles p5 / p50 / p95:
  - skin_rb 1.25 / 1.50 / 1.80; skin_rg 1.16 / 1.32 / 1.48
  - skin_lum 0.31 / 0.475 / 0.615; skin_sat 0.22 / 0.34 / 0.44
  - skin hue 1° / 16.8° / 31°
  - luma p1 0.005 / 0.051 / 0.17; near-black (<0.03) share 0 / 0.001 / 0.14
  - global hl ratio (>0.65) 0.002 / 0.19 / 0.70
- 6.7.8 TARGETS covered only 46% (rb), 48% (rg) and 47% (sat) of graded frames. On these graded stills, the
  275 engine produced:
  - median temp −22, tint +5, shadow +12
  - skin hue rotation median −13°, with 90% of frames rotated by more than 6°
  - skin sat ratio median 0.64
  - p99 luma 0.92 → 0.81
- 276 retune:
  - TARGETS / TARGETS_CENTER rb [1.30, 1.70], rg [1.18, 1.44], sat [0.24, 0.42]. Center lum is now [0.38, 0.60]; the old [0.55, 0.75] brightened graded frames.
  - non-extreme shadow ≤ template + 4
  - `gradedRef` band: rb 1.30–1.75, rg 1.18–1.45, lum 0.38–0.60, sat 0.25–0.43 (56% of the sample). Inside the band, params are scaled ×0.5 toward 0 and capped:
    - bright ≤ 6, |contrast| ≤ 3, shadow ≤ 4
    - highlight ≥ −5, or ≥ −7 on washout-risk
  - 275 washout thresholds are kept: the gate fires on 47% of graded frames, but its effect is now damped in-band. Narrowing it without LUT-off user frames risked bringing the overexposure back.
- Reference results, 275 → 276 (face-region rows, p50 unless noted):

| metric | 275 | 276 |
|---|---|---|
| temp | −22 | **−6** |
| tint | +5 | **0** |
| shadow | +12 | **+3** |
| mean abs ΔY | 0.047 | **0.028** |
| skin hue rotation | −13.2° | **−2.1°** (p5 −5.8°) |
| frames rotated > 6° | 90% | **2.3%** |
| skin sat ratio | 0.64 | **0.91** |
| frames with p1 crushed by > 0.02 | 6.9% | **0%** |
| p99 output (input p99 0.92) | 0.81 | **0.84** |

## Probe results (synthetic scenes, final 276)
| scene | 0.02 / 0.05 luma out (275 → 276) | skin hue in→out (275 → 276) | skin sat in→out (275 → 276) |
|---|---|---|---|
| warm-mid-hl | 0.010/0.042 → 0.020/0.051 | 20.0→8.5 → **20.0→16.6** | 0.43→0.25 → **0.43→0.35** |
| neutral-mid | 0.001/0.038 → 0.021/0.053 | 19.1→2.8 → **19.1→17.5** | 0.36→0.19 → **0.36→0.33** |
| pinkish | 0.000/0.036 → 0.021/0.053 | 0→326 → **0→0** | 0.24→0.20 → 0.24→0.25 |
| yellow | 0.000/0.026 → 0.021/0.053 | 30.8→33.8 → 30.8→31.2 | 0.53→0.34 → **0.53→0.43** |

## Tests (`scripts/test-native-lut.py`)
- Oracle cube equality (when params equal 6.7.8) now covers grid entries with input luma ≥ 0.20; the toe
  region is checked against the new toe contract instead.
- New toe contract on every case and on the regression fixtures:
  - black point exactly 0
  - neutral ramp is monotonic
  - toe ratio stays within [0.92, 1.05] (extreme-dark: up to 1.25)
  - no lift above 5% below 0.08
  - dark-fabric chroma ratios preserved
  - 0.03→0.06 shadow step keeps ≥ 92%
- New `harsh` fixture (temp −31 / contrast +6): the 6.7.8 oracle crushes 0.03 luma to < 0.01, the mobile cube keeps it at ≥ 0.029.
- New skin fixtures (warm / pink / dim / neutral): hue rotation ≤ 6.5°, no magenta, sat ratio ≥ 0.78.
- New graded-reference fixtures (reference p25 / p50 / p75 skin + hl / sh medians, both face and center regions). Each must stay near-neutral:
  - |temp| ≤ 10, |tint| ≤ 3, |sat| ≤ 3
  - bright in [−3, 6], |contrast| ≤ 3, highlight in [−7, 2], shadow ≤ 4
  - skin hue rotation ≤ 4°, sat ratio 0.85–1.10, skin luma shift ≤ 0.05
- Extreme-dark `predictParams` still exactly equals the 6.7.8 oracle.

## Not claimed
- Pixel-identical to desktop 6.7.8 / browser WebGL: the shadow toe and skin guard are deliberate mobile changes.
- On-device verification on the user's clip: still needs the user to check that clip on device.
- Content that is already flat or lifted in the source is not re-darkened. The toe only stops the LUT from crushing or lifting near-black.
