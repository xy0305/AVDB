# Build 328 — 首页看熱播日榜英雄区、竖滑换条、往期推荐栏、浅色主题

Base: Build 327 / 67a9cca70ff80d1fa5dab63b1165055511d49e93, `feat/detail-auth-327`. MARKETING 1.0.2, build 328. Branch `feat/home-hot-328`.

用户反馈：首页大屏图空白（MIDE-991 截图像素为 `#2A2019`，是英雄页 state 0，不是加载失败横幅）；英雄数据要改成看热播日榜并轮播；往期推荐放到下面做成普通栏目；首页棕色改成和详情页一致的浅色；在保留横滑的同时增加竖滑换条。

方案先与 Muse（Kai）讨论（discussed with Muse / Kai），再共同修订（then jointly revised）。Kai 最初提出过全屏竖滑信息流（fullscreen vertical feed），随后撤回；双方最终采用的仲裁表是 Kai 的，位置是嵌在首页英雄区内（embedded on the hero），不是新的全屏页。空白封面修复与数据源切换同一批次落地，都不是可选项。失败页最小种子（番号/标题/封面）仍**刻意推迟**，不塞进这次首页改动。7 个 Tab 合并、live CoverSR、Build 327 详情鉴权行为均不动。

## 改了什么

1. **空白英雄修复（与数据源切换同一批）**：英雄层始终绘制当前最好的图（定稿 HQ 清晰 ?? 快速模糊 ?? 列表 DTO 封面/缩略图直接加载）。交叉淡入随更好的层到达。列表返回的 DTO 封面是强制底板——即使 HeroCoverStore 卡住也必须有像素。不得把低于档位 / thumb 图提升为定稿 A/B 清晰英雄（326 档位与竞赛规则保留），它只做底板。单条硬截止：现有竞赛总预算（6 s）到期后强制进入终态（有 ≥C 就显示，否则模糊/快速图，否则 DTO 底板）。全局「高清封面加载失败」横幅按**每条终态**判断（全部 `finished && !hasQuick` 且没有 DTO 底板），不再允许单条永远挂起。可见空底改为中性 `systemGray`，不再使用品牌棕色 `#2A2019`。验收不以「新日榜碰巧能出图」为准：用卡住的 CDN（`fixture://hang`）夹具证明截止后进入终态且不是空棕色。该测试代替可能已不在英雄区的 MIDE-991。

2. **英雄数据源 = 看熱播日榜**：`JavDBSDK.playbackRankings(filterBy: "high_score", period: "daily", page: 1)`，与看熱播页默认筛选一致，不用 SDK 默认的 `filterBy: "all"`。轮播最多 10 条。`HeroCoverStore.shared.start` 只作用在这条播放数组上，不再作用在 `recommendMovies`。保留 326 四态、仅 A/B 自动播放（5 s）、不因图片失败踢出轮播、Ken Burns、下拉拉伸、视差、VoiceOver 增减。左上角「往期 {date}」改为「看熱播 · 日榜」身份胶囊，深色玻璃叠在图上；点按打开 `RankingsView(embedded: true, initialTab: .playback, initialPlaybackFilter: "high_score", initialPlaybackPeriod: .daily)`，与英雄同一套筛选。看熱播快捷入口仍打开完整排行页（同样带这组默认筛选）。文案栈：番号 + 标题 + 日期 + 有则显示的简介；日榜条目常无简介，缺则省略，不编造。横滑或竖滑换条后自动播放计时重置。

3. **往期推薦成为普通栏**：英雄上不再放往期胶囊。快捷入口行之后增加 `HomeRailHeader` + `HomePosterRail`，标题「往期推薦」，数据仍是已加载的 `vm.recommended` / `recommendMovies(page: 1, period: -1)`，不额外发网。右侧「全部」仍推进 `PastRecommendView`。栏目顺序：英雄 → 快捷入口 → 往期推薦 → 最新上架 → TOP250 → 近期磁鏈 → 我的關注。

4. **英雄上的竖滑换条（不是新全屏页）**：横滑保留。竖滑也切换当前标题。触摸落下时锁定模式，中途不改：若当时滚动偏移 > 1 pt，整段手势属于 ScrollView，即使后来拖回顶部；若偏移 ≤ 1 pt，进入英雄仲裁。位移 14 pt 时锁轴：`|dy| ≥ 1.5|dx|` 为竖，`|dx| ≥ 1.5|dy|` 为横。英雄仲裁下：横轴走原有分页；上滑且非最后一条则换到下一条（一次）；上滑且已是最后一条则放行给 ScrollView；下滑且非第一条则回到上一条（一次）；下滑且已是第一条则放行，让系统 `.refreshable` 用原生阈值工作。换条阈值：位移 ≥ 56 pt，或轻弹（位移 ≥ 24 pt 且速度 ≥ 500 pt/s）；未过线则回弹。换条后忽略同一手势的剩余部分，一次手势最多换一条。竖向翻页是方向性整页滑动（顶/底边），弹簧 response 0.38、damping 0.88，与横向同一家族。圆点仍在底部并共用同一索引。因为 SwiftUI `DragGesture` + `simultaneousGesture` 无法表达 require-to-fail 放行，手势走 UIKit `UIPanGestureRecognizer` 桥（`HeroSwipePolicy` / `HeroSwipeOverlay`），ScrollView 的 pan 必须等英雄识别器失败后才能开始，二者不得同时移动。底部中央有 44 pt「更多」（`chevron.down` + 文案），点按把首页滚到快捷入口行。

5. **浅色主题，与详情页对齐**：去掉首页根上强制的 `.environment(\.colorScheme, .dark)` 以及 `immersiveActive` 的 `preferredColorScheme(.dark)`。状态栏在英雄图上用浅色内容，在浅色栏区用深色内容（`HomeStatusBarStyle`，不因此把整页颜色方案打成深色）。栏区 / 快捷入口 / 页底使用 `Color(.systemBackground)`，不是硬编码 `#FFFFFF`，主文案随系统外观。326 氛围色只留在英雄本身和顶部过滚动区域，`HomeAmbientBackground` 不再把 `#14100D` / `#2A2019` 涂在栏区下面。明确重着色：栏目标题、海报卡番号/日期、「換一組」/ 箭头；快捷入口在浅底上用 `secondarySystemBackground` 圆形底 + 深色图标和标签；我的關注选中仍是橙色，未选用浅灰底 + 深色字；搜索钮保持深色玻璃白图标，在英雄和浅色已滚页面上都可读；`HomeTopScrim` 改为系统背景淡出，不再用棕色 `#14100D` 罩住浅色页。不重做 TOP250 图片横幅（仍是深色岛）。不重做底栏配方；因 0.32 填充在浅色首页上对比不足，首页改用已有的非首页 0.66 填充，此外不动底栏、不合并 Tab。英雄本身仍是通栏图 + 深色 scrim + 白色标题/日期/简介，看熱播胶囊、搜索、圆点和「更多」仍是图上镀铬。

## 刻意推迟

- 底部 7 Tab → 3 Tab 合并。
- 可选 CoverSR 后处理（`HeroCoverSRHook.liveSREnabled = false`）。
- 失败页最小种子（番号/标题/封面）——Build 327 曾写「推迟到 328」，本次首页改动仍不纳入。

Tests: `scripts/test-home-hot328.py`（静态契约）；`HomeHot328Tests`（仲裁表七条 + 卡住源截止夹具）；`test328HomeHotChrome`（芯片、「更多」、往期栏）。326 英雄截图任务与 327 详情鉴权任务保留。
`scripts/package-lut328.py` → `AVDB-unsigned-1.0.2-328-home-hot.ipa`；workflow artifacts `AVDB-328-*`；专用 `home-hot-328` 任务。
