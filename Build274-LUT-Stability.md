# Build 274 — LUT 画质/稳定性自研优化

Base tip: `feat/lut4-online-from269` @ 273 (`829934c`). Version **1.0.2 / 274**.

## Change
- **Scene-change guard**: `analyzeMultiFrame` / `selectCoherentPairs` — if per-frame `skin_lum` span > 0.08 or `skin_rb` span > 0.18 across ≤3 frames, do **not** median mixed scenes; keep largest coherent cluster (face-preferred) or best single frame. `analyzeFrame` unchanged.
- **Param/cube crossfade ~200ms** (native UX): after analysis/reanalyze publish, dissolve previous CIColorCube → new (or original→new). Online reanalyze keeps Metal filter until new cube fades in. **关闭/bypass** still clears immediately. HDR/DRM/PiP hard-fallback untouched.
- **Sample interval ~120ms**: playing multi-frame grabs align to userscript `CONFIG.sampleIntervalMs` (was ~80ms). Paused → single frame. No seek. ≤3 + face early-stop.
- **Enable delay ~400ms**: first 开启 auto-analyze waits before grab (avoid black/loading). 重新分析 stays immediate.
- Docs: `THIRD_PARTY/NATIVE-LUT.md`; packaging `package-lut274.py` / `lut4-online274.yml`.

## Not claimed
- Pixel-identical to browser WebGL / desktop MPV.
- Full userscript RVFC loop or `initialDelayMs: 500` literal (native uses ~400ms).
- Crossfade on every strength-slider tweak (analysis/reanalyze publish only).
