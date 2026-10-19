# Build 214 — 可选 ThePornDB 欧美横版封面

- 基于本地 20c0a82，保留 213 JavBus 候选、212 紧凑播放器菜单及 211 双击行为；不修改日系解析、日亚/DMM 的 6 槽/2 并发/12 秒预算、播放按钮样式或列表图。
- 我的 → 来源 → 欧美封面 / ThePornDB：默认关闭；SecureField 手动填入个人 Token；仅本机 ThisDeviceOnly Keychain；可清除。环境 PORNDB 仅用于外部授权验证，未写入源码、配置、报告或安装包，也未替用户写入 App 钥匙串。
- 独立 landscape 路径，最多 2 个 metadata + 2 个原生图片请求，12 秒总预算，每个请求最多 5 秒；metadata 各 1 MiB、图片各 8 MiB，合计最多 18 MiB；每张图最多两次白名单 HTTPS 跳转。API 全部拒绝跳转，Bearer 仅限 api.theporndb.net。图片无鉴权、无 Cookie；标准系统 TLS，未实现 TLS 绕过。
- 尝试 Blacked Raw、Blacked、Vixen、Tushy 单场景；需明确欧美 type=2、品牌日期编号、英文原题、分钟时长及无冲突日期。有确切 original_url 时用官方 URL 查询，否则标题+规范站名+日期查询；必须完整单页、严格唯一匹配，复查 UUID 详情的品牌/原题/日期/时长/官方 URL/external_id。缺失、歧义、冲突、限流等均保留 JavDB。
- 只读 image / background.full 原生横图；拒绝 smart / upscale / sharpen / 派生 poster。检查图像完整性与实际像素，最多 20M pixels，缩略解码上限 2048；以两个候选的原生面积择优，等面积优先片商 image。原比例显示，不进 DVD front 评分或右裁。
- 5 分钟正缓存、30 秒负缓存；账户隔离，令牌/开关变更生成随机 namespace，清空缓存并取消旧任务；界面也校验完整请求键后一次发布。设置页提供 401 / 403 / 429 / 网络 / JSON 等不含凭据的诊断；403 不被武断标记为失效 Token。

## 正常 TLS 实网验证（2026-10-19）
使用现有 PORNDB（仅报告 set）直接请求当前官方 API：
1. GET /scenes/4d2c0748-71ea-4f1b-b486-94db042c7b34 → HTTP 200，完整 JSON 17,442 bytes。
2. /scenes?url=精确官方URL → HTTP 200，唯一返回该 UUID。
3. App 同款 title + site=Blacked Raw + date=2026-10-13 → HTTP 200，完整一页、唯一返回该 UUID。
作品核对：Sultry Ava Manhandled，Blacked Raw，2026-10-13，2091 秒，external_id=blackedraw:sultry-ava-manhandled；官方作品地址 https://www.blackedraw.com/videos/sultry-ava-manhandled 。这不是按模糊标题取首条。
- image：HTTP 200，324,089 bytes，完整 Pillow 解码 1920×1080。
- background.full：HTTP 200，162,495 bytes，完整 Pillow 解码 1920×1080。
- poster 为 800×1200 smart/sharpen/upscale/watermark URL，未请求、不当原生竖封。
所有图片独立无鉴权、无 Cookie；未内联展示或描述图片内容。仅验证这一场景，不能外推四品牌完整覆盖，也没有 JavDB 同片像素对照，不能宣称一定更高清。

## 公开参考及许可
- 官方 API 文档：https://api.theporndb.net/docs
- 官方 OpenAPI：https://api.theporndb.net/specs?openapi.json （本地已下载文档，读取 SceneSearchRequest 的 URL/title/site/date/per_page 及 SceneResource 字段）
- 官方 Stash 插件：https://github.com/ThePornDatabase/stash_theporndb_scraper/blob/master/scrapeScenes.py
- 许可：https://github.com/ThePornDatabase/stash_theporndb_scraper/blob/master/LICENSE
本轮通过 GitHub API 正常 TLS 实际读取源码 blob f48dbd6a56b4dfa806407b7502052e56baf3d2df 与 LICENSE blob b5796a32eab0fff9c16fd2330c70ce09b01c0955：MIT，Copyright (c) 2020 pierre-delecto。参考其 Bearer 与 background.full 行为；Swift 协议独立实现，无复制或逐句翻译第三方实现，未复制 GPL。旧插件 API 域名不被照搬。软件许可不等同于第三方图片再分发许可。
直接 raw.githubusercontent.com 的 curl 曾因本地证书链 curl 60 停止；未 -k，改用正常验证的 GitHub API 读取公开源码。TPDB API/图片本身正常 TLS 成功。

## 测试边界
scripts/test-detail-posters.py 强制调用 test-tpdb-posters.py，保留原 JavBus 与所有旧测试。新增实际生产 Swift policy/cache 测试覆盖 host/header、API redirect 拒绝、无鉴权图片、假无效 Token/错误 JSON、精确匹配歧义/品牌/日期/分页、原图与派生、横图隔离、旧 generation 取消与未知身份回退。本地 Alpine 无 swiftc，只跑静态安全检查；实际 Swift 执行与 Release 编译交由 macOS CI，不冒充真机验收。
