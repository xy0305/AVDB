# Build 200 — 从197重新实现同片封面择优

基线：GitHub API 确认 main `1c64bf1de21ddb92d47ee8deef21e09b00b574c2` tree `a44bf102c26357c19d4708d2cb4b2ba3a7a5b4c4`，逐树等于 build197 `0ba86ce35b4a39ba498e6d8bfb298c00946488bf`。不是恢复198/199。

## 比旧方案变化
- 官方 OpenAPI `site` 是站名（如 `Vixen`），`site_id` 才是数字；修正旧实现 `site=202` 的错误。
- 不再限制 Blacked Raw 单样本。显式映射 Blacked Raw、Blacked、Vixen、Tushy；其他品牌明确未支持，不做演员/日期单字段匹配。
- 优先已有 TPDB UUID 或完整官网 URL，严格品牌、原始标题（存在时）、时长（存在时）交叉校验。无精确 ID/URL 必须品牌+日期+英文原始标题+时长且唯一；重复、冲突或分页未穷尽拒绝。不推断日期冲突为时区。
- 只读 TPDB image/background.full；拒绝 smart/upscale/sharpen 派生图。欧美 JavDB thumb/cover 也实解比像素，横原图不竖裁；图片最多6张、2并发、12秒，发现与图片下载并行、单赢家发布。非欧美原裁切规则不变。
- 默认关闭，设置明确需点保存；Keychain SecureField 保存/清除/测试已保存 Token。保存/清除更换随机缓存namespace并取消旧缓存flight，账号隔离；不内置研究Token。
- 详情评分下来源来自实际winner或实际fallback加载回调，附原始/有效像素；点按复制URL移除user/password/query/fragment。静态精确host映射，不用contains伪装来源。
- 诊断区分未启用/无Token（未请求）、HTTP鉴权拒绝、超时、同片冲突、年龄页、外源发现及已解码但未胜出。发现元数据不宣称图片已加载。
- MGStage 此次三个完整番号正常TLS GET均为年龄页，未启用新详情adapter或虚构成功。旧pf_e/pf_o1规则不计新增，Tenhow/日亚机会保持不变。

## 快速公开源码核对（只参考行为，不复制表达）
1. https://github.com/metatube-community/metatube-sdk-go/blob/main/provider/theporndb/video.go ：GetMovieInfoByID、SearchMovie，scenes/movies分开，搜索返回候选供选择，而非自动取第一条。
2. https://github.com/xbapps/xbvr/blob/master/pkg/scrape/tpdb.go ：ScrapeTPDB 从TPDB场景URL取identifier，Bearer查询，读取data.image。它的VR固定类型不能直接作通用2D适配。
3. https://github.com/ThePornDatabase/stash_theporndb_scraper ：sceneQuery、manuallyDisambiguateResults、sceneHashQuery。仍有metadataapi.net旧域名，hash调用存在支持边界，不复制旧域名到新接入。
4. https://api.theporndb.net/docs/specs?openapi.json ：本次直接GET404；参考此前正常获得官方OpenAPI v3.24.757并以本次实际Bearer请求交叉核验site/url/title/date字段。不能声称本次文档端点HTTP200。

## 真实四品牌样本（正常TLS完整GET/Pillow decode；图片无鉴权头）
|品牌|场景|日期|UUID|image/background.full实际像素|
|---|---|---|---|---|
|Blacked Raw|Sultry Ava Manhandled|2026-10-13|4d2c0748-71ea-4f1b-b486-94db042c7b34|1920×1080 / 1920×1080|
|Blacked|Rival Beauties Share BBC|2026-10-15|8b7d3b6b-6c5f-4d8f-b2bb-5a371d695ea7|1920×1080 / 1920×1080|
|Vixen|Fiesty Babe Bangs Her Boss|2026-10-14|59b402cc-306b-4a85-adda-5829fc422b27|1920×1080 / 1920×1080|
|Tushy|Nicole Goes All Anal|2026-10-11|30d23043-6ed0-4bc1-900c-849a4a360f5a|1920×1080 / 1920×1080|

Blacked Raw精确官网：https://www.blackedraw.com/videos/sultry-ava-manhandled 。TPDB/Data18索引10/13，先前官网10/14冲突保留；精确URL可佐证同片，不自动解释时区。时长2091秒。smart poster 800×1200拒绝。

Data18本次公开搜索HTTP200唯一找到上述场景；直接无Cookie详情GET403，浏览器公开页可显示真实img#playpriimage（640×360），正常点击Gallery#0显示实际bdn链接 https://bdn.dt18.com/338/3117/398670/0.jpg （既有完整解码1000×562）。生产不复用浏览器Cookie，不伪造Stashdata_user_captcha，不从scene ID算Gallery路径。静态HTML没有真实Primary href时仅保留主图，不保证客户端能取得1000×562；403/年龄页可见诊断。

MGStage：https://www.mgstage.com/product/product_detail/300MIUM-1150/ 、200GANA-3159、ABW-001 三页均HTTP200但6349字节年龄确认页；没有真实产品封面像素证据，因此未强接新的数字前缀规则。

更高原生像素不保证压缩/观感最好；本次没得到可公开比较的JavDB同片原图，不宣称TPDB一定胜出或覆盖全站。所有研究Token仅运行时环境PORNDB→api.theporndb.net Bearer，拒绝重定向，未进入代码/IPA/fixtures。

## 验收
本地无swift/swiftc：只能执行静态检查，原生执行SKIP，绝不算原生测试通过。GitHub macOS工作流执行Release及双设备中性设置/来源、身份/冲突/原像素/迟到高图/缓存清除测试，保留字幕旋转测试。终态结果及IPA哈希以最终交付报告为准。
