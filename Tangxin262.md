# Build 262 — 糖心空列表分类与生命周期修复

基线：功能258 `cd63335`，独立分支 `feat/tangxin-from258`，延续261 `616b0e8`；不合并main/fix。

## 已确认的缺陷与修复

- 261把来源真正空列表、全部筛除及解析失败统一显示为“暂无可显示内容”，缺少证据分类；262生产parser返回content/sourceEmpty/filtered/structureChanged以及只含数量的report。
- 生命周期防御性加固：262新增显式cancel，取消时使未完成页面可再次加载，保留成功页面与导航状态，generation隔离旧响应。取消初次加载再入已由新生产模型回归覆盖；未证明用户261截图由生命周期导致。
- 标题提取支持card局部h3.title内同一作品链接，过滤空aria-label/alt后回退；全部候选标题和卡片局部标签都筛查，不能用安全alt掩盖风险heading，不扫描全局标签或普通作者昵称。
- 空/筛除/结构变化页保留经同源集合及相邻页验证的真实next，显式手动每次推进一页，不自动扫描填满。

## 根因边界

用户手机261截图只证明当时为空，不能证明24张卡全部被策略筛除。先前Python复算不是生产Swift结果。CI新增只读GET（生产相同UA和Referer，无cookies/redirect/标题日志/HTML artifact），在macOS分别编译261原生产parser和262生产parser；只输出HTTP与计数。macOS CI `40254061382`实测（2026-10-26 01:24–01:25 UTC）：HTTP200；原261生产Swift parser显示23项、next=true、rootAllowed=true；262生产Swift parser为content、cards=24、extracted=24、blocked=1、malformed=0、duplicates=0、displayed=23、next=true。该次运行的UI断言误把SwiftUI非独立AX容器当otherElements，已改为验证实际渲染的状态文案；该运行整体不是通过记录。上述生产计数排除了该次响应“全部被筛”或原Swift正则普遍失效的推断，不能倒推截图当时的网络、响应及设备生命周期唯一根因。最终IPA仍须通过修正后的整套CI。

## 安全与保留范围

明确未成年人、偷拍、偷录、非自愿泄露、强迫、下药等拦截保留；普通黑料昵称不是过滤依据。可见元数据规则不能证明所有内容成年且自愿。未改DNS/TLS/重定向/同源/私网与HLS范围保护；不猜CDN媒体地址，不下载视频，不执行网页脚本。

保留258播放器、字幕、手势、115、LUT、音频、既有六按钮原生底栏及导航状态；此次不改这些实现，仅精确更新旧版本断言为262，其他断言不弱化。

## 验证方式

- macOS生产Swift parser：mixed/allblocked/sourceEmpty/malformed、局部tags、heading回退及冲突标题、URL/私网DNS/HLS/Referer等旧回归。
- iOS Simulator生产模型：初次加载取消再入、外层任务取消、刷新代际隔离、错误重试、逐页手动推进。
- 真实Xcode iPhone与iPad Simulator XCTest：生产ContentView/底栏/糖心视图，合成loader；原导航/分页返回保留，并新增filtered/sourceEmpty/structureChanged/mixed状态截图。其他栏目和播放器为替身；不是实体设备或实站播放验收。
- Build IPA全套原回归与Release构建；IPA核对ZIP、plist 1.0.2/262、arm64、unsigned、AVDBSourceCommit/AVDBSourceTree与该CI提交一致。

用户设备网络、真实首帧、连续播放、密钥加载仍未验收；不得以模拟器合成UI或清单请求替代。
