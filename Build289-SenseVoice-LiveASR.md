# Build 289 — 实时字幕：精度和速度优先（SenseVoice 默认 + 苹果系统识别降级）

Owner feedback on 288: toast 「设备发热，已切换到 small 模型」, recognition not timely, video stutters.
289 goal: accuracy **and** speed, without starving playback.

## Recognizers
| 选项 (设置 → 实时字幕 → 识别引擎) | Engine | Where | Default |
|---|---|---|---|
| SenseVoice（默认） | SenseVoice-Small int8 (2024-07-17 export) on sherpa-onnx v2.0.1 / onnxruntime CPU, 2 threads, language=ja, ITN on | bundled `LiveModels/sensevoice-small-int8` (~240 MB) + `Frameworks/SherpaOnnxC.framework` | ✅ |
| 苹果系统识别 | iOS 26+: `SpeechAnalyzer` + `SpeechTranscriber` (ja-JP, assets via `AssetInventory`); iOS 17–25: `SFSpeechRecognizer(ja-JP)` with `requiresOnDeviceRecognition = true` | system | fallback |
| Whisper small | WhisperKit 1.1.1 Core ML | bundled | manual only |
| Whisper turbo | WhisperKit large-v3-turbo | **not bundled any more**; on-demand download (huggingface.co → hf-mirror.com) to Application Support/LiveModels, excluded from backup; deletable | manual only |

Whisper models are never loaded/compiled unless picked. The 2025-09-09 SenseVoice export was rejected: it ignored `language=ja` and emitted Chinese/Cantonese for Japanese audio; the 2024-07-17 int8 export transcribes Japanese correctly.

Why sherpa-onnx instead of a Core ML conversion: prebuilt iOS xcframework (device + simulator), C API, int8 CPU decode at ~0.04 RTF on a Linux x86 CPU (7.2 s clip in ~0.3 s, 2 threads). The Core ML EP of onnxruntime does not accelerate int8 graphs; the bench runs a `coreml` provider variant only as a data point.

### Licenses
- SenseVoice-Small model weights: **FunASR Model Open Source License v1.1** (commercial use allowed; requires attribution and keeping the model name/"SenseVoice"). Text: `scripts/live289/FUNASR_MODEL_LICENSE.txt`, also shipped next to the model as `MODEL_LICENSE.txt`.
- SenseVoice code: MIT. sherpa-onnx: Apache-2.0. onnxruntime: MIT. whisperkit-coreml / WhisperKit: MIT.
- Artifacts are fetched and sha256-pinned by `scripts/live289/fetch_live289.py` (Vendor/ is git-ignored).

## Fallback / degradation (`LiveSubtitleGuard`, engine)
- Thermal `serious`/`critical`, Low Power Mode, battery < 20 % → 苹果系统识别 (only if its on-device assets are installed; otherwise stays on SenseVoice and toasts 「已降低识别负载」). Battery < 10 % unplugged → pause.
- SenseVoice falling behind (RTF > 0.7, or ≥ 3 of the last 5 lines with > 2 s latency) → session override to Apple.
- Memory warning while on Whisper → SenseVoice.
- Load failure walks the candidate list (SenseVoice → Apple; Whisper → SenseVoice → Apple).
- SenseVoice BPE output spaces between Japanese characters ("君 のこ とが") are stripped in `LiveText.clean` (ASCII-adjacent spaces kept).
- Toast is a small capsule, auto-hides after 5 s, not over the subtitle line or video centre.

## Anti-stutter
- Recognition, translation, the audio reader thread and model loads run at `.utility` QoS, never on the main thread; one serial recognition worker (concurrency 1).
- 288 VAD chunking and read-ahead kept; read-ahead throttled by thermal state (`fair` ×0.75 min 6 s; `serious`+ ≤ 8 s).
- `LiveHitchMonitor` (CADisplayLink) counts main-thread frame gaps > 50 ms while live subtitles run; summary shown in 模型状态与诊断 (copyable).

## AI 图片增强（封面超分 4xNomosWebPhoto）— 不再受温度限制
Owner request: AI image enhancement must always be allowed. `AICoverEnhanceGuard` no longer reads `ProcessInfo.thermalState`
and the `.hot` verdict / 「设备温度较高，已暂停 AI 增强」 message are removed — both 自动 and 手动 run at any thermal state.
Unchanged: 自动 still skips Low Power Mode and < 20 % battery (unless charging); 手动 always runs; 关 never runs.
Thermal throttling now exists only in live subtitles. (The video LUT's "safe performance" option in NativeLUT.swift is a
separate player feature and was not changed.) Test: `scripts/test-ai-cover289.py` (static + compiled Swift check);
`AICoverPolicyRegression285.swift` updated (auto/manual hot → ok).

## Evidence / tests
- `scripts/test-live289.py` (wiring + version) → 288 → 287 regressions incl. `LiveCoreRegression287.swift` guard checks.
- CI bench `scripts/test-live-bench289.py` (macOS runner): SenseVoice vs Whisper small vs Apple on macOS-TTS (Kyoko) Japanese lines — per-chunk ms, RTF, CER, end-to-end look-ahead/paced/seek; SenseVoice thread/provider variants. Output `evidence-live289/bench/bench289.json`.
- CI simulator `scripts/test-coldload289.py`: fresh install embedding the shipping SherpaOnnxC.xcframework; SenseVoice vs Whisper small cold load + per-chunk latency.
- UI screenshots 17–23 (Apple toast portrait/landscape, failed+retry, settings status, recognizer picker, turbo download row).

## Not measured
- No physical-iPhone numbers (latency, RTF, heat, hitches). GitHub runners are virtualised M1 without ANE/GPU for Core ML.
- SpeechAnalyzer path is compiled but unverified on a device; CI runners may lack ja-JP on-device assets.
- Test speech is synthetic TTS, not film audio.
- The audio reader still opens a second HLS connection (downloads muxed segments) — network contention remains possible on slow links.
