# AVDB

JAVDB 第三方 iOS 客户端（SwiftUI + iOS 17+），一比一复刻 JAVDB 官方 App 的界面与功能。

基于 [Brokye/JAVDB-APP-API](https://github.com/Brokye/JAVDB-APP-API) 逆向的官方 App 全量 API 构建。

## 功能

- 🏠 **首页** — 热门搜索词、分类标签、推荐、最新发布、排行榜
- 🔍 **搜索** — 关键词/番号搜索、磁力搜索
- 🎬 **影片详情** — 封面、剧照、标签、演员、简介、影评、相似推荐
- ▶️ **播放** — HLS 多清晰度（1080p/720p/480p/360p）、多集切换、续播
- 🧲 **磁力链接** — 磁力列表、复制、下载
- 👤 **演员/片单/系列/片商** — 完整浏览与详情
- 🔐 **登录/VIP/会员/钱包** — 用户态接口
- 🔓 **图片解密** — 自动解密 CDN 单字节 XOR 加密流

## 技术要点

### 签名算法（每个请求必须）

```
jdsignature = "{timestamp}.lpw6vgqzsp.{md5(str(timestamp) + STR1)}"
```

- `STR1` / `STR2` 为逆向得到的固定常量
- 时间戳为当前 Unix 秒，逐请求实时计算
- 详见 `AVDB/Networking/JavDBSignature.swift`

### 必带 Query 参数

```
platform=android&app_channel=official&app_version=official&app_version_number=1.9.35&system_version=13
```

### 图片 CDN 解密

`tp.spfcas.com` 返回单字节 XOR 加密流：`enc[0]` 为密钥，`enc[i] = plaintext[i-1] ^ key`。

详见 `AVDB/Services/ImageLoader.swift`

## 架构

```
AVDB/
├── AVDBApp.swift              # 入口
├── Models/                    # 数据模型（snake_case 兼容 API）
│   ├── Movie.swift           # 影片/标签/演员/磁力/排行榜/影评等
│   └── User.swift            # 用户/登录/会员/钱包
├── Networking/
│   ├── JavDBSignature.swift  # 签名算法 + 图片解密 + 常量
│   └── APIClient.swift       # HTTP 客户端（签名/鉴权/响应解析）
├── Services/
│   ├── JavDBSDK.swift        # 全端点 SDK 封装（50+ API）
│   ├── ImageLoader.swift     # 图片加载/解密/缓存
│   └── MovieListViewModel.swift # 分页列表 VM
└── Views/                     # SwiftUI 界面
    ├── ContentView.swift     # Tab 导航
    ├── Home/                 # 首页
    ├── Search/               # 搜索
    ├── Detail/               # 影片详情
    ├── Player/               # HLS 播放器
    ├── Actors/               # 演员
    ├── User/                 # 用户中心/登录/会员/钱包
    └── Components/           # 通用组件
```

## 已实现的 API 端点

### 搜索类
- `GET /api/v2/search` — 主搜索
- `GET /api/v2/search_image` — 以图搜图
- `GET /api/v1/search_magnet` — 磁力搜索

### 影片 / 元数据
- `GET /api/v4/movies/{id}` — 详情
- `GET /api/v1/movies/{id}/magnets` — 磁力列表
- `GET /api/v1/movies/{id}/play` — 视频流（VIP）
- `GET /api/v1/movies/{id}/resume_play` — 续播
- `GET /api/v1/movies/{id}/reviews` — 影评列表
- `GET /api/v1/movies/latest` — 最新发布
- `GET /api/v1/movies/top` — 排行榜
- `GET /api/v1/movies/tags` — 标签
- `GET /api/v1/movies/recommend` — 推荐
- `GET /api/v1/movies/recommend_periods` — 推荐时间段
- `GET /api/v1/movies/may_also_like` — 相似推荐

### 演员 / 导演 / 系列 / 片商 / 发行商
- `GET /api/v1/actors`、`/api/v1/actors/{id}`、`/api/v1/actors/recommend`
- `GET /api/v1/directors/{id}`、`/api/v1/series/{id}`、`/api/v1/series/letters`
- `GET /api/v1/makers`、`/api/v1/makers/{id}`、`/api/v1/publishers/{id}`
- `GET /api/v1/rankings`、`/api/v1/rankings/actors`、`/api/v1/rankings/playbackP`

### 片单 / 标签 / 影评 / 文章
- `GET /api/v1/lists`、`/api/v1/lists/simple`、`/api/v1/lists/related`、`/api/v1/lists/{id}`
- `GET /api/v1/following_tags`、`/api/v2/tags`、`/api/v1/reviews/hotly`、`/api/v1/articles`

### 登录 / 用户
- `POST /api/v1/sessions` — 登录
- `GET /api/v1/users`、`/api/v1/users/recent_viewed`
- `GET /api/v1/users/collected_*` — 收藏（actors/codes/directors/makers/series/lists）
- `POST /api/v1/users/feedback`、`/api/v2/users/review_movies`、`/api/v2/users/{id}/reviews`

### 上报 / 广告 / 其它
- `GET /api/v1/startup`、`/api/v1/about`、`/api/v1/helps`、`/api/v1/ads`
- `POST /api/v1/logs/movie_played`、`POST /api/v2/logs/activated`
- `GET /api/v1/magnet_apps`、`/api/v1/codes/{id}`、`/api/v1/codes/{id}/collect_actions`

### 会员 / 钱包
- `GET /api/v3/plans`、`/api/v4/plans`、`/api/v2/plans/payment_order`
- `GET /api/v1/wallets`、`/api/v2/wallets/withdraw`、`/api/v1/wallets/withdraw_logs`

## 构建

```bash
xcodebuild build -project AVDB.xcodeproj -scheme AVDB \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

## 免责声明

本项目仅供学习研究使用。使用本软件产生的任何后果由使用者自行承担。请遵守当地法律法规，尊重知识产权。

## License

仅供学习研究，请勿用于商业用途。
