#!/usr/bin/env python3
"""Build 304 — 類別 篩選 bar uses safeAreaInset so it sits above the floating tab."""
from pathlib import Path
r = Path(__file__).resolve().parents[1]
src = (r / 'AVDB/Views/Categories/CategoriesView.swift').read_text()
plist = (r / 'AVDB/Resources/Info.plist').read_text(); pbx = (r / 'AVDB.xcodeproj/project.pbxproj').read_text()
assert '<string>304</string>' in plist and pbx.count('CURRENT_PROJECT_VERSION = 304;') == 2
root = src.split('struct CategoriesView: View', 1)[1].split('enum CatalogSort', 1)[0]
assert '.safeAreaInset(edge: .bottom, spacing: 0)' in root
assert 'CategoryInlineFilterPanel(' in root
assert '.sheet(isPresented: $showFilter)' not in root
assert '@AppStorage("categories.filterPanel.expanded.v2") private var filterExpanded = false' in root
# Must NOT be a bare VStack sibling after ScrollView without inset (the 302 bug).
assert 'ScrollView {' in root
# Panel is attached via safeAreaInset on the ScrollView, not as trailing VStack child only.
scroll_to_end = root.split('ScrollView {', 1)[1]
assert '.safeAreaInset(edge: .bottom' in scroll_to_end
panel = src.split('struct CategoryInlineFilterPanel', 1)[1]
assert 'minHeight: expanded ? nil : 52' in panel
assert '.regularMaterial' in panel
assert '"篩選"' in panel and 'CatalogSort.allCases' in panel
assert 'ForEach(vm.groups)' in panel and 'scheduleApply()' in panel
assert 'liquidGlass' not in panel
# 303 HQ prefetch still wired from categories fetch
assert 'HomeHQPosterPrefetch.prefetch(warm)' in src
print('PASS category-filter304: safeAreaInset above floating tab, collapsed ~52pt visible, build 304')
