# Build 316 — 中指通月度精選繼續補齊

Base: Build 315 / 368d25b, `feat/zzt-ranking-315` (PR #5, unmerged).

- `AVDB/Resources/ZhongZhiTongMonthly.json`：35 个月、819 部（Build 315：31 个月、751 部）。
- 新增 4 个月（`video_ocr`，影片画面/烧录字幕 OCR，javdb 精确命中且发行日期在该月 -4 ~ +1 个月内）：
  - 2021-01（18）、2020-10（21）、2020-05（10，部分）、2020-03（19）
- 2020-05 的 `1PX-485` 为 OCR 把 I 读成 1，javdb 核对 IPX-485（2020-05-13）后收录。
- YouTube 原片仍被机器人检查/年龄验证挡下，画面取自同一影片的转载版本。
- 仍缺：2019-09/11/12、2020-06、2021-02~04/06/07/09/10/12、2022 全年、2023（除 05）、2024-01~11、2025-11；2026-08 仍仅 DSOD-001。
- 资料不含任何磁链；图片管线不变。
- Version/plist/packaging/artifact identifiers bumped to 316 (`AVDB-unsigned-1.0.2-316-zzt-more.ipa`, `AVDB-316-*`); workflow also runs on `feat/zzt-ranking-316`.

Validation: `test-zzt-ranking316.py` (new months, ≥35 months, ≥810 codes, no magnets) plus 313/314/315 zzt tests.
