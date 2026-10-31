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

Caveats: emulation, not a device run; the device-scenario hang/dip/flip schedule is modelled on the diagnostics;
Apple recognition/translation can't run on Linux; NLLB here is the HF fp32 model (the app ships an int8 Core ML port).
