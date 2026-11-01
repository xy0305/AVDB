# Build 297 — 字幕音频读取失败提示不再挡画面

## 问题（296 机上截图）
左上角常驻胶囊：「字幕音频读取失败 (open -541478725)，拖动进度可重试」盖住画面；底部双语字幕往往仍在更新。

## 根因
`LiveAudioReader` 连续失败第 4 次时 `onError` 把文案写进 `LiveSubtitleEngine.notice`，且**不走** `toast()` 自动消失；`LiveSubtitleStatusChip` 在 `.running` 时一直显示 `notice`，恢复后也不清。

`-541478725` 多为 FFmpeg `AVERROR_EOF`（open/读流边界），读取侧本就有 1/2/4/8/15s 可中断退避重试，拖动也会经 295 `seekSettled` 重开二路 HLS。

## 修复
1. **不再上屏**：`onError` 只写 `LiveDiagnostics`，并记下 `lastReaderError` 供「复制诊断日志」。
2. **Chip 兜底**：若 `notice` 仍含「字幕音频读取失败」则不渲染。
3. **静默重试保留**：reader 退避 + 拖动重开逻辑不动。
4. **不动**：295 拖动/重开黑屏/关不灵敏；296 短句合并上限与展示拆句；SenseVoice 默认；预读 20。

## 产物
- CFBundleVersion **297**；`lut4-online297.yml` push；296 → `workflow_dispatch` only。

## CI / IPA
- （push 后回填）
