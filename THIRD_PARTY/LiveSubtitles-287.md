# Build 287 live subtitles — third-party components

- **WhisperKit** (argmaxinc/argmax-oss-swift 1.1.1) — MIT License, Copyright (c) 2024 Argmax, Inc.
- **Whisper Core ML models** (argmaxinc/whisperkit-coreml: openai_whisper-large-v3-v20240930_turbo_632MB,
  openai_whisper-small_216MB) — MIT; derived from OpenAI Whisper weights (MIT, Copyright (c) 2022 OpenAI).
- **Whisper tokenizers** (openai/whisper-large-v3, openai/whisper-small on Hugging Face) — MIT / Apache-2.0 model cards.
- **NLLB-200-distilled-600M** (facebook/nllb-200-distilled-600M @ f8d333a098d19b4fd9a8b18f94170487ad3f821d) —
  Creative Commons Attribution-NonCommercial 4.0 (CC-BY-NC-4.0). Converted to Core ML with a trimmed vocabulary and
  int8 weights by scripts/live287/convert_nllb287.py. Non-commercial use only; replace with a permissively licensed
  model before any commercial distribution.
- **Apple Translation** framework (system, iOS 18+), used when the user has installed the ja / zh-Hans packs.
