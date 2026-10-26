# 原生糖心 build261（功能基线 1.0.2 build258）

## 基线与隔离

- 2026-10-26 fetch后确认远端main仍为build201、`fix/subtitle-position-201`最新为build260。没有从main或260开始。
- build258历史依次有`211b1f4`、`b8634e5`、`cd63335`；选择最后的`cd63335fca9405774104e18149632007952800d5`，tree `5981bf697527d3ff4bffc6f7fb2558f363d7735d`。
- 此基线的IPA CI [40221986706](https://github.com/xy0305/AVDB/actions/runs/40221986706)成功；同提交的中性UI CI [40221986647](https://github.com/xy0305/AVDB/actions/runs/40221986647)失败，未将它描述为通过。
- 分支`feat/tangxin-from258`仅普通push。无merge/force-push，未改main/fix。保留基线播放器、115、字幕、手势、音频、LUT、排行实现；不引入259最高HLS档位偏好或260资源布局。
- fetch时全仓远端分支最大构建号260，因此使用261，marketing仍为1.0.2。旧离线合同只更新版本断言，不弱化其他检查。

## 原生实现

- SwiftUI `TangxinRootView`独立NavigationStack。列表支持下拉刷新、按真实下一页链接加载、错误重试、去重、取消与代际隔离；作者push/pop保留原列表状态。
- 详情使用生产Swift parser；只取`article.info`中的作者链接，不把相关推荐作者当本片作者。作者页按同源`/a/<name>/`链接原生展示作品；本站采样未下发头像，不编造头像/总作品数。
- 复用既有`KSChromePlayer`，每次实例局部传入站点Referer和UA，不改播放器代码、不修改全局headers、不查JavDB，不生成Movie ID、不将HLS传给115。
- 点击播放前复用公共`OnlineTransport`/`OnlineMediaScope`/`OnlineManifest`，严格公网DNS、HTTPS、同源HLS子清单/密钥/分片路径检查，限制清单图深度/数量；标准AES-128由现成HLS播放器处理，不自写解密或中转。
- 六个原生底栏按钮均可见（含iPad）；真实iPhone XCTest发现六项TabView即使隐藏系统栏仍会生成More外壳、双层返回及双栏，因此改用延迟挂载、稳定身份的原生SwiftUI六栏容器；未访问栏目不自动挂载，已访问栏目与导航状态保留，不创建系统More。iOS26使用真正`glassEffect(.regular)`，17–25使用系统material回退。按钮高度52pt，作者和播放控件至少44pt，图片装饰不抢触控。

## 脚本移植边界

参考文件`rex-tangxin.js` v1.6.0，SHA256 `f963d1797aa9926fe8bfba025548f651f1883d58ad2193e25781cdad93502dba`。分段阅读模块/函数/headers/路由，不作为代码执行或网页JS运行。

移植：精选视频、视频详情、页面实际发出的作者链接、作者作品分页、媒体Referer。未移植：805项硬编码作者枚举、全量标签枚举、混合首页聚合、站点域名任意输入、脚本storage、脚本CDN猜测fallback。这些不是可靠身份/安全分类或已验证来源。原生不提供专门的偷拍、未成年、泄露私密内容入口。

## 实站只读核对

2026-10-26，只读请求站点公开精选及其普通成人原创详情、该页实际作者链接和已下发HLS清单；不导入浏览器cookies、不登录、不探测违规类别、不绕验证码、不下载密钥或视频分片。

- `/featured/`：HTTP200，Astro静态HTML，24个`article.card`，`a.cover-link`内`img.alt`为标题；`a.nickname`提供作者。真实下一页链接是`/featured/2`（不以脚本的拼接规则猜测）；采样显示1/153。
- `/v/<issued-id>/`：HTTP200，`article.info h1`、`p.description`、本片`a.nickname`和tags；页面实际下发`https://t.5gcdn.xyz/videos/<issued-id>/index.m3u8`。
- `/a/<issued-name>/`：HTTP200，`header.artist-head h1`、作品列表；此作者采样只有一页，无头像。
- 清单带`Referer: https://tangxinvlog.app/`：HTTP200，标准AES-128，976个EXTINF、无多档master；只证明清单请求成功，**不是播放首帧证明**，未宣称无Referer一定失败。
- 仓库只保存`captured-safe-metadata.json`中的结构/状态/散列，不保存真实标题、作者姓名、缩略图、raw HTML、密钥、签名媒体URL或cookies。

## 内容限制

普通作者昵称（包括“黑料”）不作为违规判定；作品标题、标签、详情明确指向未成年、偷拍、非自愿泄露、强迫或下药等风险时隐藏列表项并拒绝详情/播放。当前仅提供精选和从安全作品发出的作者页面，不导入危险标签入口。

这只是基于可见元数据的保守筛查，不能证明所有内容自愿或成年，也不能识别所有隐晦描述；若发现内容侵权/非自愿，应停止使用、不要传播并向来源举报。来源不可用、挑战页面或结构变更会明确报错，不回退猜地址。

## 网络隔离与限制

- 固定HTTPS根域，未增加任意来源配置；页面/作者/分页严格同源，分页仅允许当前集合的紧邻下一页。
- 糖心图片走独立客户端及来源headers，不复用JavDB图片cookies/cache。每次公共传输创建ephemeral session，禁cookies、credentials和URLCache，拒绝重定向，保持系统TLS验证。
- 未放宽公共在线播放DNS/TLS或更改系统代理策略。shell fetch所用git SSL环境不进入App。
- AVPlayer/KSPlayer的真实重定向与播放器网络行为仍遵循既有播放器能力；预检只能验证当次下发的HLS图，不能保证来源稍后不改变内容或DNS。真机真实首帧/连续播放/加密密钥加载仍需用户验收。

## 测试与验收

- `scripts/test-tangxin261.py`在macOS编译真实生产Swift parser和公共网络策略并在deny-network沙盒执行：列表、详情、作者关联、分页、去重、黑料昵称保留、风险拦截、URL/跨源/私网DNS、局部Referer、AES-128清单与密钥契约。fixtures明确合成，不含真实人物或媒体。
- 复用既有Build IPA CI，保留258回归，新增生产Swift门禁及独立真实iPhone/iPad Simulator XCTest job。
- `scripts/test-tangxin-ui261.py`编译真实ContentView/底栏/糖心视图及模型；非糖心栏目与播放器为惰性替身，糖心网络由注入loader完全替换。测试六Tab可达、糖心→作者→作品→返回、分页去重和切Tab保留状态。截图名`SYNTHETIC-261-*`，证明原生UI，不证明线上播放。
- Release IPA必须按CI当前提交SHA、Info.plist 1.0.2/261、ZIP完整性、arm64 Mach-O及无签名逐项验证后才交付；CI状态/产物详见此次交付记录。
