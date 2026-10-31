# Build 295 — 拖动卡死 + 退出重开黑屏有声 + 实时字幕关不灵敏

## 问题（294 机上，iPad13,4 M1）
- 拖动进度条仍卡住（293 hold 0.45s / 294 追帧宽限不够）。
- 退出播放器再进：黑屏但有声音。
- 「实时字幕选择关不灵敏」：选「关」后要等一会儿/要点多次。
- 封面云端正常（无关）。

## 根因
1. **Seek 卡死**：293 仅 `holdForSeek`（会话仍占着二路 HLS）；0.45s 后 `reader.seek` 又在播放器自己 seek/rebuffer 时抢带宽 → 主画面冻住。
2. **重开黑屏有声**：`beginRunning` 一就绪就 `reader.start` 打开二路 HLS，和首帧视频抢流；同时 Metal LUT 在 seek/重开后若可见又无新帧，会盖住 AVPlayerLayer 呈黑。

3. **关字幕迟钝**：`mode = .off` 在主线程同步做 `saveCache(force)`（主线程取 pipeline 锁快照，与识别 worker 争锁）+ `stopRunning` + `hitches.stop`；同时 `latencyText` 每 100ms 无条件赋值 → `@Published` 每秒 10 次刷新整个播放器 chrome 与字幕菜单，Menu 里的 Picker 点击常被重绘吞掉。

## 修复
1. **Seek 拆二路**：`didSeek` → `holdForSeek` + **`reader.stop()`** 拆掉 open_input；`PlayerView.seek` / resume 完成回调 `seekSettled`；合并 0.45s 后等播放中/就绪（或 ~2s 超时）再 `ensureReader`→`start`。
2. **首开门控**：`beginRunning` 等到 `playing` 或 1.5s 再开字幕读取。
3. **LUT**：`lut.noteSeek()` 立刻藏 Metal；可见却超过 stall 无新帧 → 回原画（避免黑 MTKView 盖住有声画面）。
4. **关字幕立即生效**：OFF 当拍就清字幕/phase/notice、`reader.stop()`（只置标志）；保存缓存（快照在后台线程取）、worker/ticker/hitch 拆除放下一拍，且有 `modeToken` 防止用户马上又打开时被误关。`latencyText` 仅变化时发布、约 1Hz 更新。菜单从嵌套 `Picker` 改成带勾的独立 `Button`，一点即提交。
5. 保留 293/294：整句 MT、相邻合并、追帧宽限/软追帧；SenseVoice 默认、预读 20。

## 回归
- `LiveSeekPolicy`：coalesce 450ms、mayReopen / mayFirstOpen。
- `seekSettled` / `ensureReader` / `isRunning`；PlayerView 接线；LUT `noteSeek`。
- 294 catch-up / 293 MT 仍通过。

## 产物
- CFBundleVersion **295**；`lut4-online295.yml` push；294 → `workflow_dispatch` only。
- 可选 Sakura 不变；`AVDB_COVERS_KEY` 注入保留。

## CI / IPA
- CI: https://github.com/xy0305/AVDB/actions/runs/41190805828 （全绿；首个 run 41190174281 因历史/封面回归脚本版本号仍写 294 失败，`c4a50f2` 已修）
- IPA artifact: https://github.com/xy0305/AVDB/actions/runs/41190805828/artifacts/13039670138
- IPA: `AVDB-unsigned-1.0.2-295-livesub-lut4-online-from269.ipa`
- size 770538905 · sha256 `27996f29c0440e4b8f59754c724353932056861ca6479183b06da8feefa9ad1f` · CFBundleVersion 295 · covers key present (fp `5cc2a6c8`)
- sourceCommit `c4a50f2c283bb81a09d967e5def6af0d17a77972` · 主改动 `a301063`
- `NativeHLSLUTSurface.swift` 安全哈希已重锁（`test-hls-safety273.py`），strict-runtime 模拟器测试通过。
