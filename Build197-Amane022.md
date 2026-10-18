# Build 197 — Amane v0.22.0 适用项独立审查

## 基线与许可边界

- 2026-10-18 正常 TLS GitHub API 实查 `xy0305/AVDB/main`：`e088360f32ea5ce062646965a7a2a7ceb2766521`，build196。独立工作区 `/var/minis/workspace/AVDB-amane022`，由该 SHA 的 API tarball 恢复，再重建并核验相同 SHA 的 `.git` 对象。git HTTPS 的本地 CA 链失败没有通过关闭验证绕过。
- 对照真实 [v0.22.0 release](https://github.com/sqzw-x/amane/releases/tag/v0.22.0)，逐项核对 PR 的 merge/head SHA 与 files；#472 是 issue，不是 PR。
- Amane 的 GitHub license API 标注 GPL-3.0。只借鉴公开问题所描述的行为及互操作规格；没有复制其 Python/TS/CSS、测试代码、图片或夹具，没有逐行翻译其实现。这里的改动是对 AVDB 自己的 UIKit、SwiftUI、ImageIO 与 SDK 的独立修复。不改变 AVDB 已有依赖的许可义务（例如 KSPlayer GPL）；本说明不声称整套应用因此摆脱 GPL，也不是法律意见。
- 不改196高清日亚、195关闭字幕/白按钮、192原大图/标题三行开关、MissAV返回状态、115、LUT和FC2原图策略。不删除或放宽旧字幕/旋转 UI 失败断言。

## 九项逐项判断

| 上游条目 | AVDB判断与处理 | 核对过的固定源码 |
|---|---|---|
| mgstage剧情/剧照及素人不取化名 #472/#495 | 不适用。AVDB目前只生成/使用MGS图片URL，不刮其详情页剧情、剧照或出演者。不为追随修复新增整站元数据爬虫。 | [mgstage.py@a666a8a](https://github.com/sqzw-x/amane/blob/a666a8a2f1d6d2695bd43dda156b866bc061af81/src/amane/crawlers/sites/mgstage.py)；[#472 issue](https://github.com/sqzw-x/amane/issues/472) |
| FC2两变体/下架误判 #470 | 部分加入。真实路径是MissAV/外部榜单 → `JavDBSDK.exactMovie` → `JRPolicy.movieCode/exactCode`及账户隔离的精确候选缓存。旧规则接受PPV但拒绝`FC2-<id>`，因此完整商品身份出现假阴性。只将FC2完整两种拼写归为同一个精确键，数字串原样保留；不同商品、非FC2、裸数字、嵌入或尾随字符拒绝；多影片ID依旧歧义报错。未加入上游的官方商城存在性/下架检查，因为AVDB没有这个接口。 | [parsing.py@5e4d3b8](https://github.com/sqzw-x/amane/blob/5e4d3b85d9de65ab5996e0659924204f3c68e0bf/src/amane/crawlers/parsing.py)；[merge@c88e3f1](https://github.com/sqzw-x/amane/commit/c88e3f1b160b37e7d25d5d8c5685a2e34aa5c8ef) |
| freejavbt解析 #470 | 不适用，没有freejavbt详情爬取链。不新增站点。 | [freejavbt.py@5e4d3b8](https://github.com/sqzw-x/amane/blob/5e4d3b85d9de65ab5996e0659924204f3c68e0bf/src/amane/crawlers/sites/freejavbt.py) |
| 分块下载参数 #494 | 按用户要求排除，不修改任何下载配置、传输或115代码。 | [http.py@3c47173](https://github.com/sqzw-x/amane/blob/3c4717384210a6af14ba8b19f4adce5f3766edfa/src/amane/net/http.py) |
| 演员墙滚动跳变 #467 | 按用户要求排除，不修改演员页、网格滚动、任务生命周期或分页。本轮临时新增的演员相关修改及测试已撤回；最终相对build196没有演员墙差异。 | [actor-grid.tsx@0e7d855](https://github.com/sqzw-x/amane/blob/0e7d855e048bc5600bbd8e4030b70841fe027966/web/src/components/media/actor-grid.tsx) |
| 慢盘DB批写/调度器恢复 #464 | 按用户要求排除，不修改数据库、批写、调度或崩溃恢复，不添加基础设施。 | [engine.py@7515f4f](https://github.com/sqzw-x/amane/blob/7515f4f944fcd92fb9c386215af6246079d7a49e/src/amane/db/engine.py)；[worker.py](https://github.com/sqzw-x/amane/blob/7515f4f944fcd92fb9c386215af6246079d7a49e/src/amane/scheduler/worker.py) |
| 海报裁剪失败 #463 | 上游的RGBA源以`.jpg`目标写JPEG失败不适用：AVDB用ImageIO识别字节、应用EXIF，CGImage内存裁剪，不按URL后缀编码JPEG。本次不无意义强制去alpha。补RGBA PNG冒充JPG URL的真实裁剪输出/边界/无效候选不能胜出测试，并修真实邻接缺陷：`JavDBImage`的State保留上一来源图片，新来源失败时旧图永久留下；现在按请求身份显示；来源替换和图片发布都禁用继承动画，避免新来源失败时旧图仍在淡出；同一身份取消后再入不清空。 | [images.py@387a245](https://github.com/sqzw-x/amane/blob/387a2458536a34fcbe08ea6094702500b3b82b43/src/amane/media/images.py) |
| 无码筛选漏未标记 #465 | 不适用。上游将content_type从文件迁到条目，联合文件phase筛选。AVDB的JavDB目录类型/标签由服务端提供，没有这套文件相位/本地元数据表。不按图片或番号猜测无码，不擅改服务端分类含义。 | [metadata.py@936a4b3](https://github.com/sqzw-x/amane/blob/936a4b368d102e608b75427981599d0c4e5e6e34/src/amane/db/repos/metadata.py) |
| 播放器误触 #490 | 按用户要求排除，不修改播放器、字幕、手势或控件。本轮早先探索提交中的播放器修改已在正常快进后续提交撤回，旧生产代码与旧失败断言原样保留。最终diff相对build196不含播放器变化。 | [playback-player.tsx@PR490 merge](https://github.com/sqzw-x/amane/blob/27825d1bb642f9eb6c46f4635d5e7f52752a4ee4/web/src/components/media/playback-player.tsx)；[CSS](https://github.com/sqzw-x/amane/blob/27825d1bb642f9eb6c46f4635d5e7f52752a4ee4/web/src/components/media/playback-player.module.css) |

## 测试与验收诚实边界

- iSH仅执行Python静态契约/捕获响应检查；本地没有Swift/iOS SDK，不能将skip称为编译通过。
- 新增生产SDK的FC2正反变体/不同商品/非FC2/裸ID/尾缀/多ID歧义回归；旧的“短写必须nil”规格明确改为两变体等价，并增加不同ID和裸ID拒绝断言，不改字幕UI断言。
- 新增`Amane022RegressionTests`：真实ImageIO/CGImage裁剪RGBA PNG字节（URL为JPG），输出376x538；非法尺寸和无效候选不能胜出；hosted真实JavDBImage从有效来源切到失败来源后必须由彩色旧图变成中性占位，不得错误winner；宿主frame不变。既有EXIF/完整解码/赢家缓存/取消回归保留。
- 双设备专项workflow使用macOS实际Swift、iPhone/iPad Simulator及Xcode test；发布IPA由原Build IPA生产链编译。最终结果以对应SHA的Actions结论和原始日志为准，另交付验收报告，不在提交前预写成功。
- 195/196已有字幕触控、重选与iPhone详情旋转失败仍是待验收问题。原全套workflow与断言完整保留；专项成功也不代表旧全套全绿。
