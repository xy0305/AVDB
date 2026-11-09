# Build 320 — 中指通月度精選繼續補齊（评论转录 + javdb）

Base: Build 319 / 6b4e2a8, `feat/zzt-ranking-319` (PR #9, unmerged).

- `AVDB/Resources/ZhongZhiTongMonthly.json`：67 个月、1563 部（Build 319：60 个月、1394 部）。
- 新增 7 个月（`youtube_comments`：官方月度片评论区番号列表，javdb 精确命中且发行日期在该月 -4 ~ +1 个月内）：
  - 2022-08（41）、2022-06（23）、2022-03（20）、2022-07（18）、2022-09（17）、2021-09（26）、2021-12（24）
- 合计新增 169 部。
- 年龄验证挡下的 2019-09/11/12、2020-06、2021-02/03/04/06/07/10、2022-04/05：无法取评论/原片；a123tv 搜索无命中；hires+右下裁切 OCR 对 2022-03/06/07/09 仍几乎无码。
- 资料不含任何磁链。Version bumped to 320。

Validation: `test-zzt-ranking320.py` plus 313–319 zzt tests.
