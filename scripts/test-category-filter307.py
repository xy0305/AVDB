#!/usr/bin/env python3
"""Build 307 — 類別 篩選 moves to the top-left: toolbar entry + panel under the tabs."""
from pathlib import Path
r = Path(__file__).resolve().parents[1]
src = (r / 'AVDB/Views/Categories/CategoriesView.swift').read_text()
plist = (r / 'AVDB/Resources/Info.plist').read_text(); pbx = (r / 'AVDB.xcodeproj/project.pbxproj').read_text()
ver = plist.split('CFBundleVersion')[1].split('<string>')[1].split('<')[0]
assert int(ver) >= 307 and pbx.count(f'CURRENT_PROJECT_VERSION = {ver};') == 2
root = src.split('struct CategoriesView: View', 1)[1].split('enum CatalogSort', 1)[0]
# Entry point: top-left corner of the toolbar, always visible.
assert 'ToolbarItem(placement: .topBarLeading)' in root
assert 'category-filter-toolbar-toggle' in root
assert '"篩選"' in root
# Nothing filter-related hangs off the bottom any more.
assert '.safeAreaInset(edge: .bottom' not in root
assert 'if filterExpanded {' in root
assert root.index('CategoryInlineFilterPanel(') < root.index('ScrollView {')
assert '.move(edge: .top)' in root
panel = src.split('struct CategoryInlineFilterPanel', 1)[1]
# Top-hung panel: square top corners, rounded bottom corners, downward shadow.
assert 'topLeadingRadius: 0' in panel and 'bottomLeadingRadius: 18' in panel and 'bottomTrailingRadius: 18' in panel
assert 'radius: 12, y: 3' in panel
assert 'DragGesture' in panel and 'dy < -60' in panel and 'setExpanded(false)' in panel
assert 'minHeight: expanded ? nil : 52' not in panel, 'no collapsed bottom strip any more'
assert 'activeFilterSummary' in src and 'private var summary: String { vm.activeFilterSummary }' in panel
# filter_by 7-slot encoding unchanged (main:tags:year:month)
assert 'return "\\(catalog.rawValue):t:\\(main):\\(tagSlot):\\(year):\\(month):"' in src
print('PASS category-filter307: filter entry top-left in toolbar, panel drops from top under tabs, build 307')
