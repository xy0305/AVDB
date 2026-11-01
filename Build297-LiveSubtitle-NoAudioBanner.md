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


## 产物上传修复（297b）
- 根因：`lut4-online297.yml` release 的 `upload-artifact` 路径仍写死 **296** IPA 文件名，包步骤已产出 297 IPA（~770MB）但未上传，artifact 只剩 evidence/logs（~58KB）。
- 修复：上传路径改为 `AVDB-unsigned-*.ipa`，并在上传前断言 IPA 存在且 >500MB。

## CI / IPA
- CI: https://github.com/xy0305/AVDB/actions/runs/41270309905 （release=success；产物 ~770MB）
- IPA artifact: https://github.com/xy0305/AVDB/actions/runs/41270309905/artifacts/13068799694
- file `AVDB-unsigned-1.0.2-297-livesub-lut4-online-from269.ipa`
- size 770541308 · sha256 `67a8434ff133fea1e818ed9574660f7ff922b45bf604f840022ba787ed3eb268` · CFBundleVersion 297
- 说明：旧链接 run 41267295821 / artifact 13067364648 只有 ~58KB（上传路径写死 296），已作废。
