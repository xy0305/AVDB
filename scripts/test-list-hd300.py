#!/usr/bin/env python3
"""Build 300 — every poster list upgrades visible cards to HD (bounded, cancelable)."""
from pathlib import Path
r = Path(__file__).resolve().parents[1]
loader = (r / 'AVDB/Services/ImageLoader.swift').read_text()
grid = (r / 'AVDB/Views/Components/JAVDBUI.swift').read_text()
rec = (r / 'AVDB/Views/User/RecommendationsView.swift').read_text()
plist = (r / 'AVDB/Resources/Info.plist').read_text(); pbx = (r / 'AVDB.xcodeproj/project.pbxproj').read_text()
v = plist.split('CFBundleVersion')[1].split('<string>')[1].split('<')[0]
assert int(v) >= 300 and pbx.count(f'CURRENT_PROJECT_VERSION = {v};') == 2
img = loader.split('public struct MoviePosterImage', 1)[1].split('public var body', 1)[0]
assert 'var upgradesVisibleHQ = true' in img
assert grid.count('var upgradesVisibleHQ = true') == 2
assert 'upgradesVisibleHQ: false' in rec, 'blurred backdrop opts out'
policy = loader.split('enum VisibleHQPosterPolicy', 1)[1].split('actor VisibleHQPosterScheduler', 1)[0]
assert 'DetailPosterPolicy.candidates(number: movie.number).first' in policy
assert 'return Array(result.prefix(1))' in policy and 'static let wifiConcurrency = 5' in policy
sched = loader.split('actor VisibleHQPosterScheduler', 1)[1].split('enum ListHQCoverCache', 1)[0]
assert 'FrontPosterPolicy.cropRect' in sched and 'Task.detached' in sched, 'envelope front crop off-main'
view = loader.split('struct VisibleHQPosterUpgrade', 1)[1].split('public struct MovieCoverCard', 1)[0]
ident = view.split('private func requestIdentity', 1)[1]
assert 'upgradeURL' not in ident, 'no policy work per body pass'
# synchronous list unchanged (small image paints first)
lst = loader.split('public static func sources(movie: Movie)', 1)[1].split('public struct MoviePosterImage', 1)[0]
assert 'DetailPosterPolicy.candidates' not in lst
print('PASS list-hd300: all grids upgrade visible cards, one bounded HD candidate, front crop off-main, build 300')
