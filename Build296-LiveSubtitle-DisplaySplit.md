# Build 296 — 实时字幕短句不再拼成一长条

## 问题（295 机上截图）
翻译后中文字幕把多句短对话粘成一行，例如：
「来。还有，没有补习班和固定提供师，所以在调查吗？温柔的老师真好啊。我不认为不严格。」
屏上一行过长，好几句同时出现。

## 根因
Build 293 为提高日→中整句质量，对 SenseVoice 相邻 final（间隙 ≤0.85s、合并后正文 ≤64）拼进同一 `LiveSegment` 再整段 MT。条件里 `prevFinal || gap ≤ 0.85` 在已进入 `gap ≤ 0.85` 时恒真，连续短句会被一路拼到 64 字，显示也用整段 `zh`。

## 修复
1. **合并上限**：`adjacentMergeMaxBody` 64→**28**；新增 `adjacentMergeMaxClauses = 2`（合并后 `。？！` ≤2）。石川くん两半句仍合并；第三句不再粘上。
2. **展示拆句**：`caption(at:)` 经 `displaySlice` —— 中文（或无中时的日文）超过 28 字且含 ≥2 个句末时，按字符权重把 `[start,end]` 切开，播到哪句只显示哪句；MT 仍可整段翻译。
3. **不动**：295 拖动拆二路 HLS / 重开黑屏 / 关不灵敏；SenseVoice 默认；预读 20；整句 MT（`LiveMTPrep` 不按句拆译）。

## 回归
- 293：石川くん相邻合并、整句 MT、gap>0.85 不合并。
- 296：三短句仅前两句合并；monster 中文 early/mid 各只露一句；短双语「嗯。好的。」仍整段。
- 294/295 catch-up / seek 策略原样。

## 产物
- CFBundleVersion **296**；`lut4-online296.yml` push；295 → `workflow_dispatch` only。
