#!/usr/bin/env python3
"""Build 302 — 類別 篩選 panel is stowable; default collapsed thin bar above floating tab."""
from pathlib import Path
r = Path(__file__).resolve().parents[1]
v = (r / 'AVDB/Views/Categories/CategoriesView.swift').read_text()
plist = (r / 'AVDB/Resources/Info.plist').read_text(); pbx = (r / 'AVDB.xcodeproj/project.pbxproj').read_text()
assert '<string>302</string>' in plist and pbx.count('CURRENT_PROJECT_VERSION = 302;') == 2
root = v.split('struct CategoriesView: View', 1)[1].split('enum CatalogSort', 1)[0]
assert 'CategoryInlineFilterPanel(vm: vm' in root and '.sheet(isPresented: $showFilter)' not in root
assert '@AppStorage("categories.filterPanel.expanded.v2") private var filterExpanded = false' in root, 'default stowed'
panel = v.split('struct CategoryInlineFilterPanel', 1)[1]
for s in ['ForEach(vm.groups)', 'CatalogSort.allCases', 'vm.selectSort(sort)', 'vm.pick(groupID: cid', 'scheduleApply()',
          'await vm.applyFilter()', 'Tag.allChip', '"篩選"', 'DragGesture', 'reloadGroups()', 'summary']:
    assert s in panel, s
assert 'liquidGlass' not in panel and 'staggerAppear' not in panel, 'static chips keep the panel smooth'
assert '.ignoresSafeArea(edges: .bottom)' not in panel, 'bar must sit above floating tab inset'
# filter_by 7-slot encoding unchanged (main:tags:year:month)
assert 'return "\\(catalog.rawValue):t:\\(main):\\(tagSlot):\\(year):\\(month):"' in v
print('PASS category-filter302: stowable default-collapsed bar, chips apply immediately, sort, 7-slot filter_by, build 302')
