# Native LUT: v8.3 selective safety update

## Provenance and scope

Baseline: `ec82c2388274e17596ab3a3df9fa3e61ff091669` (user-designated 1.0.2/266; verify version independently in Info/project). The inherited numeric engine comes from supplied `网页视频实时 LUT（v6.7.5）`, metadata `@author You`, `@version 6.7.5`; unexecuted reference remains `THIRD_PARTY/lut-v6.7.5.txt`. Its redistribution permission is unverified; no license is invented. New bounded validation, final safety attenuation and neutral protection are independently implemented from requirements, not copied from the v8.3 Python source.

The v8.3 ZIP and offline article were inspected statically only. No Python/Lua entry point, dependency installer, remote dependency, video, cover or advertisement was run/fetched. The article attributes face-landmark adoption to v8.0; it is not uniquely new to v8.3. Existing native code already uses MediaPipeTasksVision 0.10.14, VIDEO mode and an existing bundled model with a GPU delegate. The supplied `.task` is not treated as Swift source or silently substituted. Model inference and delegate thread/lifecycle behavior still require device validation; no new dependency is added.

## Implemented changes

- Correct nonlinear saturation response from inherited 1.5 to v8.3's 0.82. Brightness 0.67 and contrast 0.57 were already present.
- Standard skin-statistic targets: R/B 1.24–1.50, R/G 1.20–1.35, luma 0.35–0.54, saturation 0.22–0.34, highlight fraction 0–0.05. These are advisory heuristic targets, not a universal standard for all skin tones.
- High-match entry uses all four color/luma/saturation metrics, no highlight-count shortcut. Already-matching sampled skin returns neutral parameters, avoiding mandatory cooling of natural skin. This is deliberately more conservative than the desktop biased template.
- Extreme darkness keeps inherited R/B <=1.6, luma <0.22, shadow fraction >0.35 and tightens highlight fraction from <0.15 to <0.10.
- Missing-face fallback samples the whole image, not central 50%; native labels match. Existing Cr/Cb rejection and minimum 150 accepted pixels remain. This is a heuristic fallback, not semantic skin segmentation. Face ROI behavior and model are retained.
- Final search result, after all legacy balancing, is clamped to the same [-50,50] domain used by cube generation. Brightness is bounded to [-10,10] (extreme-dark upper bound 35). If original sampled luma is within the standard range, attenuate the complete final adjustment toward neutral until final luma has not fallen by more than 0.005. A bounded fallback returns neutral if necessary.
- Zero parameters now mean true identity for every 33^3 grid node. The old overexposure limiter accidentally modified colored highlights even with zero controls; identity bypasses that limiter in both analysis mapping and cube generation.
- Validate image dimensions/length, finite clamped ROI, finite parameter count and finite [0,1] native RGBA output. Red varies fastest, then green, then blue. Alpha stays 1.
- Native one-entry cube cache has an exact parameter key. Strength/comparison/enhancement changes reuse a matching cube. Reset/detach invalidate data and key. Existing generation/revision checks prevent late publication; JavaScript execution already in progress is not forcibly interrupted.

## Already supported / deliberately not transplanted

Already present: per-highlight 0.70/0.95 temperature damping, 80%-interval temperature target in standard search, three-branch brightness interval error, one-sided highlight error, extreme-dark compensation skip, staged luma guards, independent background JavaScriptCore VM, SDR/HDR format gates, image-space strength dissolve, debounce and stale-result guards.

Not transplanted: desktop Tk UI/delta preview/Chinese-path startup restriction, ffmpeg/MPV/Lua file association and universal-CUBE loader, Python dependency install/download, four-image calibration as a universal complexion target, full multi-frame desktop analysis, desktop fixed +6 tint and aggressively biased templates. The inherited search structure is retained; this is not an exact or complete v8.3 Python port. Inherited legacy center-specific code remains unreachable from the native full-frame fallback and is not claimed as active v8.3 functionality.

The desktop implementation's analysis mapper and final exporter differ in their overexposure behavior; direct copying would not ensure predictor/render equivalence. New tests check shipped mapper/cube semantics instead of promising old-version byte equality.

## Color pipeline / limitations

The actual native pipeline is nonlinear sRGB SDR [0,1], using Rec.709 primaries/luma coefficients and `CIColorCubeWithColorSpace(sRGB)`. Rec.709 and sRGB share primaries but not transfer curves; do not claim Rec.709-transfer or HDR equivalence. HDR PQ/HLG, HLS/noncomposable composition limitations are unchanged. No adapter, parser, filter, TangxinCore, seeking or playback progress code is changed.

Manual adjustment, reanalysis and restore-original remain available even with insufficient skin data; there is no forced default color cast. The enhancement pipeline bypasses the LUT at strength zero; independently enabled sharpening/deband can still alter the image. No extra per-frame JavaScript analysis is introduced.

## Tests and evidence

`scripts/test-native-lut.py` now invokes `scripts/test-lut83.js`, replacing obsolete v6.7.5 whole-engine exact-parity assertions. Tests cover every identity grid node/red-fastest index/boundary; malformed input and nonfinite parameters; bounded extremes; neutral gray; 0.82 saturation; highlight-temperature damping; off-center whole-frame fallback; natural-skin neutral protection; strict dark-scene routing; final luma and deterministic search. All fixtures are generated color blocks, not external media.

On macOS the same entry point additionally runs native JavaScriptCore parity (parameters/cube samples) and actual CoreImage identity/RGB-boundary/zero-strength-dissolve rendering, and prints native macOS cube bake wall times. Linux explicitly reports these native tests NOT RUN. This script is not a substitute for iOS simulator/device integration, cancellation/cache runtime and playback/seek regression. CI must actually run it and preserve results before claiming native validation. Linux/iSH Node timings are not iOS GPU/FPS benchmarks.

KSPlayer remains an external GPL-3.0 dependency: preserve its notices/license and provide corresponding source for the exact application/dependency revision with binary distribution. This does not license the unlicensed supplied scripts.
