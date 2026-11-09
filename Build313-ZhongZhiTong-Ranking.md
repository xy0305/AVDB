# Build 313 — 排行加入「中指通月度精選」

Base: Build 312 / 8a83917, `feat/home-load-312` (PR #2, unmerged).

- 排行榜「来源」菜单新增 `中指通 → 每月作品精選 · 按月份`，打开 `ZhongZhiTongRankingView`。
- 月份选择器（新到旧），每月按影片介绍顺序列出番号；显示该月影片标题、YouTube 原片与番号来源链接。
- 每个番号经现有 `MissAVMetadata` → `JavDBSDK.exactMovie` 精确番号匹配，命中后封面/详情走正常 `MoviePosterCard` / `MovieDetailView`；未命中显示番号 + 女优，并保留「重试 AVDB 匹配」和手动核对路线。来源图片从不作为封面。
- 资料：`AVDB/Resources/ZhongZhiTongMonthly.json`（随安装包，离线可用）。启动后尝试读取 `raw.githubusercontent.com/xy0305/AVDB/main/AVDB/Resources/ZhongZhiTongMonthly.json`；只有严格校验通过且 `updated_at` 不旧于现有资料时才替换，并原子写入 Caches/ZhongZhiTong313。失败/格式错误保留安装包资料。
- 资料不含任何磁链。
- ImageLoader、缩略图尺寸、HQ 预取与图片缓存策略不变。
- Version/plist/packaging/artifact identifiers bumped to 313; workflow also runs on `feat/zzt-ranking-313`.

Validation:
- `python3 scripts/test-zzt-ranking313.py`: data contract (month/code format, newest first, no magnets), wiring assertions, plus executable Swift tests (`scripts/ZZTCatalogTests313.swift`) for strict decode, ordering, offline bundle, remote refresh + cache, garbage rejection and no downgrade.
- Existing release regression scripts retained; only build/artifact assertions updated.
