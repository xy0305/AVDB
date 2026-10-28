# Build 274 — 糖心分页 HTTP 307（尾斜杠）

Base tip includes Build 273 Amazon HQ. Version stays 1.0.2 / project build 266 (preview artifact naming unchanged).

## Root cause

- 精选首页 HTML 的真实下一页是 `https://tangxinvlog.app/featured/2`（**无**尾斜杠）。
- 线上对该路径返回 **HTTP 307** → `Location: /featured/2/`；带尾斜杠的 `/featured/2/` 为 **200**。
- `OnlineTransport` 故意不跟随任何跳转（`willPerformHTTPRedirection` → nil），并把 3xx 记为硬失败，于是下滑加载更多显示 `tangxinvlog.app · 查询：HTTP 307`。
- 同类规则也适用于 `/featured`、`/a/…`、`/v/…`（无斜杠 → 307 → 有斜杠）。

## Fix（策略内、不跟随 Location）

- `TangxinPolicy.featured` 固定为 `https://tangxinvlog.app/featured/`。
- 新增 `TangxinPolicy.documentURL`：仅在已通过 `page`/`video` 校验的同主机 URL 上补尾斜杠，清除 query/fragment；拒绝跨域。
- `TangxinClient.document` 对规范化后的 URL 发 GET。不开放通用 redirect 跟随，不改 OnlineTransport 全局策略。

## Live probe（只读，生产 UA + Referer，max-redirs 0）

| URL | Status |
|---|---|
| `/featured/` | 200 |
| `/featured/2` | 307 → `/featured/2/` |
| `/featured/2/` | 200 |
| `/v/{id}` | 307 → `/v/{id}/` |
| `/v/{id}/` | 200 |

## Tests

- `TangxinNetworkRegression263`：documentURL 同主机补斜杠；注入 loader 断言 client 请求 `/featured/2/` 与 `/v/…/`，且从不请求裸路径。
- `TangxinRegression261`：documentURL 路径断言。
- Fixtures / model loaders 同时接受有/无尾斜杠分页路径。
- `scripts/test-tangxin274.py`：静态源码守卫。
