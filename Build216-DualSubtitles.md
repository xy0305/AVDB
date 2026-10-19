# Build 216 · 同时启用迅雷与 SubtitleCat

- 用户只需一次点击「搜索（同意发送本次查询词）」，两源独立匿名请求并行，结果逐源出现，错误状态分别显示。不是 provider 单选模式。
- 每源最多 80 个候选，缓存键为来源 + 可见查询词，120 秒；最多保留约 40 个缓存键。不会预抓所有详情，不会自动选择或下载。
- SubtitleCat 候选标注「待选语言」，点击候选只读语言详情，在原结果下面显示实际下载 href 的语言（简体 zh-CN、繁体 zh-TW 优先，其他按真实码；最多 120 条）。只有用户点语言才下载 SRT。Translate-only 不调用翻译、上传或 JS。
- 使用 AVDB 自有惰性、无脚本 JRHTML 树。下载取页面真实 href，支持跨目录、空格、中文及已有百分号编码，不猜目录，不全 URL 解码。
- 明确请求种类：迅雷 JSON、SubtitleCat 搜索 HTML、详情 HTML、文本字幕。HTML 仅用于元数据；字幕拒绝 HTML/ZIP，元数据 1 MiB / 字幕 8 MiB 流式上限，15 秒请求 / 25 秒资源超时；同类型重定向最多 5 次，SubtitleCat 下载仅可保持绑定 href。
- 请求仅允许 HTTPS 精确主机、443、无账号密码。全新 ephemeral session、不共享 Cookie、credential、115 headers 或 TPDB 信息，标准系统 TLS，无 WAF/验证码 solver。
- 新搜索、编辑查询、换视频 URL、关闭字幕或面板，取消关联工作并使 generation 失效；已失效响应不能修改结果、语言或 cues。关闭面板保留已加载；关闭字幕清空 selected/cues。选择新字幕失败时保留上一次可用字幕，始终只有一个 cues 数组播放。
- 原选中候选框绿勾/绿边与加载成功提示保留，语言在原 section 展开，不整页替换。保留字幕字号、位置、微调、偏移、编码选择与播放器手势隔离。
- 保留 Build 215 实际分辨率、Build 214 TPDB、Build 213 JavBus 与 Build 212 播放菜单；没有改动这些功能源码。

## 自动验证

`scripts/test-online-subtitles.py` 在 macOS CI 编译实际 `OnlineSubtitle.swift`、`OnlineSubtitleModel.swift`、`SubtitleCatProvider.swift` 与完整生产 `JavRankingCore.swift`，无 DOM stub。除既有 SRT/VTT/ASS、UTF-8/GB18030/Big5、时间轴/偏移回归外，强制执行双源模型与传输测试：跨目录 href、Unicode/已编码空格、简繁分离、同名不同 ID、Translate-only、challenge 200、外链/私网/类别与跳数、未绑定字幕、HTML/ZIP 伪装、元数据/字幕流式超限、gzip 解码字节与压缩长度不混淆、先后顺序反转、单源失败独立显示、cache 命中、查询/关字幕/换片清除与晚响应、无自动详情/下载、仅手选语言才加载。

本机 Linux 没有 Swift 编译器；本机静态检查通过不等于 Swift 或 UI 测试通过。构建验收以精确远端提交的 macOS CI 结果为准。没有宣称真机 UI、真人视频同步、中文官网 SRT 编码、PiP/AirPlay 已实测；需签名安装后人工验收。

## 参考及许可

独立 Swift/DOM 实现，没有复制第三方解析器代码、没有引入 cloudscraper 或 JS 依赖。协议研究参考：
- MIT：se bvannistel/PolyglotSubs-Kodi（实际仓库 `sebvannistel/PolyglotSubs-Kodi`），固定树 `a79d25a46caac7a35a7cabaa4519aa2a714bdd46`，`a4kSubtitles/services/subtitlecat/request.py`。
- 只用于辨别资料、未移植：sqzw-x/mdcx 本地复制字幕工具（GPL-3.0）；warren-bank/subtitlecat 历史下载器（GPL-2.0，未采用其 insecure TLS）。
- 开源代码许可不代表站方 API 或字幕内容授权。本功能不镜像再分发字幕、不自动翻译/上传；站方访问验证或 403/429 明确停止并提供外部原站入口。
