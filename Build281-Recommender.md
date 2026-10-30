# Build 281 — 本机 AI「为你推荐」

Base: Build 280 (`15565e5`). CFBundleVersion 281. Workflow `lut4-online281.yml` (280 workflow is now `workflow_dispatch`).

Everything runs on the device: no server, no account upload, no login prompt. The only network traffic is
JavDB list/detail requests the app already makes (spaced 1 s apart, ≤10 list + ≤10 detail requests per manual
refresh, ≤7/≤6 automatic, stops after 3 consecutive failures).

## Pipeline (adapted from X's open-sourced `twitter/the-algorithm`)

| X concept | Build 281 adaptation | Code |
|---|---|---|
| **Signals / UUA** (user actions as weighted, time-decayed events) | 观看历史 (watch ratio → 0.4 + 1.2·ratio, rewatch bonus `min(1.2, 0.6·log2 plays)`), 快速跳出 <10 % = −0.35, 想看/收藏 +1.0, 喜欢 +2.0, 不感兴趣 −2.5, 关注 +2.5 (no decay), 少推 −2.0. Half-life 30 d (explicit feedback 60 d). | `RecSignalWeights`, `RecProfile.build` |
| **In-network vs out-of-network sourcing** (Earlybird vs CR-Mixer/UTEG) | In-network: 关注的女优/系列, top actresses, same series. Out-of-network: same maker, top tags (e.g. 黑丝), JavDB 「相似作品」 of recent positives, weekly ranking / new releases. Each source has a budget; sources are interleaved. | `RecSourcingPlan`, `RecCandidateSource.inNetwork` |
| **SimClusters** (community detection on the follow graph → sparse interest vectors) | Feature co-occurrence graph (actresses, tags, series, makers, directors) with cosine-normalised edges, label propagation → communities; each item and the user get a community distribution. Shown in 「我的偏好 · 兴趣社区」. | `RecClusters` |
| **TwHIN** (dense embeddings of the heterogeneous graph) | TF-IDF feature vectors smoothed by graph neighbours, then a fixed 32-d hashed random projection → dense embedding; user embedding = decayed weighted average. | `RecIndex`, `RecEmbedding` |
| **Heavy ranker** (predicts engagement probabilities) | 13-feature logistic regression: content cosine, embedding cosine, community overlap, actress/series/maker/tag affinity, in-network, freshness `exp(−age/60d)`, popularity prior, rating, negative affinity. Trained **online on device** from 喜欢/不感兴趣/少推 and from whether recommended items were then watched (≥50 % → 1, <10 % → 0). | `RecRanker` |
| **Visibility filtering** | Drop watched >80 %, 不感兴趣, 少推 actresses/series/tags, unavailable items, duplicate 番号. | `RecFilter` |
| **Heuristics: author diversity, content balance** | MMR re-rank (λ 0.75) with per-author decay 0.6, max 2 in a row and ≤4 per actress/series in the feed. | `RecDiversity` |
| **Explicit negative feedback** ("not interested", "show fewer from") | Long-press: 不感兴趣 / 少推该女优 / 少推该标签 / 少推该系列 — applied instantly, persisted, removable in 我的偏好. | `RecommendationStore.feedback` |
| Cold start | <3 positive items → popularity + freshness + rating prior over weekly ranking + new releases, with a hint card. | `RecommenderPipeline.rank` |

## UI

* 我的 → 「为你推荐」 section (both logged-in and guest layouts): compact hero + card strip.
* Full feed: hero 「今日首选」 (large HQ cover over a blurred cover backdrop, reason capsule), horizontal carousels
  grouped by reason (因为你常看 XX / 黑丝精选 / 同系列新作 · XX / 看过 XX 的人也喜欢 / 热门新作 / 更多为你推荐),
  pull-to-refresh, lightweight shimmer skeleton (disabled with Reduce Motion), cold-start card, toast after feedback.
* Cards: HQ cover pipeline (`MoviePosterImage`), 0.7 poster ratio, 14 pt continuous corners, soft shadow and scrim,
  番号 / title / tinted reason capsule with SF Symbol; `@ScaledMetric` widths for Dynamic Type; semantic colours for dark mode.
* Long-press: context menu with a large cover preview and haptics.
* 「我的偏好」: weighted bars (actresses, series/makers), weighted chips (tags), interest communities, 少推 chips
  (tap to restore), what the ranking model learned, and 重置推荐偏好 with confirmation.

## Performance / storage

* Profile, clustering, ranking and the preference summary run in `Task.detached` (off the main thread).
* Results are cached in `Caches/avdb-recommender-v1.json`; on appear the cache is reused for 6 h; lists are reused for 12 h.
* Metadata cache LRU-capped at 1500 items (interacted items kept), 40 pools, 500 feedback events, 300 shown items.

## Tests

* `scripts/test-recommender281.py` — executes the pure core and the store (fixture source) with swiftc: decay, quick bail,
  rewatch, TF-IDF, clusters, embeddings, profile, cold start, sourcing plan, scoring, filters, MMR/author diversity, reasons,
  groups, online LR, storage caps, persistence, feedback, reset; plus wiring/privacy/version checks.
* `scripts/test-rec-ui281.py` — CI simulator run of the production views with a seeded fixture; exports screenshots
  (feed, hero, carousels, long-press menu, toast, 我的偏好, reset dialog, cold start, skeleton, dark mode, 我的 section, large Dynamic Type).
  Covers in the screenshots are procedural placeholders because CI is offline.

## Limitations

* The model is small (linear LR + hashed projection); it learns per device and does not sync between devices.
* JavDB 「相似作品」/lists depend on the existing API; if requests fail the feed falls back to cached results.
* 想看 uses the local Watch-Later list; the server-side 想看 list is not fetched separately.
* Tangxin items are excluded from signals (no comparable metadata).
