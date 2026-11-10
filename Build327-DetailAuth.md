# Build 327 — 详情页登录令牌与可见鉴权错误

Base: Build 326 / 17b60998bfccae6ffbebd0f8f334edb31dd6859c, `feat/home-hero-hq-326`. MARKETING 1.0.2, build 327. Branch `feat/detail-auth-327`.

用户已登录，但从首页点进任一番号后只看到白底、橙色感叹号和「重试」。原因不是 326 英雄图管线，而是 `GET /api/v4/movies/{id}` 在未带 `Authorization` 时返回 HTTP 200 + `{success:0, action:JWTVerificationError, message:請登錄帳號}`。`movieDetail` / `movieDetailFull` 没有传 `useToken: true`，已登录用户也不会带 Bearer 令牌。失败文案用 `.foregroundStyle(.white)` 画在 `Color(.systemBackground)` 上，浅色模式下看不见。

方案先与 Muse（Kai）讨论（discussed with Muse / Kai），再共同修订（then jointly revised）。双方最终一致：详情请求带令牌；仅在 `setToken`（身份变化）时清空共享 URLCache；鉴权失败走现有 AppState「需要重新认证」策略（保留令牌、不调用 `logout()` / `setToken(nil)`、不自动重试失效令牌）；失败页用详情页自身的深色底加配对的 primary/secondary 前景，并提供「去登录」；登录成功后沿用已有 `.avdbCatalogAccountChanged` 通知重新加载当前影片。没有独立令牌刷新。按共同修订稿落地。7 个 Tab 合并、英雄区高清管线、可选失败页番号/标题/封面种子（推迟到 328）仍**刻意不做**。

## 改了什么

1. **详情请求带令牌**：`movieDetail` / `movieDetailFull`（`GET /api/v4/movies/{id}`）传 `useToken: true`。有令牌时 `cachePolicy` 为 `.reloadIgnoringLocalCacheData`（与 `movieReview` 相同），避免沿用匿名失败缓存；无令牌时保持默认缓存策略。`APIClient` 仅在令牌存在时附加 `Authorization`，不编造令牌。
2. **仅在身份变化时清空 URLCache**：`APIClient.setToken(_:)` 是唯一身份变化钩子（新令牌、退出/`nil`、切换账号），调用 `URLCache.shared.removeAllCachedResponses()`。将状态标为 `needsReauth` 不是身份变化（同一人、凭证保留），不得清缓存。不做按账号分层的缓存。
3. **错误分类 + 去登录 + needsReauth（不清除令牌）**：
   - 鉴权类：`action == JWTVerificationError`，或 HTTP 401，或文案为「請登錄帳號 / 请登录帐号」及同类需要登录的文案。
   - 其它（网络、5xx、解码失败等）：只显示服务端/错误文案和「重试」，没有登录按钮。
   - 鉴权类 UI：服务端文案 +「重试」+「去登录」。若当时已有令牌，走 `AppState.markNeedsReauth()`：`sessionStatus = .needsReauth`，`isLoggedIn = false`，保留已存凭证，不调用 `logout()` 或 `setToken(nil)`，不自动重试失效令牌。
   - 「去登录」以 sheet 呈现现有 `LoginView`（与「我的」/ 演员页相同）。
   - 登录成功后 `APIClient.setToken` 仍会发 `.avdbCatalogAccountChanged`。详情页已有订阅；处理函数改为 `await vm.load()` 重新加载当前影片。退出登录走同一通知也可以，届时可能再次显示鉴权错误。
4. **可见的失败样式（配对色）**：失败态背景改为详情页自己的深色页底（与成功态 `legacyDetailBackground` 同一套），文案用配对的 `.primary` / `.secondary`，并在失败容器上使用 `.colorScheme(.dark)`，避免先闪白再闪回深色。保留橙色感叹号。不再把硬编码白色文字画在不受控的系统背景上。
5. **测试**：`scripts/test-detail-auth327.py` 静态契约；`DetailAuth327Tests` 覆盖无令牌/有令牌的 `Authorization` 与 cachePolicy、生产 JWT 失败载荷（HTTP 200 + success:0）必须判为鉴权失败、带令牌时 ViewModel 能加载影片（无真实网络）；UI 测试检查错误文案存在且非空，以及鉴权类显示「去登录」、非鉴权类不显示。不在 UI 测试里断言颜色对比。测试接入现有 `home-hq298.yml`（静态进入 zzt-ranking / release 回归；专用 `detail-auth-327` 任务跑单元 + UI）。326 英雄截图任务保留。

## 刻意推迟

- 首页英雄区高清管线（HeroCoverResolver / HeroCoverStore / 内嵌卡）不动。
- 底部 7 Tab 合并。
- 可选 CoverSR 后处理。
- 失败页最小种子（番号/标题/封面）推迟到 Build 328。
- 不改写登录流程，不发明令牌刷新。

Tests: `scripts/test-detail-auth327.py`（静态契约）；`UITests/DetailPosterQualityTests.swift` 中的 `DetailAuth327Tests`；`UITests/PosterNavigationTests.swift` 中的 `test327DetailAuthErrorMessageVisible` / `test327DetailAuthLoginButtonPresence`；生产失败载荷 `scripts/fixtures/detail-auth-jwt-error.json`。
`scripts/package-lut327.py` → `AVDB-unsigned-1.0.2-327-detail-auth.ipa`；workflow artifacts `AVDB-327-*`；`detail-auth-327` 任务上传 `AVDB-327-detail-auth-tests`。`home-hero-hq-screenshots` / `test326HomeHeroHQScreenshots` 路径保留。
