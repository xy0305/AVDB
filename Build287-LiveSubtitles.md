# Build 287: 实时语音识别字幕 + 中文翻译 (on-device, during playback)

Results (CI timings, latency tables, screenshots, sha256) are filled in by the report; this file documents the design.

## Pipeline (latency first)
1. **Look-ahead reader** (`LiveAudioReader.swift`): a second, audio-only FFmpeg context on the *same URL + headers*
   (115 / online HLS / AVPlayer+Metal-LUT path / local) — every non-audio stream `AVDISCARD_ALL`, swr → 16 kHz mono
   Float32. It decodes up to `lead` (default 20 s × rate) ahead of the playhead, so lines are recognised and translated
   **before they are spoken** (latency 0 in steady state). Seek → exact-trim re-seek; cached ranges are skipped.
2. **VAD** (`LiveVAD`): 20 ms frames, adaptive noise floor, 0.32 s end-of-speech hangover, 0.2 s pre-roll, max 5 s
   utterance (split at the quietest frame).
3. **Scheduler**: finals in playhead order; when the reader is *not* ahead (after a seek / slow network) the open
   utterance is re-decoded every 0.8 s as a **streaming Japanese partial** (shown in italics with …), then refined.
4. **ASR**: WhisperKit 1.1.1, `openai_whisper-large-v3-v20240930_turbo_632MB` (default), `openai_whisper-small_216MB`
   (degrade tier). Japanese fixed, no timestamps, ≤ 1 temperature fallback, previous line as prompt tokens,
   encoder + decoder on `.cpuAndNeuralEngine`.
5. **MT**: Apple Translation (iOS 26 UI-less session when ja→zh-Hans packs are installed; iOS 18–25 via a hidden
   `.translationTask` host; 2 s timeout) → fallback bundled **NLLB-200-distilled-600M** Core ML (int8, trimmed vocab
   16,982, static 64/48, greedy). 中文 mode shows the Japanese line until the Chinese arrives.
6. **Store/cache**: dedupe (overlap + bigram similarity), hallucination filter, repeat collapse; per-video cache
   (Caches/LiveSubtitles, key = 番号/来源 resume key or progress id, LRU 200 files / 40 MB). Only what was played
   (+ the look-ahead window) is ever generated.

## UI
- Player bottom bar: 「字幕」 menu → 关 / 日文 / 中文 / 双语 + 实时字幕设置… (font size, Japanese scale, position slider +
  on-screen drag, model tier, Apple pack download, look-ahead seconds, latency read-out, cache clear).
- Overlay: 8-way hairline outline + soft shadow, Chinese over Japanese (Japanese smaller, warm white); lifts above the
  bottom controls (118 pt reserve) while the chrome is visible, so it never covers them.
- Guards: thermal serious / Low Power / battery < 20 % → small model with a notice; thermal critical or battery
  < 10 % unplugged → pause with a notice; auto-resume when conditions clear. Pause / rate / seek handled from the
  player clock (any > 1.5 s discontinuity counts as a seek).

## Models (bundled; `scripts/live287/fetch_models287.py`, cached by CI, not in git)
| Model | Size | License |
| --- | --- | --- |
| Whisper large-v3-turbo (2024-09-30) Core ML, argmaxinc/whisperkit-coreml | ~632 MB | MIT |
| Whisper small Core ML | ~216 MB | MIT |
| NLLB-200-distilled-600M int8 Core ML (converted) | ~372 MB | **CC-BY-NC-4.0 (non-commercial)** |
| WhisperKit / argmax-oss-swift 1.1.1 (code) | — | MIT |
