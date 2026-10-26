# Build 263 — 糖心原生网络诊断与受限系统代理兼容

功能基线为258 `cd63335`，延续独立分支 `feat/tangxin-from258` 的262 `5afd5bd`。已fetch，远端可读分支最大构建号262，递增为263；未合并main/fix/260。

## 源码确认的缺陷（不是推断用户网络）

262 `validateDNS` 原本抛出了DNS具体固定reason；`OnlineTransport.fetch`把糖心带scope的列表错误推断成“密钥/DNS”，而`OnlineFailure.presentation`的旧阶段词典不识别“密钥”，于是显示未知阶段。旧diagnostic分支只识别HTTP、超时、取消、TLS等少数固定文本，没有识别DNS空集、getaddrinfo和非公网/合成地址拒绝，因此统一映射unknown并丢掉reason。仅凭262截图不能反推出被丢弃的实际reason。

修复使用类型化安全detail、数字code、errorDomain和地址类别计数，网络错误不再经过localizedDescription再分类；糖心调用明确传入查询/详情/图片/清单/密钥阶段。旧固定DNS reason仍兼容到有界detail，不渲染任意错误自由文本。CustomNSError仅携带安全诊断，NSError重建/捕获可恢复类型化reason；不保存系统userInfo、URL或响应体。URL错误按domain+code分类，保留DNS/TLS/连接/取消/HTTP，未知域相同数字不误判TLS。

## 用户入口与行为

糖心首页右上角“网络设置/诊断”。默认严格模式；“运行诊断/重试”仅GET公开列表，显示来源host、阶段、HTTP/系统错误码、错误域或地址分类计数，不输出地址、完整敏感URL/query、Cookie、密钥或标题。提供“在Safari核对来源”外部链接，不在应用中渲染网页、不绕CF验证。

只有用户信任当前系统VPN/代理且自愿开启“系统代理/Fake-IP兼容”时，糖心局部client通过withDNSMode使用systemProxy；选择只在糖心偏好内持久化。切换重建糖心导航与请求，防止旧严格/兼容任务混用。应用不修改系统DNS/路由/代理；不自动降级、不固定IP、不关闭TLS。

只允许已核准来源198.18.0.0/15及既有合法mapped/NAT64包装；私网/回环/ULA/fd27/混合不安全地址仍拒绝。UI警告明确不能由5G状态推断是否存在VPN，不能声称用户设备实际使用Fake-IP。

加载有文字状态；取消未完成请求后显示可重试的取消提示，返回重入会重新启动，不再仅清空error并沉默。既有成功页面与generation隔离保留；空源、筛除、结构变化仍分别显示。没有把HTML解析或降低筛查当网络修复。

## 能力边界（必须向用户保留）

列表、作者页、图片、详情、HLS主/变体/音轨清单和AES-128 key预检均使用同一选定transport/DNSMode；原有URL/host/scope/HTTPS/禁止重定向及HLS所有子资源URL校验不变。分片URL在清单解析时继续逐项同源验证，兼容模式没有扩大主机或私网范围。

原有KS原生播放引擎消费原清单并自行请求后续keys/segments、解析DNS和处理网络。本次未替换播放器/增加资源代理，应用预检不是DNS pinning，**不能保证原生引擎播放期的每次DNS/重定向都由OnlineTransport拦截**，也不能把合成预检测试宣称为全链真机播放验收。systemProxy不会强制原生播放器改DNS；它仅解除应用对精确受限合成地址的预检拒绝，由当前系统网络负责实际连接。若要求对播放期每次key/segment网络严格执行同一应用策略，仍需单独设计完整资源加载层；本版不假称已实现。

## 验证与未知

新增生产Swift运行回归覆盖：原始diagnostic固定reason、LocalizedError显示、NSError重建roundtrip；严格拒绝198.18、显式approved系统代理允许、未approved拒绝、私网/ULA/fd27/NAT64私网仍拒绝、DNS空集/getaddrinfo、URL错误域/code/TLS/取消、客户端列表/图片/详情/HLS/key模式传播，以及拒跨域/私网/明文分片URL。iPhone与iPad真实Xcode Simulator合成UI门禁覆盖入口、具体诊断、重试、默认关闭、用户开启后实际客户端成功、重新关闭恢复严格拒绝。模型取消断言改为必须显示取消提示，而非旧版要求error为空。

本机Linux只能运行静态Python契约，生产Swift和UI执行由macOS CI完成，结果另行记录。只读curl/生产Swift网络验证仅说明执行环境当时情况，不是用户设备复现。用户262截图确认错误文字；另一张只有来源说明的白页不能证明唯一生命周期根因。用户设备实际DNS结果、VPN/代理配置、运营商环境、TLS与首帧仍未知；不保证真机根因已经解决。

保留明确未成年、偷拍、非自愿私密泄露等内容风险拦截；元数据筛查不能证明所有内容合法自愿成年。未改258播放器、字幕、手势、115、LUT、音频及其他栏目的网络偏好。版本契约只更新263，不弱化原断言。
