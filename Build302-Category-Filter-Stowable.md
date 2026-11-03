# Build 302 — 類別篩選可收纳

User: 「要是可收纳的形式」

## Change
- Default **collapsed** (stowed): one thin bottom bar with 「篩選」 + current sort label + optional active-filter summary + chevron/handle.
- Sits in the Categories `VStack` above `FloatingTabContainer`'s tab-bar `safeAreaInset` (no `.ignoresSafeArea(.bottom)`), so it does not cover the poster grid much and stays above the floating tab.
- Tap or drag up expands the full chip panel (基本/年份/月份…); tap handle or drag down stows again.
- Expand/collapse remembered via `@AppStorage("categories.filterPanel.expanded.v2")` (new key so 302 defaults stowed even after 301).
- Tap-to-apply chips + sort unchanged; 299 search open, 300 list HD / Plan A untouched.

## Version
CFBundleVersion / CURRENT_PROJECT_VERSION = 302
IPA: `AVDB-unsigned-1.0.2-302-category-filter-stowable.ipa`
