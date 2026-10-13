# Build 175 — MissAV 原生请求兼容性与 403 诊断

版本：1.0.2 (175)。只修复新增 MissAV 来源；AVDB/JavDB 排行、完整番号精确匹配、原生详情、115 Cookie/目录与离线资源推送不变。

## 已确认原因与证据（2026-10-13，当前执行网络）

对参考 `MissAV_TuT.js` 的站点候选与请求头进行只读 HTTPS GET 对照。路径均为 `/dm170/cn/weekly-hot`，不自动跟随重定向、不带账号或浏览器 Cookie。每个域分别测试 `AVDB-readonly` 旧 UA 与参考 iPhone Safari UA + HTML Accept + 语言 + 同域根 Referer。

| 域 | 旧 UA | Safari 请求头 | 内容与跳转 |
|---|---|---|---|
| missav.ws | 403 | 403 | `cf-mitigated: challenge`，Cloudflare 中间验证页；无跳转 |
| missav.fans | 200 | 200 | 12 张真实 thumbnail 卡片；无跳转 |
| missav.media | 200 | 200 | 12 张真实 thumbnail 卡片；无跳转 |
| missav.ai | 403 | 403 | Cloudflare challenge；无跳转 |
| missav.live | 403 | 403 | Cloudflare challenge；无跳转 |

首次批量探测使用 curl -k（运行环境排障用，不进入应用）；随后额外以正常证书校验 GET `https://missav.fans/cn/weekly-hot` 确认 200。应用继续使用系统 TLS 校验，没有降低证书验证要求。

**已确认**：当前网络上默认旧域 missav.ws 的 403 是 Cloudflare 验证，不是 AVDB/115；换 UA 不足以解决。旧代码在响应头阶段丢弃 403 正文，无法区分普通禁止与挑战。另一个可复现的解析缺陷是：正常 fans/media 200 列表尾部也含 `/cdn-cgi/challenge-platform/scripts/jsd/main.js` 被动脚本，旧版将任何 `challenge-platform` 字串当作验证码，错误拒绝可读排行。真实列表还将 dm 前缀链接规范化为 `/cn/weekly-hot?page=2`，旧同路径分页比较会漏掉下一页。

**兼容风险而非已证明的403唯一原因**：AVDB-readonly UA、过窄 Accept、缺 Referer、完全禁止普通站点 Cookie 都不利于正常 HTTP 访问；本次对齐标准头并恢复隔离的正常会话 Cookie，但不宣称头或 Cookie 能绕过 Cloudflare。用户真机、IP、地区与当前执行网络不同，未复现其设备本身。

## 修复

- 新默认域为实测有真实列表且与参考 JS 一致的 `missav.fans`。已保存自定义域原样保留；没有自动镜像轮询或切域。若曾手动保存 missav.ws，可在 MissAV 设置点「恢复默认 missav.fans」后保存。
- 标准 iPhone Safari UA、HTML Accept、zh-TW/zh-CN/en 语言与当前来源根 Referer。HTTP Connection/压缩交给 URLSession 管理，不复制 JS 播放解码、广告或脚本执行。
- 独立 ephemeral 内存 Cookie storage，仅正常 HTTP Set-Cookie；同站列表/详情请求复用，切换来源域丢弃旧 jar。不是 shared Cookie storage，不读取或写入 AVDB、115、WebKit 或浏览器 Cookie，不持久化验证 token，不伪造 token。
- MissAV 传输有界读取最多 4 MiB 的错误页，识别 cf-mitigated challenge、真正的中间页标记与 HTTP 状态；普通 403 不冒称 Cloudflare，非 HTML 也拒绝。JRRedirectPolicy 默认行为保持原样，仅 MissAV 注入可选响应检查。
- 被动 JS 检测不再误杀正常列表；不执行任何脚本。200 真挑战、空页、广告或无合法卡片仍拒绝。
- 允许已经通过严格路由验证的 `/dm数字/cn/同一排行` 与 `/cn/同一排行` 之间分页链接规范化；仍要求 rel=next 和下一页序号，保留域名、查询参数、路径和封面白名单。
- 实站未观察跨域重定向，不放宽既有 HTTPS 来源/子域安全限制；跨域来源必须用户核对后手动保存，绝不跟随任意 Location。
- 保留重试；错误区提供普通浏览器核对来源链接，不用 WKWebView 展示排行，不共享浏览器 Cookie，并明确浏览器验证成功不代表原生获准。

## 测试与边界

`scripts/test-missav.py` 在 macOS CI 编译运行 shipping Swift parser/URLSession 回放：旧 ws 日周月/详情夹具，新增实站 fans 200 列表及被动 Cloudflare JS、规范化下一页、实际请求 UA/Accept/Referer、独立 jar 复用/跨 AVDB 与115隔离/切域清理、403 header challenge 与普通403、503 challenge、200非HTML、200 challenge、取消/重置，以及原有精确番号和115纯资源预检。

iSH 没有 swiftc，本地只跑静态检查；Swift 运行和 iOS Release 编译必须以 GitHub macOS CI 实际结果为准。未使用真实 AVDB/115 账号，未执行115写操作；未做用户真机安装与地区连通性验证。未承诺 Cloudflare challenge 可由此版本自动解决。
