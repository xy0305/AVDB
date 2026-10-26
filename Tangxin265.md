# Build 265 — 糖心集合尾斜线、紧凑标签与播放点击验收

版本 1.0.2/265；分支 feat/tangxin-javverse-from261；来源功能基线 d761e795b1111c15c7b91d1ad01368c520e28e0e；264 前序提交 5718b1d。仅普通推送同分支，不合并 main/fix。

## 已证实的实站网络事实

2026-10-26 的只读 GET 已确认：/featured/2 返回 HTTP 307，Location 为 /featured/2/；带尾斜线同页返回 200。作者根、已许可安全标签根及该安全标签第二页也存在相同补尾斜线的 307→200。作者样本第二页本身 404，根页没有 next，不能把它当作真实作者分页成功证据。没有探查风险类别、账户或真实115。

TangxinPolicy.canonicalPage 先执行现有 HTTPS/精确同源/路径/编码/查询/fragment/端口/类别门禁，再仅补集合 URL 的末尾斜线；不规范化视频或媒体地址，不跟随 Location。parser 的 next、作者、标签入口均输出规范化 URL，标签同路径有无尾斜线去重。client.document 实际发送规范化集合请求，client.list 相对链接解析基址也采用实际请求 URL，避免请求已经补斜线但相对 href 仍按旧文件式 URL 解析。模型 root/load/visited/next 使用同一规范化身份，失败不记 visited，允许显式重试，generation/取消/返回保留成功页语义不变。

生产 transport 注入夹具断言 actual request 为 canonical，使用现有 DNS 校验且不执行网络；另直接调用生产重定向 delegate，验证 301/302/303/307/308 对同源斜线跳转、跨域、HTTP、私网目的均回调 nil。后者证明拒绝策略而非真实服务器响应链。没有修改 OnlinePlaybackCore、TLS 或 DNS 策略。自动翻页仍保持264的48卡真实viewport/drag门禁、失败不自动循环、去重零新增停止、sourceEmpty/filtered/structureChanged仅手动单页前进；模型补充空页多次sentinel不推进与规范化请求/根身份断言。

## 布局事实与推断

生产代码事实：旧详情标签使用自适应网格布局；265改为复用 CategoriesView.swift 中的生产 FlowLayout(spacing:8)，标签按内容宽度排布，最小44pt点击高度；详情 ScrollView 增加16pt底部安全区和44pt scrollContent底部余量（一个最小点击目标高度），继续由 ContentView 的 measured safeAreaInset 决定原生底栏占位，不使用固定屏高/忽略safe area。单独 Swift/模拟器宿主均从原文件抽取相同 FlowLayout 声明编译，不维护测试专用假算法。

“大间隔竖排来自网格分配宽度”是针对反馈和旧代码的合理推断，不冒充旧版真机测量或截图结论。首轮265 CI（a5a1b26，40292153271）已经测得仅16pt安全区时：iPhone 402×874 viewport，12个chip为3行、总高148pt；播放按钮frame=(16,750,370,58)，底栏按钮从y=786开始，完整播放目标仍重叠22pt。实际tap能进入替身，但完整目标避让断言失败，不能以isHittable或tap成功掩盖这一事实；随后增加44pt可滚动内容余量，保留原断言重跑。新增 iPhone/iPad Simulator 用12个合成标签及长详情，记录每个chip位置、行数、总高和播放/底栏frame；要求同一行至少两个chip、实际换行、44pt高度、每行8pt间隔以及总高上界。实际滑动后整个播放按钮位于底栏上方且有8pt余量，执行tap并等待全屏惰性 KSChromePlayer 替身标识，不只断言 isHittable。标签与作者入口均执行点击/返回。既有48卡列表自动分页与返回测试不缩减。

## 播放业务预检边界

未跳过生产 TangxinClient.playback：点击后仍校验详情、读取HLS清单、解析variant/key范围、检查AES密钥16字节，再创建播放计划并进入既有fullScreenCover。宿主仅替换最终 KSChromePlayer 类型，夹具替代 transport IO；没有给release链添加绕过网络hook。新增密钥读取失败场景验证点击发生但显示错误/重试、不进入替身，区分网络预检错误与点不到。

这不是实际HLS解码、真实CDN/密钥可用性、播放器后续segment/redirect行为或用户iPhone/iPad物理设备播放证明；本轮不声称真机播放验收。实站只读请求与合成生产代码UI验收分开记录。最终结果以对应提交 CI 与产物验证报告为准，Linux静态检查不是Swift/UI执行。

## 保护与交付

Player目录、原电影Detail、115与其他来源的业务实现不动；相对d761e79验证Player/Detail/OnlineAdditionalProviders/DetailOnlineAdapters一致；相对a0625a5验证OnlinePlaybackCore/PlaybackDiagnostic/AVDBNativeTabBar一致。最高HLS、263网络模式与tab保持。版本plist/project和旧版本硬契约仅同步到265，不弱化断言。

IPA交付必须在同提交Release构建和iPhone/iPad UI门禁成功后，校验ZIP CRC、1.0.2/265、嵌入source commit/tree、Mach-O arm64以及无签名，再写入dist。JavVerse每日自动更新仍受无人值守来源403阻塞，本次未处理或声称完成。
