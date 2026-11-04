#!/usr/bin/env python3
"""Build 304 contract, updated for 307 — the 篩選 panel left the bottom in 307
(top-left toolbar entry + panel under the tabs); this file keeps guarding the
shared bits: no sheet, same AppStorage key/default, material panel, sort +
chips, HQ prefetch wiring."""
from pathlib import Path
r = Path(__file__).resolve().parents[1]
src = (r / 'AVDB/Views/Categories/CategoriesView.swift').read_text()
plist = (r / 'AVDB/Resources/Info.plist').read_text(); pbx = (r / 'AVDB.xcodeproj/project.pbxproj').read_text()
ver = plist.split('CFBundleVersion')[1].split('<string>')[1].split('<')[0]
assert int(ver) >= 304 and pbx.count(f'CURRENT_PROJECT_VERSION = {ver};') == 2
root = src.split('struct CategoriesView: View', 1)[1].split('enum CatalogSort', 1)[0]
assert 'CategoryInlineFilterPanel(' in root
assert '.sheet(isPresented: $showFilter)' not in root
assert '@AppStorage("categories.filterPanel.expanded.v2") private var filterExpanded = false' in root
assert 'ScrollView {' in root
# 307: the bottom inset is gone for good — the floating tab bar covered the strip.
assert '.safeAreaInset(edge: .bottom' not in root
# Panel is hosted in the VStack above the ScrollView, not inside/under it.
assert root.index('CategoryInlineFilterPanel(') < root.index('ScrollView {')
panel = src.split('struct CategoryInlineFilterPanel', 1)[1]
assert '.regularMaterial' in panel
assert 'bottomLeadingRadius: 18' in panel
assert '"篩選"' in panel and 'CatalogSort.allCases' in panel
assert 'ForEach(vm.groups)' in panel and 'scheduleApply()' in panel
assert 'liquidGlass' not in panel
# 303 HQ prefetch still wired from categories fetch
assert 'HomeHQPosterPrefetch.prefetch(warm)' in src
print('PASS category-filter304: shared filter contract holds after the 307 top move (bottom-inset asserts retired)')
