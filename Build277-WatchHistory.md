# Build 277 — 「我的」观看历史（带封面）

Base: 1.0.2 (276) `001d0d1`, branch `feat/lut4-online-from269`. LUT code untouched.

## Store (`AVDB/Services/FeatureStores.swift`)
- Reuses the existing account-isolated `PlaybackHistoryStore` (UserDefaults `avdb.play.history.v1.<scope>` + small
  JPEG artwork under Application Support). Logged-out playback now goes to a separate device-only `guest` scope.
- `PlaybackHistoryItem` gains optional `source`, `position`, `length`, `pageURL`, `posterURL`; ≤276 JSON decodes unchanged.
- Pure `PlaybackHistoryList`: dedupe by id → move to top (keeps previous resume point), cap **500** (was 300),
  progress throttle (first value / ≥10 s / forced), remove, clear. Artwork in-memory cache.
- Still never stores stream URLs, headers, cookies or tokens; covers must be public https images without query.

## Recording (all player entry points through `KSChromePlayer`)
| Entry | Source label | Cover |
|---|---|---|
| JavDB catalog `PlayerView` | JavDB | JavDB cover → HQ list pipeline |
| 115 `Pan115PlayerView` | 115 | detail HQ poster snapshot |
| 在线 MissAV / Jable / 123AV / MemoJav / JavDay | provider label | detail HQ poster snapshot |
| 糖心 | 糖心 | Tangxin poster via TangxinClient |

Start is still gated by `PlaybackHistoryStartGate` (real advancing playback). Position/duration are written every
≥10 s while playing and forced on pause, played-to-end, player exit and app resign-active.

## UI
- 「我的」: 「观看历史 · 全部 N」row + horizontal strip of the 20 most recent covers (0.7 card, source chip,
  progress bar, 番号, 今天/昨天/日期). Shown signed-in and signed-out. Long-press → 删除这条记录. Empty hint.
- 「全部」: adaptive grid (same columns as poster grids), 番号 / 标题 / 相对时间 · 看到 mm:ss / 总长,
  long-press delete, 清空 with confirmation, empty state.
- Tap → catalog detail (`MovieDetailView`) or 糖心 detail; 115 / 糖心 playback resumes from the existing
  `PlaybackProgressStore` position.

## Tests
- `scripts/test-watch-history277.py` (executes the Swift list/format policy with swiftc on macOS CI:
  record, dedupe, cap, delete, clear, progress throttle, UserDefaults round-trip, legacy decode, relative dates;
  plus wiring guards). `scripts/test-playback-history.py` updated to 277 and added to CI.
