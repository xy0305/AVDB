# Build 318 — 中指通月度精選繼續補齊（2024-01/02 + 2023 部分）

Base: Build 317 / 6882968, `feat/zzt-ranking-317` (PR #7, unmerged).

- `AVDB/Resources/ZhongZhiTongMonthly.json`：53 个月、1206 部（Build 317：44 个月、1026 部）。
- 新增 9 个月（`video_ocr`，YouTube 原片 android client 取流，画面番号 OCR，javdb 精确命中且发行日期在该月 -4 ~ +1 个月内）：
  - 2024-02（26）、2024-01（30）
  - 2023-08（19）、2023-07（24）、2023-06（13）、2023-04（18）、2023-03（14）、2023-02（18）、2023-01（18）
- 合计新增 180 部。识别后已删除本地下载视频与抽帧。
- 部分 SSIS 被 OCR 成 SISS 而未命中 javdb（已丢弃，未猜改）。
- 仍缺：2019-09/11/12、2020-06、2021 若干、2022 全年、2023-09..12、2025-11；2026-08 仍仅 DSOD-001。
- 资料不含任何磁链；图片管线不变。
- Version/plist/packaging/artifact identifiers bumped to 318 (`AVDB-unsigned-1.0.2-318-zzt-more.ipa`, `AVDB-318-*`); workflow also runs on `feat/zzt-ranking-318`.

Validation: `test-zzt-ranking318.py` (new months, ≥53 months, ≥1200 codes, no magnets) plus 313–317 zzt tests.
