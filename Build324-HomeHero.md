# Build 324 — 首页大图卡（参考截图）

Base: Build 323 / 592b6e2, `feat/player-chrome-323` (unmerged). MARKETING 1.0.2, build 324.

首页「佳片推薦」轮播按参考截图的样式重做融入方式；首页其余结构（搜索、快捷入口、最新上架、TOP250 横幅、近期磁鏈、我的关注）全不变：

- 大图卡片化：横版小横幅（200 pt 高、下一张露边）改为竖版大卡。宽度 = 内容宽 − 左右边距（与下方分区卡片对齐），高按海报 3:4 比例（宽 × 4/3，iPhone 上限 640、iPad 上限 560），圆角 16 与其他卡片一致；海报走 `frontPoster` 正面封套裁切完整显示，不再横裁。
- 背景融入：当前海报的模糊版（blur 28、saturation 1.25、opacity 0.55）垫在卡片后方，向下多延 150 pt 并渐隐进 LiquidGlass 页面背景；换页时交叉淡入淡出，颜色随海报变。
- 文字精简：图上只压一行「番号 + 标题」（底部渐变 scrim 上），日期、简介、评分星行、播放按钮全部去掉（详情页都有）；卡片下方原来的标题 + 星行删除，改为居中圆点指示。
- 行为不变：约 4 秒自动翻页、拖拽暂停复位、点卡进详情、分区标题（佳片推薦 / 期间 chip / 往期）不变。

Tests: `scripts/test-home-hero324.py` (static); version asserts → 324;
`scripts/package-lut324.py` → `AVDB-unsigned-1.0.2-324-home-hero.ipa`; workflow artifacts `AVDB-324-*`.
