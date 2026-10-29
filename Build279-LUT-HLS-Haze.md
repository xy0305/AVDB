# Build 279 — HLS LUT haze / lifted blacks / grey whites fix

## User report (Build 278 on device)

Same scene, high-key (white rug/bed, beige wall, sheer black stocking):
image 1 = LUT off (AVPlayerLayer), image 2 = 278 LUT on the Metal/HLS surface.
Image 2 is hazy, washed out, blacks lifted, whites grey, skin pinkish.

Measured on the screenshots (content area, subtitles excluded, luma):

| | p1 | p5 | p50 | p95 | std | neutral white | darkest 3% | skin hue |
|---|---|---|---|---|---|---|---|---|
| LUT off (image 1) | 0.179 | 0.248 | 0.577 | 0.841 | 0.179 | 0.834 | 0.190 | 16.9° |
| 278 on device (image 2) | 0.237 | 0.335 | 0.641 | 0.771 | 0.145 | 0.753 | 0.247 | 10.7° |

## Root cause (two independent parts)

**A. Colour pipeline mismatch (Metal/HLS path only) — the haze and lifted blacks.**
`NativeHLSLUTSurface` built its source with `CIImage(cvPixelBuffer:)`. CoreImage honours the
buffer's BT.709 transfer attachment, linearises with the 709 OETF⁻¹ and re-encodes to the sRGB
output space: every shadow is lifted (0.19 → 0.25) and contrast flattens *even with a neutral cube*.
AVPlayerLayer (LUT off) shows the raw decoded values, so the user compares against the un-lifted
picture. The analysis copy (`NativeLUT.swift`) used the same call, so params were also chosen on
the lifted frame. Simulation: 709→sRGB re-encode + 278 cube on image 1 reproduces image 2
(p1 0.253, p5 0.328, std 0.146, darkest-3% 0.265, hue 8.6–9.5°). The old CI check
`strengthZeroMatchesNeutralOriginal` compared Metal against Metal, so it could not see this, and the
whos.tv benchmark measured the raw-value pipeline, not what the device rendered.

**B. LUT params on high-key frames — the grey whites and pink.**
278's hlblow fix pushed `highlight` to −18 (15% of frames ≤ −15, 0% in 6.7.8): white 1.0 → 0.76.
`bright`/`shadow` lift brightened high-key frames further, the toe allowed slope 1.6, and
`temp` −20 rotated skin 16.9° → ~9°.

## Fix

* Swift: `NativeHLSLUTSurface.sourceImage(_:)` tags decoded 32BGRA SDR buffers as **sRGB**
  (`CIImage(cvPixelBuffer:options:[.colorSpace: sRGB])`) — presentation **and** analysis use it.
  Neutral Metal now reproduces the decoded pixels. New CI host check
  `sourceImageIdentityToDecodedBuffer` compares a CoreImage readback of the production source
  image against the raw buffer bytes (mean |Δ| < 1.5 codes, dark-pixel lift < 2 codes) and records
  the legacy untagged lift as a measure.
* JS (`OriginalLUT.js`, still 6.7.8 params as target):
  * white anchor in the bake / `renderArray`: bright low-saturation source keeps its luminance
    (white balance correction kept);
  * toe slope cap 1.10 (1.35 only when shadow > 12);
  * per-frame gate gains `lift` (p5 / darkest-3%), `haze` (std, p95−p5), `greywhite`,
    `highkey` (median ≥ 0.5 or skin ≥ 0.55 brightened > 0.03) and `pink` (hue < 9°, rotated > 7°);
  * hlblow highlight floor −18 → −15.
* Tests: toe cap, white-anchor contract, synthetic high-key white-rug + sheer stocking scene
  (fails on 278: rug white 0.840 → 0.812), whole-frame lift/haze/white/high-key assertions on all
  safety scenes; HLS surface hash + sRGB-tag source contracts.

## Regression case (image 1 through the 279 cube, direct path)

| | p5 | p50 | p95 | std | neutral white | darkest 3% | skin hue |
|---|---|---|---|---|---|---|---|
| LUT off | 0.248 | 0.577 | 0.841 | 0.179 | 0.834 | 0.190 | 16.9° |
| 278 cube (no mismatch) | 0.260 | 0.609 | 0.804 | 0.164 | 0.795 | 0.197 | 9.1° |
| **279** | 0.253–0.257 | 0.602 | 0.825–0.827 | 0.172–0.173 | 0.830 | 0.191–0.195 | 10.1–12.0° |

## whos.tv benchmark (held-out by video id: 3887 skin frames / 3593 videos)

New metrics vs the untouched source frame: haze (std or p95−p5 ratio < 0.90), lifted_black
(p5 or darkest-3% +0.03), grey_white (neutral whites −0.04), highkey_over (median ≥ 0.5 frame
+0.04, or skin ≥ 0.55 +0.04), pink (hue < 8°, rotated > 8°). `278dev` = 278 as it actually ran on
device (analysis and render on the 709→sRGB lifted frame, compared with the raw frame).

| | strength ΔRGB vs 6.7.8 | haze | lifted black | grey white | high-key over | pink | crush | clip/washout | any fail |
|---|---|---|---|---|---|---|---|---|---|
| 6.7.8 | 1.00 | 14.0% | 10.5% | 15.7% | 22.4% | 70.5% | 24.0% | 40.1% | 93.0% |
| 276 | 0.60 | 25.4% | 1.1% | 31.2% | 3.0% | 1.2% | 0% | 11.7% | 48.8% |
| 278 (raw pipeline) | 0.92 | 29.5% | 11.6% | 28.9% | 18.9% | 47.5% | 0% | 0.6% | 73.6% |
| 278 on device | (1.64, mostly lift) | 58.7% | 95.6% | 25.9% | 36.6% | 53.9% | 0% | 48.2% | 99.2% |
| **279** | **0.72** (skin 0.78) | 0.7% | 0.0% | 0.0% | 0.4% | 0.2% | 0% | 0.7% | **1.8%** |

On frames where 6.7.8 itself causes none of these problems (except its hue rotation), 279 keeps
**0.90×** of 6.7.8 strength (0.89× on non-high-key frames). The overall 0.72× is the cost of not
greying whites / not brightening high-key frames / not lifting blacks on the ~93% of frames where
6.7.8 does at least one of those.

Not covered: the local-file path (`AVVideoComposition` `request.sourceImage`) is colour-managed
by AVFoundation and was not changed or measured on device here.
