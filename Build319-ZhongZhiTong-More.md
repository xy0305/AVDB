# Build 319 — 中指通月度精選繼續補齊（2023-09..12 / 2022-01/12 / 2025-11）

Base: Build 318 / 21968a2, `feat/zzt-ranking-318` (PR #8, unmerged).

- `AVDB/Resources/ZhongZhiTongMonthly.json`：60 个月、1394 部（Build 318：53 个月、1206 部）。
- 新增 7 个月（`video_ocr`，YouTube 原片 android client，javdb 精确命中且发行日期在该月 -4 ~ +1 个月内）：
  - 2025-11（38）、2023-12（32）、2023-11（21）、2023-10（33）、2023-09（17）、2022-12（23）、2022-01（24）
- 合计新增 188 部。识别后已删除本地下载视频与抽帧。
- 2022-03/06/07/09 原片 OCR 仅 0–1 条有效番号（画面裁切），未收录；2022-04/05/08 年龄验证下载失败。
- 仍缺：2019-09/11/12、2020-06、2021 若干、2022-03..09、2026-08（仍仅 DSOD-001）。
- 资料不含任何磁链；图片管线不变。
- Version bumped to 319 (`AVDB-unsigned-1.0.2-319-zzt-more.ipa`, `AVDB-319-*`); workflow runs on `feat/zzt-ranking-319`.

Validation: `test-zzt-ranking319.py` plus 313–318 zzt tests.
