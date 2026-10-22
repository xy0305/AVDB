# Build228 在线点播：独立实现与真实验证边界

## 实现来源
本功能为 Swift 原生独立实现，依据公开匿名 HTML/JSON/HLS 响应的结构和公开站点脚本所描述的网络协议；未复制、运行或移植 AvPlay 非授权代码/资源。既有静态复核仅用于定位协议，不替代网络验证。没有通用网页执行器、浏览器 Cookie 导入、FlareSolverr、私钥或 IPA 内置账号。

## 六源实际阶段
- **JavMenu**：真实 `/zh/{number}`，完整 canonical + h1 身份，然后真正 DOM 的 `a[data-m3u8]`；选线重新获取。三个普通样本中：一个 CDN TLS 自签名失败，一个 HLS 主/子清单 200 但子清单声明加密密钥（拒绝，不请求 key），一个 CDN 404。不能称当前样本可播。
- **第三方AVDB**：真实 `ac=detail&wd={number}&pagesize=5`，精确 `movie_code`，保留实际 id、版本、对象 `episodes.server_data.Full.link_embed`；详情重新核验；upload18.org 正常 embed 的 `window.PLAYER_CONFIG` 只读字面 JSON。三个样本精确链路成立，但 helvid.com 媒体 404。它不是用户应用 AVDB，更不共享 JavDB/115/TPDB 凭据。
- **MemoJav**：本站 `/video/{number}` 的 og:url+h1+实际 iframe，embed 声明 id；公开 `/static/main.js` 展示客户端时间戳证明，不含私钥或口令。独立重写为时间戳 Base64 的指定 10 字符与公开加权校验和；仅正常调用本站 `/hls/get_video_info.php`，不猜签名、不读取 IPA 凭据、不模拟广告。真实 START-642 得到 success/hls，正常一次 URL 百分号解码后 video10.memojav.net HLS **200**，920 个相对分片引用、无加密 key 声明，未请求任何分片。原生 macOS 同一 production provider 的另次结果由 CI 单独记录。
- **AV01**：公开站点 JS 明确 POST `/api/v1/videos/search?lang=en&include_facets=true`，query+pagination(page1,limit5)；普通请求确认 SSIS-001 对应真实 id42439，详情 dvd_id 精确成立。正常匿名 `/edge/geo.js?json` 返回站方短期授权结构，但 `comp=true`；不覆盖地域/合规策略，不输出/缓存授权值，不继续 CDN。原生实现真实搜索/详情/geo 阶段；动态授权清单改写尚未验证，返回访问受限或暂不支持，不冒充已完成可播。
- **MissAV**：真实公开搜索与精确详情 DOM 校验；只支持直接明文 HLS 候选识别。普通 TLS 信任链失败，不关闭验证。打包词表 reconstruction 未核实，不猜 URL、不执行 JS；尚无已批准实测媒体主机，因此清单阶段明确暂不支持。
- **Jable**：真实搜索 `/search/{number}/`、同源详情 `/videos/{slug}/`、canonical/og:url+h1 和 `hlsUrl` 静态解析。普通请求403，停止反爬边界；尚无已批准实测媒体主机，后续清单阶段明确暂不支持。

## App 集成和安全
真实 MovieDetailView 的“播放与下载资源”面板中六源手动查询，初次进入零请求；每次点击可见公开番号才发送给对应源。两源并发上限、来源独立状态/取消/错误，2分钟仅内存 metadata cache（不缓存媒体/短签直链），账号通知/片目/版本设置换代清空。选线再解析、验证主及最多6个子清单；单请求12秒、整次25秒；JSON 1MiB、HTML 2MiB、manifest512KiB。

媒体只接受实际样本精确主机和 HTTPS，按来源分组；无IP、账号、私网、任意跳转，重定向全部拒绝；清单中 URL 必须同主机且在根清单目录下。加密key、session-key、未验证外部音轨/子清单 fail closed，不请求分片/密钥。播放器只拿本来源 UA/Referer，未继承 PlayerViewModel 固定 JavDB Referer；不猜 Origin。服务器内容以后变化仍可能失败，不保证永久/免费或版权许可。

播放计划直接交给现有 KSChromePlayer；每次计划 UUID 创建独立播放器及一条既有三来源字幕管线，关闭沿用既有停止/取消逻辑；115 主入口和离线下载不改、不自动降级；226 详情原地边缘返回、225/220 等功能保留。中性 UI fixture 通过真实详情/真实解析器/清单检查后，最终媒体换为自制本地中性视频；并非真实站点首帧证据。

## 未完成与不宣称
这是六源 registry + 真实网络适配阶段、**不是六源全部可播**。AV01 动态授权清单桥接、MissAV 打包候选恢复和两站未知 CDN allowlist 尚未完成。真实成人媒体首帧不验证、不截图；仅完成合法匿名元数据和 HLS 清单验证。无VPS/Cloudflare/One/直播/新账单变更。
