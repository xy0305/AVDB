# Build 293 — 整句保留翻译 + 拖动进度条卡死

## 问题
1. **半句丢失（iPad13,4 截图）**：日文 overlay「いいかい、石川くん。君ももう3年目だろ。」硬字幕「听好了 石川君 你已经工作3年了吧」，我们的中文只有「你也是第3年吧。」——只剩后半句。
2. **拖动进度条卡死**：开实时字幕后反复拖 scrubber，画面卡住不恢复，需再拖一次才动。

## 根因
1. **翻译 / 展示拆句**
   - 292 `LiveMTPrep.pieces` 按 `。？！` / 句末助词拆成多段分别 MT 再 `join`；VAD 也常在 `。` 处静音切段。
   - 两条相邻 final 各自成 `LiveSegment`，`caption(at:)` 只显示当前段 → 屏上中文只剩后半；或 overlap 扩写日文后 `insert` 返回 `nil`、中文未立刻重译。
2. **Seek 与字幕二路 HLS**
   - 每次 `didSeek` / tick 跳变立刻 `restartReader` → `av_seek_frame`；interrupt 回调只看 `interrupted`（仅 `stop`），seek 时 `av_read_frame` 可堵到 `rw_timeout` 15s。
   - 字幕二路连接与播放器抢带宽；快速 scrub 连续 reopen/seek → 主画面卡住。

## 修复
1. **整句 MT**：`plan` 对整句只产一个 `.mt(s)`，不再按句拆译。
2. **相邻合并（仅 SenseVoice）**：VAD 在 `。` 后 ≤1.5s（或间隙 ≤0.85s）的下一段拼进同一 `LiveSegment`，清空 zh 并 **返回该段** 触发重译；overlap 日文变长时同样返回以便重译。对话轮次（无句末标点、约 1s 间隔）不合并。
3. **Seek**：`abortIO` / `holdForSeek` —— interrupt 在 pending seek / hold 时中止 I/O；读失败且正在 seek/hold 时不拆 session；`didSeek` 防抖 0.45s（先 hold 停读，playhead 更新用缓存字幕，落地一次 `restartReader`）。

## 回归
- `いいかい、石川くん。君ももう3年目だろ。` → 一个 MT unit；两段 insert 合并为含两半的日文。
- いま strip / glossary / moan / 套话表仍通过。
- 6 片 MissAV ASR 多句行（含 ≥1 个 `。` 且后有内容）：见评测 `multi_clause293.json`；293 起一律整句保留（不再拆）。

## 产物
- CFBundleVersion **293**；`lut4-online293.yml` push；292 → `workflow_dispatch` only。
- 可选 Sakura 下载不变；不改最高画质；`AVDB_COVERS_KEY` 注入保留。
- IPA：`/workspace/avdb-ipa/out293a/`（CI 完成后）。
