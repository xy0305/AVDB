# Build 307 — 類別篩選移到左上角

User: 「类别左上角的筛选还是被 tap 挡住，放到左上角」 — on build 306 the 篩選
strip still wasn't visible in the screenshot: the poster grid runs straight
into the floating tab bar, no filter strip above it.

## Why the bottom kept failing

302 put the strip in the VStack, 304–306 moved it to
`.safeAreaInset(edge: .bottom)` on the categories ScrollView. But
FloatingTabContainer applies its own bottom safeAreaInset outside the
NavigationStack, and the nested inner inset never reserved visible space —
the strip rendered behind/under the floating tab capsule. Three builds of
inset adjustments did not change that, so 307 leaves the bottom entirely.

## Change

- Entry point: new `.topBarLeading` toolbar button (the literal top-left
  corner, mirroring the search button at top-right): funnel icon + 「篩選」
  + a dot when non-default filters are active + chevron. Always visible.
- Panel: `CategoryInlineFilterPanel` now hangs from the top — hosted in the
  categories VStack directly under the UnderlineTabBar when expanded
  (`.move(edge: .top)` transition), square top corners, rounded bottom
  corners, downward shadow. Grab handle on its bottom edge; tap or drag up
  to stow. No bottom inset anywhere on the page.
- Behaviour unchanged otherwise: chips tap-to-apply (250ms coalesce), sort
  menu in the panel header, active summary shared via
  `CategoriesViewModel.activeFilterSummary`, filter_by 7-slot encoding
  unchanged, 303 HQ prefetch untouched.
- Contracts: new test-category-filter307 (wired into home-hq298.yml);
  test-category-filter304 updated (bottom-inset asserts retired);
  test-category-filter302 unchanged.

## Version

CFBundleVersion / CURRENT_PROJECT_VERSION = 307
IPA: `AVDB-unsigned-1.0.2-307-filter-top-left.ipa`
