#!/usr/bin/env python3
"""Build 303 — faster list HQ: prefetch, cell-sized disk cache, Wi‑Fi concurrency."""
from pathlib import Path
r = Path(__file__).resolve().parents[1]
loader = (r / 'AVDB/Services/ImageLoader.swift').read_text()
grid = (r / 'AVDB/Views/Components/JAVDBUI.swift').read_text()
home = (r / 'AVDB/Views/Home/HomeView.swift').read_text()
cat = (r / 'AVDB/Views/Categories/CategoriesView.swift').read_text()
plist = (r / 'AVDB/Resources/Info.plist').read_text()
pbx = (r / 'AVDB.xcodeproj/project.pbxproj').read_text()
ver = plist.split('CFBundleVersion')[1].split('<string>')[1].split('<')[0]
assert int(ver) >= 303 and pbx.count(f'CURRENT_PROJECT_VERSION = {ver};') == 2

policy = loader.split('enum VisibleHQPosterPolicy', 1)[1].split('actor VisibleHQPosterScheduler', 1)[0]
assert 'static let wifiConcurrency = 5' in policy
assert 'static let cellularConcurrency = 2' in policy
assert 'AICoverNetworkState.isExpensive' in policy
assert 'listPrefetchPixels = 540' in policy
assert 'pixelBuckets' in policy and 'quantizePixels' in policy
assert 'DetailPosterPolicy.candidates(number: movie.number).first' in policy
assert 'return Array(result.prefix(1))' in policy

sched = loader.split('actor VisibleHQPosterScheduler', 1)[1].split('enum ListHQCoverCache', 1)[0]
assert 'quantizePixels(maxPixelSize)' in sched
assert 'FrontPosterPolicy.cropRect' in sched and 'Task.detached' in sched
assert 'currentConcurrency()' in sched

# Disk cache still keyed via ImageLoader flightKey (url + pixel size)
assert 'HQPosterDiskCache.store(image, forKey: flightKey)' in loader
assert 'HQPosterDiskCache.image(forKey: flightKey)' in loader

pref = loader.split('enum HomeHQPosterPrefetch', 1)[1].split('#endif', 1)[0]
assert 'firstScreens = 24' in pref and 'aheadCount = 9' in pref
assert 'scheduleAhead' in pref
assert 'VisibleHQPosterScheduler.shared.upgrade' in pref
assert 'listPrefetchPixels' in pref
assert 'DetailPosterResolver' not in pref, '303 light prefetch must not run detail discovery'
assert 'R2' not in pref and 'cloudflare' not in pref.lower()

assert 'HomeHQPosterPrefetch.scheduleAhead(movies: movies, around: idx)' in grid
assert 'HomeHQPosterPrefetch.prefetch(warm)' in cat
assert 'HomeHQPosterPrefetch.prefetch(movies' in home

# No regression markers for 299/300/302
assert 'openSettled' in (r / 'AVDB/Views/Search/SearchView.swift').read_text()
assert 'var upgradesVisibleHQ = true' in loader
assert 'filterExpanded = false' in cat or 'expanded.v2' in cat
print('PASS list-hq-fast303: prefetch + cell disk cache + wifi concurrency 5 / cellular 2, build 303')
