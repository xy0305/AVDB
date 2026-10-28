# Build 276 — 糖心详情：封面可点播放 + 标签 pill

Base tip includes Build 275 list HQ covers. Version stays 1.0.2 / project build 266 (preview artifact naming unchanged).

## Root cause（播放点不到）

1. **封面无播放控件**：详情只在标签列表**下方**放了一个 `borderedProminent`「播放」按钮；封面 `TangxinImage` 带 `allowsHitTesting(false)`，且没有 overlay / 手势。
2. **按钮被挤出首屏**：标签用竖排 `NavigationLink` + `frame(minHeight:44)`，5 个标签约 250pt+，播放键落到 TabBar 下方，需大幅下滑才看得到。
3. **`loading` 共用**：详情拉取与 `playback()` 共用一个 `loading`，解析播放时整页 `disabled(loading)`，观感上像「点了没反应」（次要）。

## Fix

1. **封面整块可点**：`coverPlayHero` 用 `Button` 包住封面；中央 64pt glass `play.fill` 叠层（`tangxin.play.cover`）。`TangxinImage` 仍禁命中，由 Button + `contentShape` 吃手势。
2. **播放条上移**：原 `tangxin.play` 条移到标题/作者下方、标签上方，保证首屏可点。
3. **状态拆分**：`loadingDetail` vs `resolvingPlay`，互不禁用对方的主路径误伤。
4. **标签**：`FlowLayout` 横向换行 Capsule pill（链接标签 accent 浅底；无链接孤儿灰底），去掉竖排大触区蓝链。

## Tests / UI notes

- `scripts/test-tangxin-detail276.py` 静态守卫。
- 既有 `TangxinUITests261` 仍找 `tangxin.play`（条按钮）；封面另有 `tangxin.play.cover`。
- 不改 Tangxin 解析 / CDN / OnlineTransport。

## Build note

CI：`dmm-preview266.yml` 增加 `python3 scripts/test-tangxin-detail276.py`。
