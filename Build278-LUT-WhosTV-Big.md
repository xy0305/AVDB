# Build 278 — LUT: restore 6.7.8 enhancement + per-frame safety

## Correction vs Build 276

whos.tv screenshots are **raw video stills** (LUT *inputs*), not studio-graded targets.
Build 276 treated their skin medians as the look target and damped every frame that
already sat in that band (`gradedRef`), which made the LUT do almost nothing on
typical source footage. Build 278 reverses that:

* **Target look** = original userscript v6.7.8 enhancement (params + pipeline).
* **whos.tv big set** = robustness / safety *benchmark* of real source frames.
* Safety guards engage **only** on frames where the 6.7.8 bake would actually fail
  (crushed near-black / dark fabric, highlight blow-out, skin hue into magenta,
  oversaturation). Every other frame keeps the full 6.7.8 param set.

## Scrape (whos.tv)

| | count |
|---|---|
| Listing / category pages crawled | **4000** (`/en/frames` + `page-2..500` + 7×`type-*`/`page-1..500`) |
| Unique still URLs discovered | **37230** (`f.hersav.me/video_frames/.../*s.webp`, typically 512×288) |
| Distinct images kept after decode / size / blank / flat / dHash≤4 | **19741+** (download still growing at delivery) |
| Skin-bearing frames in the analysis set | **9749** (of 9840 prepared stills from the main listing crawl) |
| Held-out (by video id, 20%) | **1931** frames / 1810 videos |

Stored under `/workspace/lut-ref/whostv-big/` (`pages.json`, `manifest_raw.json`,
`prep_big.json`, `raw/*.rgba`, `summary_big.json`).

Input skin distribution on the analysis set (p5 / p25 / p50 / p75 / p95):

* R/B 1.26 / 1.39 / 1.49 / 1.60 / 1.77
* R/G 1.16 / 1.25 / 1.32 / 1.39 / 1.48
* luma 0.29 / 0.40 / 0.47 / 0.53 / 0.60
* sat 0.22 / 0.29 / 0.33 / 0.38 / 0.43
* hue° 2.1 / 10.9 / 16.1 / 21.0 / 29.3

## What changed (`OriginalLUT.js`)

Restored from the Build 274 / userscript 6.7.8 baseline (pre-275/276 damping), then:

1. **Removed** Build 276 `gradedRef` near-neutral damping and the widened targets that
   treated whos.tv medians as the look goal. Restored desktop `TARGETS`
   `skin_rb [1.24,1.50] / skin_rg [1.20,1.35] / skin_sat [0.22,0.34]`.
2. **Removed** Build 275 washout-risk hard bright/highlight caps that permanently
   truncated the 6.7.8 search on many mid-lit frames.
3. **Kept / refined shadow toe** (black point 0, source hue, bounded slope
   `slopeMin=0.97`…`slopeMax=1.60`) so dark fabric / black stockings keep detail
   under high contrast/shadow params — without capping the 6.7.8 shadow lift.
4. **Added soft highlight shoulder** on the *baked* cube (`knee=0.78`, `ceil=0.97`)
   so the hard `OVEREXPOSE_LIMIT=0.92` plateau does not flatten texture; the
   parametric search still uses the original hard cap so params stay 6.7.8-shaped.
5. **Per-frame safety gate** (`CONFIG.safety`): after `predictParams`, render the
   full bake (params + toe + shoulder) on a whole-frame sample + skin sample.
   Failures nudge params one step at a time until the frame passes:
   * magenta → cut tint / warm temp / lower sat
   * highlight blow → pull highlight, then bright, then contrast
   * crush → cut contrast / lift shadow
   * black-lift → lower shadow / bright
   Frames that already pass keep the exact 6.7.8 params (held-out: **22%** of
   frames identical to 6.7.8; the rest differ only by the safety nudge).

`NativeLUT.swift` is unchanged: it still drives `OriginalLUT` via JSContext
(`analyzeFrame` / `analyzeMultiFrame` / `cubeRGBA`). The bake path picks up the
toe + shoulder automatically through `generateLutData` / `cubeRGBA`.

## Metrics (held-out split, n=1931)

| build | mean ΔRGB | vs 6.7.8 | any-fail | crush | dark-fabric | clip/washout | magenta |
|-------|-----------|----------|----------|-------|-------------|--------------|---------|
| 6.7.8 | 0.0608 | 1.00× | **77.2%** | 22.7% | 6.6% | 42.0% | 47.6% |
| 276   | 0.0365 | 0.60× | 13.5% | 0% | 0% | 12.4% | 1.1% |
| **278** | **0.0554** | **0.91×** | **0.6%** | **0%** | **0.05%** | **0.4%** | **0.2%** |

Median params on held-out:

* 6.7.8: temp −22 / bright 11 / contrast 5 / highlight −7 / shadow 12
* 276:   temp −6  / bright 6  / contrast 3 / highlight −7 / shadow 3  *(near-neutral)*
* 278:   temp −21 / bright 10 / contrast 5 / highlight −8 / shadow 12 *(6.7.8-shaped)*

All-set (n=9749) matches the held-out picture: 278 retains **91%** of 6.7.8
enhancement strength while collapsing any-fail from 77% → **0.8%**.

## Tests / packaging

* `scripts/test-native-lut.py` rewritten for 278 contracts (toe, shoulder,
  magenta, 6.7.8 param equality when safe, per-frame safety scenes).
* Workflow `lut4-online278.yml`, `package-lut278.py`, CFBundleVersion **278**.
* Previous `lut4-online277.yml` switched to `workflow_dispatch`.
