# Build 305 — 筛选可见 + 首页高清加速

Ships 303 HQ speedups + 304 safeAreaInset filter bar, with CI test contracts fixed.

## Included
- **筛选**: `CategoryInlineFilterPanel` via `.safeAreaInset(edge: .bottom)` above floating tab; default collapsed ~52pt 「篩選」 strip.
- **HQ faster**: prefetch first ~2 screens + scroll-ahead; quantized cell-sized disk cache; Wi‑Fi concurrency 5 / cellular 2.
- **CI**: HomeHQ tests accept 513→540 quantize + fail-by-URL; dmm284 asserts wifi/cellular concurrency.

No R2.
