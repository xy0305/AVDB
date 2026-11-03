# Build 304 — 類別篩選底栏可见（safeAreaInset）

User: 「没看到筛选」 — poster grid went straight to floating tab; 302 bar was under the tab inset.

## Fix
- Attach `CategoryInlineFilterPanel` with `.safeAreaInset(edge: .bottom)` on the categories `ScrollView` (same nesting as ActorsView), so it stacks above `FloatingTabContainer`'s tab bar.
- Collapsed default kept; strip is unmistakable: 「篩選」 + sort + chevron, `regularMaterial`, `minHeight` 52.
- Shows for 有碼 and every category tab (shared `CategoriesView`).
- 303 HQ prefetch / disk cache / Wi‑Fi concurrency untouched.
