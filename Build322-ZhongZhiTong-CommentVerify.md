# Build 322 — 中指通月度精選評論核對修正

Base: Build 321 / 292ef1b, `feat/zzt-ranking-321` (PR #11, unmerged).

- From `ocr/verify_report.json` (comments vs data cross-check):
  - **Added 97 net new codes** from 98 `missing_candidates_verified` (ACHJ-089 applied via replace, not double-add); each re-checked javdb exact + date window.
  - **2026-08**: was title-only DSOD-001 → now `youtube_comments` with **29** codes (DSOD-001 + 28); source `https://www.youtube.com/watch?v=cqH7NrWU_AQ`.
  - **2026-09**: replace **ACHJ-088 → ACHJ-089**; also add **PRPM-002**.
  - **Did not remove** the 44 suspect-wrong codes.
- Totals: **79 months / 1881 codes** (Build 321: 79 / 1784).
- No magnets. Version bumped to 322.

Validation: `test-zzt-ranking322.py` plus 313–321 zzt tests.
