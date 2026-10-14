# Build177：外部数据库令牌配置

版本：1.0.2（177）。基于远端 main 6e4a3ca；fetch 后确认本地与远端一致且工作区干净，没有覆盖用户修改。

## 使用

- 「我的 → 来源 → 外部数据库」（无需登录），启用后填写令牌并点击「保存设置」。默认关闭，无内置或历史源码令牌迁移。
- SecureField 初始为空，仅提示已保存/未配置，不读取后填入字段。空输入保存保留旧值；显式清除需确认。返回放弃未保存编辑。
- 服务器可配置 http/https 根域/IP/端口，禁止 userinfo、非根路径、query、fragment。换服务器要求新令牌，或先清除旧值。
- 默认 HTTP 地址仅为兼容。HTTP 明文传输，令牌可被窃听；建议可信 HTTPS。本地 Keychain 不会令 HTTP 变安全。
- 无令牌/停用不请求。保存/清除使旧会话取消，详情清除旧源资源并重查；鉴权、网络、格式及 Keychain 错误可见。

## 实现边界

令牌只写 Keychain，采用 WhenUnlockedThisDeviceOnly，禁用同步；偏好设置仅保存服务器和启用状态。不写令牌至 UserDefaults、URL、剪贴板、文档或日志。请求使用 X-API-Key，ephemeral 会话禁用 URLCache、Cookie、自动凭据存储；所有重定向均拒绝，包括同源。日志/错误不展示服务器响应正文或原始网络错误。新令牌由安装后用户输入，未用于构建。

保留 ExternalLibraryClient.links 返回接口兼容，详情改用可抛错 fetchLinks。网络层校验配置 revision，详情二次校验并保留原生磁链，防止停用/换钥匙串令牌后旧响应继续合并。所有 115 推送仍由用户主动操作，本变更不发送真实写请求。

## 回归及验收范围

`python3 scripts/test-external-library.py` 在无 Swift 环境仅执行源码安全/入口结构检查并明确跳过可执行测试。macOS CI 用 swiftc 编译生产客户端及 ExternalLibraryRegression.swift，通过隔离 UserDefaults、内存令牌 store stub 和合成 URLProtocol 运行：首次无令牌/停用不请求、写读保留/清除、Keychain 失败、鉴权头及路径、禁止 URL 携带凭据、HTTP/格式错误、配置代际隔离、请求取消、后续请求新头、同源/跨源重定向拒绝。不会测试或调用任何真实账号。

UITests 新增我的页面入口、SecureField 空白不回显、保存/清除控件和保存状态可见断言。iPad Poster Navigation CI 执行模拟器测试（只导航，不写令牌）。Build IPA CI 保留已有 MissAV/JAV Ranking、115 原生协议、播放器手势、音频会话、LUT/MediaPipe 等回归，生成 unsigned arm64 IPA。CI 完成情况以对应 commit 的 Actions 结果为准，不把静态检查说成运行测试，也不声称真机验收。

本次移除当前源码硬编码值，不重写既有 git 历史；历史中曾出现的凭据必须在服务端撤销，删除源码不等同于撤销。
