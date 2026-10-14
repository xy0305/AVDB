# Build 179 · 原生 JAVLibrary 排行

## 基线与撤销范围

开始时远端 main 为 `5c9178a`（build178 诊断系列），本地旧副本为 `ebe3020`（build177）。先 fetch、快进到当前远端，再按最新到最旧以普通 revert 撤销 `5c9178a`、`3030374`、`b1d4668`、`fadd33b` 四个诊断提交；不 reset/force-push 远端，不移除 build177 Keychain 设置与其他功能。新构建从179顺增，避免与已发布178同名。新功能将默认地址校正到用户已确认的8000端口；已保存地址/令牌不自动改写。没有恢复178连接诊断页面。

## 入口与语义

「排行 → JAVLibrary 最想要 / 高评价 / 女优收藏」为新增 SwiftUI 原生来源，保留 JavDB 全部榜、JAV Ranking、MissAV 全部榜；没有 WebView。JAVLibrary 仅决定榜单顺序、rank及来源身份。所谓“替换我的数据”只指卡片显示 AVDB 当前数据源的资料，绝不把排名改为 AVDB / MissAV 排名，也不替换服务器数据库。

当前服务独立快照：mostwanted100条/5页、bestrated100条/5页、actors20条/1页。服务器北京时间00/08/16自动抓取；不是日榜/周榜/月榜。App GET整份快照，首次显示25条，再按服务器数组原序每次增加25条，不向API虚构分页参数。保留真实rank（不根据匹配完成顺序重新编号）。返回详情保留快照、已加载数量及滚动位置。下拉刷新只重读服务器快照，不触发爬虫/订阅/下载。

## 已核对的服务器 API/schema

只读核对 `/opt/avdb/javlibrary/avdb_javlibrary.py`、README、独立 SQLite；没有改动服务器服务。

- Web运维入口 `http://163.47.40.207:8000/online-resources?tab=ranking`，不是App数据接口。
- `GET /api/v1/javlibrary/rankings?kind=mostwanted`
- `GET /api/v1/javlibrary/rankings?kind=bestrated`
- `GET /api/v1/javlibrary/rankings?kind=actors`
- 原 AVDB `api_key_or_jwt` 鉴权；App复用 `X-API-Key`。匿名现场 GET 返回401。本次没有读取真实令牌或进行真实授权账户登录。
- 响应 `{code:0,message:"success",data:{source:"javlibrary",kind,entity_type,fetched_at,source_url,pages,count,stale,last_attempt,items}}`。
- `last_attempt` 为可空对象，字段 `attempted_at`、`ok`（SQLite整数0/1）、`error`；App只显示安全的失败/过期提示，不输出服务error正文。
- 影片 item：`entity_type:"movie",number,title,poster,banner,source_url,rank,in_library,local_tid`。
- 演员 item：`entity_type:"actor",name,avatar,source_url,rank`；未来显式 `aliases:[String]` 同样可解析。
- `poster/avatar/local_tid` 不是AVDB封面或JavDB ID，不用于详情身份。
- 严格校验source、请求kind、entity、count、唯一来源ID、正数递增rank、容量上限；非200/格式变化明确可重试，不把异常当成功空榜。显示抓取时间与过期/最近失败状态。

只读现场快照UTC时间分别为2026-10-14 13:32:13、13:32:31、13:32:34；SQLite integrity_check=ok。公开榜来源分别是 `vl_mostwanted.php`、`vl_bestrated.php`、`star_mostfav.php`。

## AVDB资料映射和安全边界

影片使用完整番号 `JRPolicy.exactCode` → 现有 `JavDBSDK.exactMovie(verifyAllPages:true)`，有界核对前3页搜索中的完整番号、非空有效ID、歧义拒绝；不按标题模糊匹配、不取第一条。封面/标题复用 `MoviePosterCard`/`JavDBImage` 现有管线；成功打开 `MovieDetailView(movieID:)`。未匹配保留来源标题、番号、rank并提供重试/原生搜索；不能把网页、流或local_tid当115资源。

演员复用现有精确Unicode宽度/大小写/空白与显式别名核对，只在查询预算内唯一精确匹配时使用 `ActorDetailView(actorID:)`。模糊/多个精确/分页预算耗尽均提供原生候选列表或原生姓名搜索，绝不自动绑定模糊第一条。别名超出3项查询预算时不声称自动唯一。

复用参数化后的 `MissAVMetadata` 成熟队列而非复制第二套：每个来源独立view-owned缓存，最多2个并发、身份去重、最多256结果、有界演员查询；注入来源代际和显示名称。JAVLibrary禁用任何MissAV详情/别名补全，缓存和请求不混来源。刷新、账户/令牌切换、配置变更取消并丢弃旧响应；离开取消未完成匹配，返回可重新排队，失败可重试。已有MissAV默认语义保持不变。

设置复用「我的 → 来源 → 外部数据库」（榜单右上角齿轮同入口）。默认新安装地址8000；已有18000等地址不会迁移，需用户自行修改并按安全规则重新输入令牌。首次仍默认关闭/无令牌；缺配置显示明确提示，不发请求。令牌留在Keychain；只在请求头发送，不写源码、URL、UserDefaults、日志。复用无Cookie/无凭据/无缓存的隔离URLSession，拒绝所有重定向，错误不回显服务器正文。HTTP仍未加密，应优先配置可信HTTPS。

115真实磁链、用户主动推送、Cookie/目录、原生详情均走既有流程；没有进行115写入/登录/订阅/删除。未修改播放器LUT/音频/手势。

## 验收

`scripts/test-javlibrary.py` 在macOS编译执行真实Swift解析器、真实安全传输与真实共享队列：三类schema/异常schema、非连续原始rank和分页切片、401/凭据头、完整番号规则、唯一演员/歧义候选、无MissAV跨源补全、最多2并发/去重/完成乱序不改排名、来源代际/账号隔离、取消/重入/重试。`test-external-library.py` 继续执行Keychain stub、设置变更取消、重定向委托等安全测试；原MissAV与JAVRanking映射回归继续运行。

扩展既有iPad CI：DEBUG合成快照经生产decoder解析、生产网格/分页/图片管线，在窄宽窗口点击第28张封面并返回，检查页序与位置；仅目的详情替换为中立视图，禁止触发真实账户或115。fixture不是生产数据、不代表真实账户成功率或真机验收。iSH无Xcode/Swift，离线本地仅静态检查；实际Swift运行时、iOS编译与模拟器结果以对应commit的GitHub Actions为准。

仍需用户真机验收：本机Keychain令牌与实际网络、受保护API200、AVDB账号映射命中率、真实图片、115主动合法磁链流程；本次没有声称完成这些项目。
