#!/usr/bin/env python3
"""Build 301 — 類別 inline 篩選 panel (基本/年份/月份… + sort) is always reachable."""
from pathlib import Path
r = Path(__file__).resolve().parents[1]
v = (r / 'AVDB/Views/Categories/CategoriesView.swift').read_text()
plist = (r / 'AVDB/Resources/Info.plist').read_text(); pbx = (r / 'AVDB.xcodeproj/project.pbxproj').read_text()
assert '<string>301</string>' in plist and pbx.count('CURRENT_PROJECT_VERSION = 301;') == 2
root = v.split('struct CategoriesView: View', 1)[1].split('enum CatalogSort', 1)[0]
assert 'CategoryInlineFilterPanel(vm: vm' in root and '.sheet(isPresented: $showFilter)' not in root
assert '@AppStorage("categories.filterPanel.expanded") private var filterExpanded = true' in root
panel = v.split('struct CategoryInlineFilterPanel', 1)[1]
for s in ['ForEach(vm.groups)', 'CatalogSort.allCases', 'vm.selectSort(sort)', 'vm.pick(groupID: cid', 'scheduleApply()',
          'await vm.applyFilter()', 'Tag.allChip', '"篩選"', 'DragGesture', 'reloadGroups()']:
    assert s in panel, s
assert 'liquidGlass' not in panel and 'staggerAppear' not in panel, 'static chips keep the panel smooth'
# filter_by 7-slot encoding unchanged (main:tags:year:month)
assert 'return "\\(catalog.rawValue):t:\\(main):\\(tagSlot):\\(year):\\(month):"' in v
print('PASS category-filter301: inline panel, chips apply immediately, sort, 7-slot filter_by, build 301')
