# Build 294 — 实时字幕读取追帧死循环

## 问题（293 机上诊断，iPad13,4）
- 预读 20s、热状态 0；Whisper small 激活时 ASR 仅 0.31×，64s 音频只入库 2 条。
- 日志约每 10s：`读取落后 6.0–10.6s → 跳到播放点 …`（decoded < playhead−6，冷却 10s）→ `restartReader` → `pipeline.reset` 清空队列。
- seek/打开后二路 HLS 仍在 open/seek 时，decoded 停在播放点附近 → 再次落后 → 死循环；主线程卡顿最长 1566ms，跳变检测可能误判拖动。
- 早期 SenseVoice 曾有 `读取+40s`（健康）；seek 后追帧循环占主导。

## 根因
`LiveSubtitleEngine.tick` 追帧每次 `restartReader` → `pipeline.reset`；`didSeek` 落地后没有追帧宽限；HLS 二路未重建预读前每 10s 再 reset。主线程卡顿可能让外推时钟跳变看起来像 seek。

## 修复
1. **追帧宽限（~22s）**：seek 落地、打开/启动、换源、软/硬追帧后 `armCatchUpGrace`，宽限内不追帧；诊断日志 `追帧宽限 22s（…）`。
2. **软追帧**：落后 <28s 时 `softReopen`（只清 open VAD/partial、升 generation）+ `reader.seek`，保留 finals 队列与已入库字幕；≥28s 仍硬 `pipeline.reset`。
3. **decoded 仍在增长**：近 3s 内 `decodedEnd` 前进则继续等，不追帧。
4. **误判拖动**：跳变阈值 1.5s→2.75s；大卡顿（≥400ms）后 2.5s 内忽略 <8s 的跳变。保留 293 的 `holdForSeek` / `abortIO` / 0.45s debounce。
5. 默认预读仍 20s；不改 homeui / Muse / Sakura。

## 回归
- `LiveCatchUpPolicy`：宽限/冷却/软硬分流/卡顿跳变；`softReopen` 升 generation。
- 293 整句 MT / 相邻合并 / seek hold 仍通过。

## 产物
- CFBundleVersion **294**；`lut4-online294.yml` push；293 → `workflow_dispatch` only。
- 可选 Sakura 下载不变；`AVDB_COVERS_KEY` 注入保留。

## CI / IPA
- （push 后回填）
