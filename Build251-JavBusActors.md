# Build 251 · 缺失演员头像 JavBus 补充

版本 1.0.2 (251)，最低 iOS 17。独立 Swift 实现，不加载或移植未知 .NET 程序集。

## 优先级与真正覆盖

`ActorAvatarArtwork` 共享入口：AVDB 任一非空 avatarURL / coverURL 始终优先；缺失时且有已知真实作品番号，JavBus 精确演员节点头像优先；没有已知番号、页面403/错误/无匹配、图片下载失败则保留原有 TMDB 姓名唯一匹配 fallback；TMDB 也失败则沿用原占位显示。不替换已有 AVDB 图片，包括其网络下载失败时。

覆盖：作品详情演员网格（直接传当前作品番号）；演员详情头图（仅取该页已经加载作品前两部番号）；AVDB 演员列表、原生演员榜单、搜索演员、个人演员收藏卡片。无番号卡片只允许复用共享服务记住的、同账号同后端该 AVDB actor ID 已查到的前两部真实作品，不额外调 actorMovies，不编造番号。第一次打开一个没有作品上下文的榜单，通常仅能走 TMDB；查看演员详情取得作品后再显示卡片才可利用作品上下文。

范围限制：JavVerse 外部榜单和 MissAV 自有映射卡片原来的 TMDB/source-avatar 呈现路径未改；它们导航进入的 AVDB 演员详情使用新服务。不能称所有外部榜单头像已覆盖。没有新增批量演员作品拉取或后台扫描。

## 精确关联和网络边界

仅允许 `https://www.javbus.com/<PREFIX>-<digits>`，保持完整番号，不补零、不截断、不猜测。同一 `.movie .info` 的识别码必须唯一且完全一致。只读 `a.avatar-box` 节点自己的 span 姓名、img title/src 与 `/star/<id>`；已有姓名/合法映射别名按 NFKC/casefold/空白归一后完全相等，不能子串匹配。冲突映射别名排除；同名多个 star ID 或头像不唯一拒绝。仅接受第一方 `/pics/actress/<id>_a.jpg|png`，拒绝占位图、凭据、端口、百分号、查询参数与片段，不取页面第一个图。

页面与头像使用专用 ephemeral URLSession、无 cookie storage/凭据/缓存、拒绝全部重定向。共享最多2个活动请求；页面8秒请求/10秒资源超时、768KiB上限；头像2MiB上限。流式读取中检查取消。单作品页面同时请求合并为等待同一有界任务完成的缓存结果，调用者取消可退出，最后一个活动请求随其所属调用者取消；其他等待者可自行重试，不使用脱离UI生命周期的网络Task。成功页面/头像TTL24小时；页面缺失/403/解析失败及图片HTTP失败负缓存10分钟；传输错误页面负缓存10分钟；显式取消不缓存。图片传输抛错不缓存，仍受超时/并发限制。页面缓存最多120条、图片60条、已查作品注册表240个演员；账号/后端scope隔离，账号通知清理UI结果与头像cache。内容不落盘，无账号token发往第三方。

## DLL 只读调查

ActorArchives.dll，247296字节，SHA256 `7ec991e4f5ac1ea21b7c906301159f53faef43428bc8db7d701bda02365c17d4`。仅用 Python struct 读取 PE/CLI 元数据流与筛选后的公开 endpoint/资源字面量；未加载、执行程序集，未复制IL或不明许可实现，未输出凭据。

公开线索实际是 Gfriends `Filetree.json` / `releases/download/filetree-latest/Filetree.json` 图片索引、Jav-Actors-Mapping release endpoint、MetaTube actor_mapping.json，以及 GitHub/raw/jsDelivr 域名。类型名包括 ActorImageProvider、ActorMappingService、ActorImageLookupCoordinator，字面量明确是“扫描没有头像的演员，从 Gfriends 自动搜索并应用第一张头像”。未找到 JavBus ASCII/UTF16 字面量或相应页面选择器，所以 DLL 不是 JavBus 取图成功证据，不能据此宣称移植完整Emby插件。此次不采用其“第一张头像”策略，也不新增 Gfriends 下载。

## 验证规则

新中性 Swift fixture 直接编译生产解析器与共享缓存服务，覆盖完整番号、多演员各自节点、别名、无匹配、坏URL/占位图、403、取消不缓存、账号隔离、共享并发请求合并、最多两部作品和不覆盖AVDB。无成人作品图片fixture；HTTP探针只请求作品HTML，头像不GET验证。真实浏览器 DOM 诊断与 native URLSession 探针分开记录，不将浏览器可访问等同原生HTTP成功。

250身份作品数严格最多规则/单确认页、247缺aliases兼容、静态榜单、TMDB钥匙串与字幕/历史/收藏代码不重写。所有发布使用真实parent/base_tree和非force分支更新，不修改main/win/VPS/CF，不workflow_dispatch。构建、原生验收与IPA校验真实状态见交付报告和verify.json。
