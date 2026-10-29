# Build 273 — LUT 画质：有界多帧分析（v6.7.8）

Base tip: `feat/lut4-online-from269` @ 272 (`7262489`). Version **1.0.2 / 273**.

## Change
- Native grab: up to **3** decoded frames ≈**80ms** apart while playing; paused → single frame; **no seek**.
- Early-stop on MediaPipe face box; skip duplicate PTS/buffer.
- `OriginalLUT.analyzeMultiFrame`: prefer 人脸框 frames, **median** of per-frame skin stats, merge pixels → `predictParams`.
- `analyzeFrame` kept for single-frame / test parity.
- Docs: `THIRD_PARTY/NATIVE-LUT.md` updated honestly.

## Not claimed
- Pixel-identical to browser WebGL / desktop MPV IMAGE-mode.
- requestVideoFrameCallback scheduling; tray R/F hotkeys beyond in-app buttons.
