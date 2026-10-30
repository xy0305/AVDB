# Build 285: on-device AI cover enhancement (Core ML) + cover-source fixes

Results (CI timings, screenshots, sha256) are filled in by the report; this file documents the design.

## AI 封面画质增强
- Model: 4xNomosWebPhoto_esrgan (ESRGAN 4×, CC BY 4.0 per release notes; see THIRD_PARTY), converted to
  Core ML ML Program fp16, static 128×128 tile → 512×512. `AVDB/Resources/CoverSR.mlpackage` (33 MB),
  compiled by Xcode into `CoverSR.mlmodelc`. Reproduce with `scripts/convert-coversr285.py`.
- Engine (`AICoverSREngine.swift`): edge-padded 128 px tiles, 12 px overlap, linear feathering, fp16
  MLMultiArray I/O via vImage, output ×4 capped at 2160 px height. Compute units `.all` on device
  (simulator: CPU only). Runs in `Task.detached(priority: .userInitiated)`, progress per tile.
- Policy (`AICoverPolicy.swift`): only covers whose NATIVE front height is < 1000 px (800 px jacket
  crops 378×538, MGS pf_e 422×600, JavDB 376×538, DUGA 474×674). HQ originals are never enhanced.
  Auto runs need thermal nominal/fair, no Low Power Mode, battery ≥ 20 % or charging; manual taps only
  refuse on serious/critical thermal state.
- UI: hero chrome 「AI 增强」 button → progress ring with % (tap = cancel) → 「AI 增强」 badge + hold-to-
  compare button; tap the cover → fullscreen viewer (pinch / double-tap zoom, 「按住对比原图」,
  native → AI resolution). 设置 → 「AI 画质增强」 自动 / 仅手动 / 关, cache size, 清除增强缓存.
- Cache: Caches/AICover JPEG q0.92, key = SHA256(model version + winner URL + native size), 300 MB LRU.

## Cover-source fixes (research items 1–4)
1. Jacket front crop 0.69 → measured right-aligned 0.703·h (MILK h_1240 keeps 0.69). IPX-706 800×538 →
   378×538 at x=422 (was 371 at 429).
2. DUGA `pic.duga.jp/unsecure/{label}/{id}/noauth/jacket.jpg` (native 1000 px, same 0.703 geometry) from
   the avbase record, only when it is the sole DUGA product or its label equals the MGS maker directory
   (ABF-087 also lists a re-release eiten-2295 with a different jacket).
3. MGS Prestige `images/prestige/…/pake-03_sp-*.jpg` (native 1125×758, 0.703 geometry); SIRO/FCT 1348 px
   upscales are never admitted. `pb_e_` → `pf_e_` portrait for MGS records.
4. Persistent learning: jacket-only DMM CIDs (147×200 ps) are remembered for 14 days and their ps probe is
   skipped; list HQ winners persist (UserDefaults, 1024).

## Tests
`scripts/test-ai-cover285.py` (policy / guard / tiling / size cap, crop, jacket-only TTL, DUGA rank,
avbase extras parser, wiring, model bundled, version 285), `scripts/test-ai-bench285.py` (macOS: shipping
engine on neutral fixtures per compute unit, fp16 parity vs PyTorch, compute plan),
`scripts/test-ai-ui285.py` (simulator screenshots).
