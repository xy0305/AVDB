# Build 314 — 中指通月度精選補齊歷史月份

Base: Build 313 / 65cf849, `feat/zzt-ranking-313` (PR #3, unmerged).

- `AVDB/Resources/ZhongZhiTongMonthly.json` 更新（`updated_at` 2026-11-09）：23 个月、606 部。
  - 新增 **2023-05**（「超神級共演一部接一部!!最頂的中指通五月作品精選!! #再見了相澤南」）19 部，来源：冰楓論壇 skghner 日誌 `https://bingfong.com/blog-296530-5956.html`（2023-06-03 发布）。全部番号已在 javdb 核对（发行 2023-04-25 ~ 2023-06-22，女优与清单一致）。原帖 `SSIS-703 凪光` 与 javdb（SSIS-703 = 有栖花あか）不符，已剔除。
  - 2024-12 ~ 2026-10 保持 Build 313 的资料（2026-08 仍只有标题提到的 DSOD-001）。
- 仍缺：2025-11，以及 2024-11 及更早的大部分月份（2021-01 ~ 2024-11 除 2023-05 外）。这些月份的影片只在画面上显示番号，口播/字幕/简介/置顶留言都没有番号，公开论坛也找不到完整清单；不依女优或剧情猜番号。
- 月份选择器改为「年份 + 月份」两个菜单（`zzt-year-picker` / `zzt-month-picker`），年份显示该年月数；月份信息区显示完整「YYYY 年 M 月」。`ZZTCatalog.years` 按年分组（新到旧）。
- 资料不含任何磁链；图片管线不变。
- Version/plist/packaging/artifact identifiers bumped to 314 (`AVDB-unsigned-1.0.2-314-zzt-history.ipa`, `AVDB-314-*`); workflow also runs on `feat/zzt-ranking-314`.

Validation:
- `python3 scripts/test-zzt-ranking314.py`: coverage (≥23 months, 2023-05 present, ≥3 years, ≥600 codes, per-month https source, no duplicate codes, no magnets) and year/month picker wiring.
- `python3 scripts/test-zzt-ranking313.py`: data contract + executable Swift catalog tests, now including year grouping.
- Existing release regression scripts retained; only build/artifact assertions updated.
