# Build178：外部数据库只读连接诊断

版本 1.0.2（178），fetch 后基于 origin/main ebe3020。

## 证据与边界

任务提供的前序只读实测：`http://163.47.40.207:8000/api/v1/articles/torrents?keyword=IPX-811` 在 VPS 本机带用户令牌为 HTTP 200、data 5 条，字段兼容 ExternalLink；无令牌为 401，主助手公网无令牌亦 401。18000 没有对应服务。本次不读取真实 secret、不连接 SSH、不变更服务器、不执行 115 写操作，也不重复带用户凭据测试。

用户设备此前只显示被折叠后的 `.transport`，没有实际 URLError 码。因此真机根因未知，不宣称由 ATS、代理或 TLS 导致，也不宣称真机已修复。

## 客户端变更

- 新默认端口 8000；已保存精确旧默认 `http://163.47.40.207:18000` 保持原样并提示。点击迁移按钮仅填写编辑框，必须重新输入令牌并保存；同 host 不同 port 仍禁止无新令牌更换 endpoint。任意自定义地址不被重写。
- 设置页测试连接，仅使用已保存配置只读查询 IPX-811；有未保存编辑不能测试。诊断仅显示实际 scheme/host/port、HTTP 状态、记录条数或白名单安全错误描述及 URLError 数值。
- 超时 -1001、无法连接 -1004、中断 -1005、ATS -1022、DNS、断网及 TLS/证书 -1200...-1206 分类。详情同样显示安全数值，不透出原始 error/userInfo、token、请求头、正文。
- 保留 X-API-Key、补 Accept: application/json；仍然无 key 不请求、Keychain 本机存储、禁止所有重定向、无 Cookie/缓存/凭据缓存。TLS 使用系统验证，不增加信任绕过。
- 请求与测试结果按 revision/attempt 隔离；保存配置下一次请求使用新 endpoint；页面退出/配置变更取消测试并丢弃结果，取消不显示失败。

## 生命周期与 ATS 检查

生产 transport() 复用有效 URLSession，委托由 URLSession 强持有；仅 cancelRequests() invalidateAndCancel 并置 nil，下次查询创建新 session，未发现每次请求前意外 invalidate。已有回归覆盖取消后再次请求成功。没有证据需重写 session 生命周期或服务接口。

源 Info.plist 的 NSAppTransportSecurity 只有 NSAllowsArbitraryLoads=true，没有 NSAllowsArbitraryLoadsInWebContent/ForMedia/LocalNetworking 等可覆盖该值的键。现状已允许 HTTP；不修改 ATS，也不放宽 TLS 校验。实际 IPA plist 需在产物验证中复核。

## 验收

scripts/test-external-library.py 调用 swiftc 编译真实生产客户端 + ExternalLibraryRegression.swift，使用合成 URLProtocol/隔离 UserDefaults/内存 token stub：安全错误码与敏感 raw 描述抑制、HTTP 401、Accept、固定只读番号、取消、配置保存后实际端口与新头、旧端口不自动改写、同 host 跨 port 防旧凭据复用、诊断过期结果丢弃，以及原有 Keychain/无 key/重定向/代际测试。Linux 无 swiftc 时只执行静态检查并明确跳过 Swift；macOS CI 执行真实 Swift 测试。

复用现有 iPad 设置入口 UI 测试，检查安全输入框不被填充、诊断按钮和保存 endpoint 存在、进入页面不自动生成测试结果。它不调用外部服务、不是用户真机验收。

用户安装后：若旧端口提示，点击填入 8000，重新输入令牌、启用并保存；点击测试连接，反馈显示的 host/port、HTTP 状态或 URLError 数值即可。不要发送令牌或钥匙串内容。HTTP 仍是明文传输，建议后续由服务方配置可信 HTTPS（不在本次服务器操作范围）。
