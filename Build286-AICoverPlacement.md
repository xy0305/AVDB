# Build 286: AI 增强 controls no longer overlay the cover art

User report (285): the 「✦ AI 增强」 pill + compare button sat in the top bar over the cover (face / title text).

- Detail top chrome is back + search only again (`detailChrome` has no AI control).
- `AICoverMetaChip` sits directly under the metadata row (「IPX-706 · 2021-08-13 · …」), above 播放 / actions:
  idle 「✦ AI 增强」 (tap) → 「◌ AI 增强中 42% ×」 (tap cancels) → 「✦ AI 增强 | ◧ 按住对比」; while held 「原图 | 松开恢复」.
  Right after a fresh enhancement the compare half reads 「长按封面也可对比原图」 for ~1.6 s, then fades back.
  Failed: 「⚠ AI 增强失败 · 重试」. HQ native / mode 关: no chip, no extra space.
- Long-press the cover itself (0.28 s, then keep holding) shows the original; release restores. A long-press never opens
  the viewer (tap guard); a plain tap still opens it. The hero gradient no longer swallows touches.
- Fullscreen viewer: close button / image / toolbar are stacked; at 1× nothing overlays the cover, zoom is clipped to
  the image region. The badge moved into the bottom info line (「✦ AI 增强 原图 378×538 → AI 1512×2152」).
- Tests: `scripts/test-ai-cover286.py` (source-level: no AI in chrome, chip order, long-press, viewer stacking),
  `scripts/test-ai-ui286.py` (simulator, real IPX-706 jacket: frames of every AI control are below the metadata row,
  viewer bars outside the image region, real cover long-press → compare without opening the viewer).
