#!/usr/bin/env python3
"""Build 299 — home→search open must not hitch on tag cloud / keyboard."""
from pathlib import Path
r = Path(__file__).resolve().parents[1]
search = (r / 'AVDB/Views/Search/SearchView.swift').read_text()
home = (r / 'AVDB/Views/Home/HomeView.swift').read_text()
plist = (r / 'AVDB/Resources/Info.plist').read_text()
pbx = (r / 'AVDB.xcodeproj/project.pbxproj').read_text()
assert 'CFBundleVersion' in plist and '>299<' in plist
assert pbx.count('CURRENT_PROJECT_VERSION = 299;') == 2
# Defer idle tag cloud + keyboard until after push
assert '@State private var openSettled = false' in search
assert '340_000_000' in search
assert 'openSettled = true' in search
assert 'isSearchFocused = true' in search
assert '.onAppear { isSearchFocused = submitted.isEmpty }' not in search
assert 'if openSettled' in search
assert 'Color.clear' in search
# Light chips, no stagger / pressable glass on idle tags
idle = search.split('private struct SearchIdleView', 1)[1].split('@MainActor', 1)[0]
assert 'staggerAppear' not in idle
assert 'pressableGlass' not in idle
assert 'scrolling: true' in idle
# Prefetch before push
assert 'SearchSuggestStore.shared.prefetch()' in home
assert 'func prefetch()' in search
assert 'private func fetchHotKeywords()' in search
# Plan A / cover HQ path untouched
loader = (r / 'AVDB/Services/ImageLoader.swift').read_text()
assert 'lead with the jacket' in loader or 'recognized 800x538 jacket' in loader
assert 'upgradesVisibleHQ' in home
print('PASS search-open299: deferred idle/keyboard, light chips, home prefetch, build 299')
