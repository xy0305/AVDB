# Build 325 — 首页沉浸式改版（参考截图）

Base: Build 324 / 5b90021, `feat/home-hero-324` (unmerged). MARKETING 1.0.2, build 325. Branch `feat/home-immersive-325`.

用户认为 324 首页（搜索栏 + 彩色方块图标 + 带边距 3:4 大卡）不好看，要求按参考截图的风格改。
方案先与 Muse（muse.ai）讨论得出（分阶段计划的第 1+2 阶段），再按商定的规格落地；
底部 7 个 Tab 合并为 3 个属于后续阶段，本次**刻意不做**，7 个 Tab 及其导航全部保留。

## 改了什么

1. **全出血大图轮播**（替换「佳片推薦」标题 + 带边距 3:4 卡）：宽 = 屏宽，无圆角无边距，延伸到状态栏下；
   高 = clamp(W×1.15, 430, 560)，iPad（W≥768）600。aspectFill，竖向锚点约 22%（保住人脸）。
   图源走列表正面封套（ListCoverPolicy / loadPoster 裁切）+ VisibleHQ 高清升级，预取后 2 张；
   解码宽度 < 500 px（或横图）改为内嵌卡模式（边距 P、圆角 20、模糊铺底 + aspectFit 海报），不硬拉糊图。
   - Scrim：底部 35%→100%（0.35→0、0.62→0.18、0.82→0.45、1.0→0.66 黑），顶部 0.28 黑 110 pt 渐隐。
   - 文字块左对齐 x=P（W<380 为 16，否则 20，iPad 24），间距 6：番号+标题 23 bold 白一行带柔阴影；
     发行日 13 medium 白 72%；简介 13 regular 白 85% 最多两行（为空则不显示）。简介不在列表快照里，
     对当前和下一张懒加载 movieDetail（/api/v4/movies/{id}）并缓存，绝不阻塞大图。
   - 圆点为独立层（不在文字 VStack 里），左下 x=P、距底 16；文字块在圆点上方 10。未选 6×6 白 45%，
     选中 18×6 白胶囊，间距 5，弹簧动画；1 张时隐藏圆点且不自动播放；>9 张窗口化为 9 个。
   - 行为：5 s 自动播放、0.6 s easeInOut 交叉淡入；Ken Burns 1.0→1.05 / 5.6 s 线性（每页重置）；
     按住/拖动、后台、Reduce Motion（同时关 Ken Burns）、VoiceOver、离开首页或滚出画面时暂停。
     手动翻页弹簧（response 0.38、damping 0.88），翻页后计时重启。点击进详情。
     下拉拉伸（scale 1+min(offset,120)/heroH），上滑视差（图 y = offset×0.45），文字/圆点在前 120 pt 淡出。只动 transform/opacity。
   - 「往期」入口保留为大图左上角的玻璃小胶囊（往期 · 期数日期 ›）→ PastRecommendView（期数选择照旧）。
2. **暖色氛围深色背景**（替换浅灰 LiquidGlass 背景）：当前海报 32×32 平均色 → HSB，S 夹到 [0.25,0.45]、
   B 夹到 [0.16,0.22] 为 base；竖向渐变 0→base、0.45→base(B×0.55)、0.75 起 #14100D；换页 0.8 s 交叉淡入；
   回退 base #2A2019；Reduce Transparency → 纯 #14100D。首页文字：主白、次白 62%、三级 40%、分隔白 10%；
   唯一强调色 #FF8A3D（按下 #E5772A），首页彩虹色全部去掉。首页根视图强制深色（材质/占位按深色渲染），
   首页根可见时状态栏为浅色；推入的页面与其他 Tab 维持原有浅色外观。
3. **快捷入口**：12 个彩色方块 → 12 个玻璃圆钮（同样 12 个目的地），横向滚动，手机首屏 5 个 + 第 6 个露边；
   每项宽 60（W≤375 为 56），玻璃圆 52（小屏 48），SF Symbol 22 semibold 白 92%，下方 4 pt 11 medium 标签。
   玻璃配方：ultraThinMaterial + rgba(20,16,13,0.32) + 0.5 pt 白 16% 描边 + 强调色 10% 染色。按下 0.92 / 0.12 s + 轻触觉。上边距 18。
4. **内容分区 → 横向海报栏**（替换首页 3 列网格）：最新上架、近期磁鏈更新、我的關注；TOP250 横幅改为同风格深色卡。
   标题 17 bold 白，右侧 26×26 圆（白 10%）+ chevron.right 13 semibold，44 pt 热区 → 原「全部」页面；「換一組」保留为标题栏小文字按钮。
   卡片宽 = clamp((CW−2P−24)/2.75, 108, 132)（iPad clamp(/4.6, 132, 156)），高 = 宽×1.5（2:3），圆角 12 连续、
   0.5 pt 白 8% 描边、黑 25% r10 y4 阴影，按下 0.97 弹簧；下方 6 pt 间距，番号+标题 12 medium 一行 + 日期 11 次级色，固定 34 pt 高。
   加载中同尺寸微光占位；首载失败显示 film.stack，点按重试。分区上间距 26（第一个 22）。卡图仍走 HQ/正面封套 + HomeHQPosterPrefetch。
5. **搜索**：首页顶部搜索栏移除；新增 58×58 玻璃圆形搜索钮（magnifyingglass 21 semibold 白，黑 35% r16 y6 阴影），
   悬浮在大图右上（状态栏下、右边距 P），滚动后略微变淡但始终可点；打开 SearchView（键盘自动聚焦，同前）。
   扫码图标（barcode.viewfinder）移入搜索页输入框内。
6. **Tab 栏**：7 个 Tab 与 AVDBNativeTabBar 机制不变；改为深暖色玻璃（同配方 + 阴影），选中项 #FF8A3D + 白 12% 胶囊底，
   未选白 55%。Bar 始终是深色，在浅色 Tab 上用更高不透明度的暖色填充保持可读。滚动内容仍由底部 safeAreaInset 让位，最后一个分区不被遮挡。
7. **iPad**：分区内容最大宽 1100 居中；大图全宽、高 600。
8. **无障碍**：大图为一个 VO 元素「番号 标题, 日期」（可左右调节翻页），圆点对 VO 隐藏；所有热区 ≥ 44。

## 刻意推迟

- 底部 7 Tab → 3 Tab 合并（后续阶段）。
- iOS 26 `.glassEffect` 未启用：全部系统统一使用上面的玻璃配方。

Tests: `scripts/test-home-immersive325.py`（静态契约，取代 `test-home-hero324.py`）；其余测试版本号 324 → 325；
`scripts/package-lut325.py` → `AVDB-unsigned-1.0.2-325-home-immersive.ipa`；workflow artifacts `AVDB-325-*`；
新增 `home-immersive-screenshots` 任务（PosterNavigationUITests/test325HomeImmersiveScreenshots，中性 `--home325-fixture`）上传 `AVDB-325-home-screenshots`。
