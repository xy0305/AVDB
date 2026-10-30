# LiveModels (build 287 实时字幕)

Populated at build time by `scripts/live287/fetch_models287.py` (CI caches it); the model files are not committed.

| Folder | Source | License |
| --- | --- | --- |
| `openai_whisper-large-v3-v20240930_turbo_632MB/` | argmaxinc/whisperkit-coreml | MIT (OpenAI Whisper weights MIT) |
| `openai_whisper-small_216MB/` | argmaxinc/whisperkit-coreml | MIT |
| `tokenizer-large-v3/`, `tokenizer-small/` | openai/whisper-large-v3, openai/whisper-small | MIT / Apache-2.0 |
| `nllb/NLLBEncoder.mlmodelc`, `nllb/NLLBDecoder.mlmodelc`, `nllb/nllb287_vocab.json` | facebook/nllb-200-distilled-600M @ f8d333a, converted by `convert_nllb287.py` | CC-BY-NC-4.0 (non-commercial) |

Without these folders the app still builds; 实时字幕 then reports 「模型未打包」.
