# Build 315 — 中指通月度精選畫面辨識補齊

Base: Build 314 / fc7045f, `feat/zzt-ranking-314` (PR #4, unmerged).

- `AVDB/Resources/ZhongZhiTongMonthly.json`：31 个月、751 部（Build 314：23 个月、606 部）。
- 新增 8 个月，番号读取自每月精選影片画面上的番号字卡或烧录字幕（OCR），每个番号都在 javdb 精确命中，且发行日期落在该月 -4 ~ +1 个月内；不合格的一律剔除（另列于资料整理记录）。`source_type` = `video_ocr`，`source`/`video` = 该月 YouTube 影片：
  - 2021-11（19）、2021-08（24）、2021-05（29）
  - 2020-12（19）、2020-11（22）、2020-09（18）、2020-08（8，部分）、2020-07（6，部分）
- 说明：YouTube 原片多数需登入年龄验证或被机器人检查挡下，画面取自同一影片的转载版本；2020 年影片的番号只出现在字幕里，转载版有广告遮挡，2020-07/08 只读到部分番号。
- 排行页 `sourceLabel` 新增 `video_ocr`：「番号来自影片画面/字幕文字辨识，已用资料库核对（可能不完整）」。
- 仍缺：2019-09/11/12、2020-03/05/06/10、2021-01~04/06/07/09/10/12、2022 全年、2023（除 05）、2024-01~11、2025-11；2026-08 仍仅 DSOD-001。
- 资料不含任何磁链；图片管线不变。
- Version/plist/packaging/artifact identifiers bumped to 315 (`AVDB-unsigned-1.0.2-315-zzt-ocr.ipa`, `AVDB-315-*`); workflow also runs on `feat/zzt-ranking-315`.

Validation:
- `python3 scripts/test-zzt-ranking315.py`: OCR months present with YouTube source, ≥31 months, ≥740 codes, label wired.
- `test-zzt-ranking313.py` (data contract + Swift catalog tests) and `test-zzt-ranking314.py` accept `video_ocr`.
