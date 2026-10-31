# Build 291 — live subtitles: missed lines (CAWB-044 ~1 min), restart loop, bogus Apple switch, main-thread work

## Root causes (from the user's 290 device diagnostics: iPhone14,7 · iOS 27.2 · thermal 2)
1. **Restart loop (`start target=…` every 20–60 s).** 289/290 `LiveSubtitleGuard` handed SenseVoice to Apple at
   thermal ≥ serious; a phone flapping fair↔serious made `checkGuard()` call `start()` on every flip. `start()` =
   stop reader + new `LivePipeline` from the *last saved* cache (saved only every 8 lines) + reopen the HLS stream at the
   playhead → queued utterances and up to 7 recent lines dropped, 2–3 s of audio never read per restart.
2. **"late 5/5 → apple" at RTF 0.05.** `checkPerformance()` judged "late" as `playhead − speechEnd > 2 s`, i.e.
   wall-clock vs playback. That is dominated by the *source*: the reader's audio arriving late (2nd HLS connection,
   reopen after each restart, and pacing against a playhead that only moved when the main actor ticked — an 8 s main
   hang froze the reader at stale playhead + lead). A recognizer switch cannot fix that, and caused another restart.
3. **Late lines were silently dropped.** `caption(at:)` only showed a line inside `[start, end+0.8]`; a line ready
   after that window never appeared live ("people speak, no subtitle").
4. **VAD under background music.** The adaptive floor could climb to −20 dB; after ~60 s of BGM speech over the music
   no longer cleared floor+10 dB.
5. **Crash** (289/290): after a max-length split, if the carried remainder started > 0.12 s after the last voiced frame,
   `prefix(negative)` trapped the reader thread (reproduced on CAWB-044 audio and in `LiveCoreRegression291`).
6. **Repeat filter** dropped real repeated short lines (「気持ちいい」×2) for SenseVoice (it was meant for Whisper).
7. **Reader gave up** after 3 failed sessions until the next manual seek (rest of the video without subtitles).
8. **Stale preference:** 288's `small` default could resurface; 291 uses a fresh key and never migrates Whisper.

### Main-thread work removed / measured
- Per-video subtitle cache JSON decode moved off the main actor (`beginRunning` used to `cache.load` on main).
- `LiveDiagnostics.log` wrote the whole log file atomically on the caller (often main) on every line → coalesced on a
  utility queue.
- AI-cover disk-cache hits were read + decoded lazily on the main thread at first draw (2–4K HEIC/JPEG) → read and
  `preparingForDisplay()` off-main.
- The latency ledger (sorted on main 10×/s) is bounded to 300 records.
- `LiveHitchMonitor` no longer counts gaps while the app is inactive (lock screen / Control Center / app switcher /
  PiP — the 8351 ms worst case is consistent with that) and logs every hitch > 400 ms with time + engine state
  (`主线程卡顿 HH:mm:ss 1234 ms · sensevoice 运行中 队列 0 读取 +7.8s`), so the next report pinpoints the source.
  Model load, NLLB load, Core ML AI-cover upscale and cloud I/O were already off-main (detached / actor).

## Fixes
- Heat / Low Power / low battery only throttle the read-ahead; SenseVoice stays. Whisper (manual) → SenseVoice when
  hot; only *critical* → Apple. Recognizer changes are **hot swaps** (reader, VAD, queue, lines kept); return from a
  step-down needs 120 s below the trigger (hysteresis). Every `start()` logs its reason.
- Same title re-resolved (new URL/headers) → only the reader reopens; pipeline/models kept.
- Lateness split per line: `sourceLag` (audio arrived late) vs `computeMs` (queue + ASR). Auto-switch only when
  compute-bound (RTF > 0.7, or ≥ 3/5 lines with compute > 2 s and a backlog ≥ 3).
- Late-but-valid lines are shown from their arrival for 1.5–3.5 s (≤ 8 s stale); newer lines win.
- Reader paces on an extrapolated playhead; > 6 s behind → jumps to the playhead (≤ 1×/10 s); reopen starts 1.5 s
  before the playhead; infinite retry with 1/2/4/8/15 s back-off; reads the **lowest-bandwidth HLS variant** (audio is
  identical; 360p ≈ 1.1 Mb/s vs 720p ≈ 2.8 Mb/s on MissAV); accepts disguised segment extensions (`extension_picky=0`).
- VAD floor ceiling −46 dB / threshold ceiling −36 dB; split crash fixed; repeat filter Whisper-only.
- Diagnostics: `分段 块… 语句… 过短… 识别空… 过滤… 合并… 失败… 入库… 翻译…/失败… 显示… 迟到…(源…/算…) 过期丢弃… 重置丢弃… 过时结果…`
  plus `重启 · 热切换识别器 · 读取追帧 · 读取重连 · 读取进度`.

## Replay evaluation (`scripts/live291/replay`)
Shipping `LiveSubtitleCore.swift` (290 = git `7532224`, harness-only crash guard so it can finish; 291 = this build) +
the real SenseVoice-Small int8 via sherpa-onnx C API on Linux, engine emulated on a virtual clock, compute × 0.7
(box RTF 0.086 → device ≈ 0.06). Scenario *device* = the user's 290 conditions: thermal flips every 20–60 s, one
8.35 s main hang at 62 s + 1–3.5 s hangs, read-ahead 8 s, source throughput dips (0.6× for 30 s at 50 s, 15 s every
100 s), 2.5 s HLS reopen. Same schedule for both versions. *clean* = none of that.

**CAWB-044 (0–600 s), reference = offline oracle** (silero VAD + same SenseVoice, 78 utterances with text):

| | coverage | reader gap | VAD | queue dropped | empty/filtered | lost restart/dedupe | not shown (late) | onset p90 | restarts |
|---|---|---|---|---|---|---|---|---|---|
| 290 device | 80.8 % | 0 | 5 | 2 | 1 | 2 | 5 | +3.03 s | 15 |
| 291 device | 89.7 % | 0 | 5 | 0 | 2 | 0 | 1 | +1.60 s | 0 |
| 290 clean | 87.2 % | 0 | 5 | 0 | 2 | 3 | 0 | −0.08 s | 0 |
| 291 clean | 91.0 % | 0 | 5 | 0 | 2 | 0 | 0 | −0.11 s | 0 |

At ~1 min (54.9–77.2 s) 290 lost 「洗濯物に匂いがつかないかな」「やっぱり四発目は」「三髪目より」「気持ちいいな」 (late → never
shown); 291 shows all four (0–5 s late during the 8.35 s hang). Remaining misses: very short interjections (あ？/う？).

**MissAV IPZZ-961 (中文字幕, hard subs), 0–600 s**, reference = OCR of the burned-in Chinese subtitles (32 cues),
ours = SenseVoice → NLLB-200-distilled-600M (HF, same model family as the app's Core ML NLLB):

| | coverage (caption on screen during cue) | matched (zh char-F1 ≥ 0.3) | display − cue start (median) | zh char-F1 (random baseline) |
|---|---|---|---|---|
| 290 device | 81.3 % | 56.3 % | −0.59 s | 0.276 (0.090) |
| 291 device | 100 % | 59.4 % | −1.27 s | 0.252 (0.114) |
| 290 clean | 100 % | 62.5 % | −1.31 s | 0.266 (0.113) |
| 291 clean | 100 % | 62.5 % | −1.28 s | 0.268 (0.097) |
Negative = our line appears before the hard-sub cue (look-ahead; fan subs are timed late).

**MissAV START-617 (中文字幕 page, 0–600 s)** — OCR found no burned-in subtitles in this stream (only the actress
name card), so the reference is the offline oracle (56 utterances with text):

| | coverage | VAD | queue dropped | empty/filtered | lost restart | onset p90 | restarts |
|---|---|---|---|---|---|---|---|
| 290 device | 82.1 % | 3 | 1 | 4 | 2 | +0.86 s | 15 |
| 291 device | 85.7 % | 1 | 0 | 7 | 0 | −0.20 s | 0 |
| 290 clean | 83.9 % | 5 | 0 | 4 | 0 | +0.18 s | 0 |
| 291 clean | 85.7 % | 1 | 0 | 7 | 0 | −0.21 s | 0 |
(JUR-879 中文字幕 was tried first: its stream has no burned-in subtitles either.)

Caveats: emulation, not a device run; the device-scenario hang/dip/flip schedule is modelled on the diagnostics;
Apple recognition/translation can't run on Linux; NLLB here is the HF fp32 model (the app ships an int8 Core ML port).


## 追加验证：MissAV 5 部带硬字幕作品（0–600 s，290 vs 291）

参考 = 画面内中文硬字幕 OCR（rapidocr，1–2 fps，合并同一句碎片，去掉水印/出品/主演等非对白行）。
回放 = 真实 SenseVoice + 真实 290/291 LiveSubtitleCore，虚拟时钟，算力系数 0.7，lead 8 s；device 场景含发热抖动/主线程卡顿/读流停顿，clean 场景无扰动。
翻译 = NLLB-200-distilled-600M（与 App 同系列）。zh-F1 = 中文字符级 F1（我们的译文 vs 硬字幕）。
覆盖 = 硬字幕出现时屏幕上有我们的字幕（±1 s/+1.5 s 窗口）；起始 = 我们显示时间 − 硬字幕起始（中位/p90，s；OCR 1 fps 精度约 ±1 s，硬字幕本身常晚于开口）。

| 作品 | 场景 | 句数 | 覆盖 290→291 | 匹配(F1≥0.3) | zh-F1 均值 | 起始 中位/p90 | 重启 |
|---|---|---|---|---|---|---|---|
| JUR-857 | device | 96 | 85.4% → **97.9%** | 31.2% → 37.5% | 0.250 → 0.261 (随机 0.054) | -1.23/+0.33 → -1.66/-0.09 | 16 → 0 |
| JUR-857 | clean | 96 | 100.0% → **100.0%** | 43.8% → 41.7% | 0.278 → 0.276 (随机 0.060) | -1.76/-0.14 → -1.82/-0.14 | 1 → 0 |
| ADN-801 | device | 112 | 88.4% → **98.2%** | 26.8% → 37.5% | 0.241 → 0.249 (随机 0.056) | -1.92/+0.82 → -2.34/-1.20 | 16 → 0 |
| ADN-801 | clean | 112 | 96.4% → **98.2%** | 33.9% → 37.5% | 0.252 → 0.252 (随机 0.046) | -2.08/-0.46 → -2.46/-1.20 | 1 → 0 |
| HMN-898 | device | 125 | 82.4% → **97.6%** | 23.2% → 26.4% | 0.206 → 0.185 (随机 0.047) | -1.48/+1.20 → -2.21/-0.42 | 16 → 0 |
| HMN-898 | clean | 125 | 98.4% → **100.0%** | 26.4% → 28.8% | 0.204 → 0.198 (随机 0.045) | -1.80/-0.00 → -2.30/-0.68 | 1 → 0 |
| IPZZ-912 | device | 100 | 92.0% → **99.0%** | 31.0% → 38.0% | 0.212 → 0.225 (随机 0.055) | -1.26/+0.15 → -1.58/-0.22 | 16 → 0 |
| IPZZ-912 | clean | 100 | 99.0% → **99.0%** | 38.0% → 39.0% | 0.225 → 0.230 (随机 0.056) | -1.56/-0.30 → -1.54/-0.26 | 1 → 0 |
| CAWD-989 | device | 111 | 85.6% → **96.4%** | 27.9% → 32.4% | 0.207 → 0.215 (随机 0.048) | -1.73/+0.42 → -1.84/+0.19 | 16 → 0 |
| CAWD-989 | clean | 111 | 95.5% → **96.4%** | 29.7% → 32.4% | 0.206 → 0.214 (随机 0.048) | -1.76/+0.13 → -1.91/-0.01 | 1 → 0 |

**汇总（5 部 device）**：覆盖 290 平均 86.8% → 291 平均 97.8%；重启 16 → 0；p90 起始 +0.58 s → −0.35 s。clean 场景 290 已接近 98%，291 持平或略升——即 290 的漏字幕主要来自 device 场景（重启丢队列、迟到丢弃），与 CAWB-044 结论一致。
匹配 F1 均值 0.19–0.28，远高于随机配对基线 0.04–0.06，说明内容基本对得上；绝对值偏低主要因为 ①ASR 对短句/喘息/背景音乐误识 ②NLLB 直译生硬 ③硬字幕为意译+分句不同。

### 翻译生硬示例（291 clean，时间点 s；「硬字幕」= OCR 原文，「建议」= 人工参考译法）

- **JUR-857**
  - 49 s そろそろ行くよ、夜ご飯どうする？ → 我们：「现在我们要去.」 / 字幕：「我差不多该走了哦 / 晚饭怎么办？」（后半句被丢，"现在"多余）
  - 199 s いちかごめん → 「我很抱歉.」 / 「一花 对不起」（人名丢失，语气过正式）
  - 434 s あんたが働けば → 「你必须工作.」 / 「（只要你去工作）那家伙的债务就能减轻」（条件句译成命令句）
- **ADN-801**
  - 96 s いらっしゃいませ → 「现在你来了.」 / 「欢迎光临」（固定用语直译错）
  - 37 s 怖い顔してますよ → 「我很害怕,我很害怕.」 / 建议「你脸色好吓人哦」（主语与意思都错，且重复；该处硬字幕已换到下一句）
  - 23 s すみません遅れちゃって → 「谢谢你,对不起,我迟到了.」（ASR 把おはようございます识别成碎片，NLLB 补出"谢谢你"）
- **HMN-898**
  - 21 s 箱根ね、いいね… → 「子,子,子,子,子…」 / 「箱根啊真不错呢」（NLLB 复读退化，5 部中共 4 行）
  - 59 s わかった、気をつけてね → 「现在,你必须要小心.」 / 建议「知道了，路上小心」（硬字幕此处已是下一句）
  - 121 s 突然ごめんね → 「我突然道歉.」 / 建议「突然打扰，抱歉啦」
- **IPZZ-912**
  - 278 s お前の頑張り次第だ → 「根据你之前的努力.」 / 硬字幕「好好表现」
  - 292 s （ASR 碎片 ももせロ）→ 「现在,我知道.」 / 「看着镜头」（短碎片被 NLLB 幻觉成固定句）
- **CAWD-989**
  - 87 s じゃ、よろしくお願いしますよ → 「我可以这样做.」 / 「那就拜托您了哦」
  - 107 s 失礼します → 「我很抱歉.」 / 硬字幕「慢走慢走 / 是」（场景用语直译错）
  - 115 s うんうん → 「现在,我知道.」 / 应为「嗯嗯」（硬字幕此处已是下一句「游泳部吗？」）

**系统性问题（下一版可改，非 291 范围）**：291 显示行中 20–36% 以「现在」开头（NLLB 把句首语气词/ASR 碎片译成"现在"），「现在,我知道.」单独出现 11–41 次/部；建议 ①≤3 个假名的感叹/应答词（うん、はい、あっ）走小词典或直接不翻 ②对译文做复读检测（同一 1–3 字重复 ≥5 次则回退原文/截断）③去掉无对应原文的句首「现在,」④固定寒暄语（いらっしゃいませ、よろしくお願いします、失礼します）走短语表。
