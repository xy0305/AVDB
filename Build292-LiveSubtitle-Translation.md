# Build 292 — 实时字幕翻译质量

（WIP，评测表见下方「结果」一节，随提交更新）

## 改动
1. **翻译前/后处理（所有引擎：Apple 翻译 / NLLB / LLM）** — `AVDB/Services/LiveTranslationPrep.swift`
   - 纯呻吟/喘息行（あぁん、んっ、はぁはぁ…）不翻译、不显示中文；SenseVoice 误判成英文的 “The.” 等跳过。
   - ≤3 假名感叹/应答词（うん/はい/あっ/ええ/ねえ…）与常用套话（いらっしゃいませ/よろしくお願いします/失礼します/お疲れ様…）查表，不调 MT。
   - 断句：按 。？！ 以及句末助词（よ/ね/わ/ぞ + 汉字/片假名开头的新句）拆开逐句翻译，NLLB 不再丢后半句。
   - 片名元数据中的演员名 → 术语表（NLLB 用占位符保护，LLM 用 Sakura 术语表 prompt）。
   - 后处理：去掉原文不支持的句首「现在」；原文是乱码碎片时 NLLB 的套话幻觉（「现在,我知道」「我很抱歉」…）不显示；复读（子,子,子 / 我很害怕,我很害怕）截断；过长输出截断。
2. **可选本机 LLM 翻译（设置 → 实时字幕 → 下载）** — `AVDB/Services/LiveLLMTranslation.swift`
   - Sakura-1.5B-Qwen2.5-v1.0 GGUF Q5_K_S（1,259,173,504 B，sha256 6722487146c5…1680），llama.cpp b12018 xcframework（Metal，全部层上 GPU）。
   - 不随 IPA 打包；huggingface.co → hf-mirror.com 下载，sha256 校验，排除 iCloud 备份；可删除。
   - 上下文：前 ≤3 句（日文 + 已出中文）作为对话历史；KV cache 复用公共前缀。
   - 回退：设备发热（serious+）、低电量模式、电量 <20% 未充电 → Apple/NLLB（恢复 60 s 迟滞）；台词到点时间 < LLM 近期平均耗时 + 0.3 s → 本句走 Apple/NLLB；连续 3 次失败 → 冷却 120 s。
   - 许可：CC BY-NC-SA 4.0 署名见设置页与 THIRD_PARTY/LiveTranslation-292.md；画面上 LLM 译文标注「机翻」。
3. 诊断：新增「译 表/略/LLM/常规」计数与 LLM 状态行。
