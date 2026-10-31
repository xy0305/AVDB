# Build 293 — live subtitle translation components

* **llama.cpp** b12018 (https://github.com/ggml-org/llama.cpp) — MIT License, Copyright (c) 2023-2026 The ggml authors.
  Embedded as `llama.framework` (release asset `llama-b12018-xcframework.zip`, sha256
  `c0c7daf1a710e1849a5b3c5a292e85ff5609d5dd3d64239eb3d23c76dcad03b3`).
* **Sakura-1.5B-Qwen2.5-v1.0** (SakuraLLM, https://github.com/SakuraLLM/SakuraLLM) — CC BY-NC-SA 4.0
  (https://creativecommons.org/licenses/by-nc-sa/4.0/). GGUF Q5_K_S (imatrix) quantisation by shing3232
  (https://huggingface.co/shing3232/Sakura-1.5B-Qwen2.5-v1.0-GGUF-IMX), sha256
  `6722487146c594984e4d222cae0b926c9715ffff712afb5f348b603417c01680`, 1,259,173,504 bytes.
  **Not bundled**: downloaded only when the user taps 下载 in 实时字幕设置. Non-commercial use only; the model is used
  unmodified. Every LLM line is labelled 「机翻」 (machine translation) on screen, as the SakuraLLM README requires.
* Prompt format: Sakura v1.0 (system prompt + 术语表 / glossary prompt), chat history = the previous ≤ 3 subtitle lines.
