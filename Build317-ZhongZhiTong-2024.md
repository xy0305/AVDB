# Build 317 — 中指通月度精選繼續補齊（2024-03～11）

Base: Build 316 / 4380ac2, `feat/zzt-ranking-316` (PR #6, unmerged).

- `AVDB/Resources/ZhongZhiTongMonthly.json`：44 个月、1026 部（Build 316：35 个月、819 部）。
- 新增 9 个月（`video_ocr`，YouTube 原片 android client 取流，画面番号 OCR，javdb 精确命中且发行日期在该月 -4 ~ +1 个月内）：
  - 2024-11（13）、2024-10（20）、2024-09（21）、2024-08（25）、2024-07（19）、2024-06（22）、2024-05（33）、2024-04（28）、2024-03（26）
- 合计新增 207 部。识别后已删除本地下载视频与抽帧。
- 2024-01/02 因时间盒未做完，下一批继续；2019–2023 缺月、2025-11 仍缺（年龄验证 / a123 无转载 / 时间盒）。
- 资料不含任何磁链；图片管线不变。
- Version/plist/packaging/artifact identifiers bumped to 317 (`AVDB-unsigned-1.0.2-317-zzt-more.ipa`, `AVDB-317-*`); workflow also runs on `feat/zzt-ranking-317`.

Validation: `test-zzt-ranking317.py` (new months, ≥44 months, ≥1000 codes, no magnets) plus 313–316 zzt tests.
