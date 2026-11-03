# Build 303 — faster home/list HQ thumbnails

User: 「继续」 (items 2 prefetch, 3 cell disk cache, 5 Wi‑Fi concurrency; skip R2)

## Changes
1. **Prefetch**: `HomeHQPosterPrefetch` warms first ~24 titles when home/list data arrives (same VisibleHQ path, not DetailPosterResolver). `MoviePosterGrid` schedules ~9 ahead while scrolling.
2. **Cell-sized disk cache**: pixel sizes quantized to 360/540/720/900; prefetch uses 540 so ImageLoader `HQPosterDiskCache` keys match visible upgrades (URL + size). Next launch hits disk without re-decoding full DMM/MGS originals.
3. **Wi‑Fi concurrency**: upgrade scheduler uses 5 on Wi‑Fi, 2 on cellular/expensive (`AICoverNetworkState`). Off-screen cancel unchanged.
4. **Not in this build**: Cloudflare R2 / cloud proxy.

## Keep
299 search open, 300 HQ + junk rejection + Plan A, 301/302 stowable category filter.
