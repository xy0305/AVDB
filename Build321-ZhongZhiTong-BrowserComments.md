# Build 321 — 中指通月度精選繼續補齊（浏览器评论誊写）

Base: Build 320 / 478eac0, `feat/zzt-ranking-320` (PR #10, unmerged).

- `AVDB/Resources/ZhongZhiTongMonthly.json`：79 个月、1784 部（Build 320：67 个月、1563 部）。
- 新增 12 个月（`youtube_comments`，用户浏览器登录后誊写的官方月度片评论番号；javdb 精确命中且发行日期在该月 -4 ~ +1 个月内）：
  - 2021-10（28）、2022-04（26）、2022-05（26）、2021-06（25）、2021-03（21）、2021-02（19）、2021-04（19）、2021-07（18）、2020-06（11）、2019-11（10）、2019-09（9）、2019-12（9）
- 合计新增 221 部。
- 丢弃：2021-06 IPX-525/MIMK-078（日期窗外）、「089 佐知子」无厂牌前缀不收录；2021-03 SSIS-024（javdb 无此番号，疑手误）；2020-06 SSNI-241（日期窗外）。
- 2019-09 素人号 300MIUM/200GANA/300MAAN → javdb 标签 MIUM/GANA/MAAN（去频道前缀）后精确命中。
- 仍仅 2026-08 为标题单部（DSOD-001）。Version bumped to 321。

Validation: `test-zzt-ranking321.py` plus 313–320 zzt tests.
