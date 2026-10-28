# Build 277 — 播放进度条点按跳转

Base tip includes Build 276 Tangxin detail play/tags. Version stays 1.0.2 / project build 266 (preview artifact naming unchanged).

## Root cause

`KSChromePlayer.progressBar` 用的是 SwiftUI `Slider`。系统 Slider **只认拖动滑块**，点轨道不会触发 `editing` / `set`，所以只能拖到目标位置。

## Fix

1. 保留原有 `Slider` 拖动 + seek 预览（UITest `app.sliders.firstMatch.adjust` 仍可用）。
2. 用 `GeometryReader` 包住进度条，加 `SpatialTapGesture`（`simultaneousGesture`，不抢拖动手势）。
3. `tapSeekProgress(atX:width:)`：把 `x / width` clamp 到 `[0,1]` 映射成绝对时间后 `seek(to:)`；`horizontalDrag` / `seekPending` / 无效 `duration` 时忽略。
4. `accessibilityIdentifier("player.progress")` 方便后续点按测试。

不改画面区水平拖动 seek、双击跳转、音量 UISlider。

## Tests / Build note

- `scripts/test-progress-tap277.py` 静态守卫。
- CI：`dmm-preview266.yml` / `build-ipa.yml` 增加该脚本。
