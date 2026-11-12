#!/usr/bin/env python3
"""Build 347 actor ranking period. Contracts: the 演員月榜 is a
single monthly list and must not be presented as if it split into
日榜 / 周榜 / 月榜 — those three periods belong to 作品 only. On
Build 346 the user opened 排行榜 → 歐美, selected 演員月榜, and
the 日榜 / 周榜 / 月榜 bar still sat above it with 月榜
highlighted (user screenshot, 2026-11-12 23:21); tapping 日榜 in
actor mode merely reloaded the identical monthly actor list under
a 日榜 label, because the actor loader has always hardcoded
period "monthly" (GET /api/v1/rankings/actors). Build 347 fixes
the presentation in RankingsView only: one helper,
showingActorRanking (the 作品 / 演員月榜 segment is on "actors"
AND the board has a genuine actor ranking), hides the period bar
in actor mode and pins the request period to .monthly. 作品 keeps
the 日榜 / 周榜 / 月榜 bar and the user's selected period,
restored untouched when switching back. The boards with an actor
ranking are exactly the Build 345 set (有碼 0, 無碼 1, 歐美 2;
FC2 excluded), 看熱播 keeps its own period bar (a works ranking),
TOP250 is untouched, and the actor endpoint, loader, grid and
tap-through are unchanged. Static source contracts on Linux;
behaviour verified on device."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '347' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 347;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2

wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 347' in wf and 'feat/actor-ranking-period-347' in wf
assert 'feat/list-paging-repeat-346' in wf and 'feat/western-actor-ranking-345' in wf
assert wf.count('python3 scripts/test-actor-ranking-period347.py') == 5  # dedicated job + zzt-ranking list + remove-javverse/detail-api jobs + release regressions
assert wf.count('python3 scripts/test-list-paging-repeat346.py') == 5  # the 346 gate keeps its 5 run lines
assert 'scripts/package-lut347.py' in wf and 'AVDB-347-release' in wf and 'AVDB-346-release' not in wf
pkg = (r/'scripts/package-lut347.py').read_text()
assert "=='347'" in pkg and 'AVDB-unsigned-1.0.2-347-actor-ranking-period.ipa' in pkg and "MinimumOSVersion']=='17.0'" in pkg
assert '  actor-ranking-period-347:' in wf and '  list-paging-repeat-346:' in wf

doc = (r/'Build347-ActorRankingPeriod.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '347' in doc
assert 'unsigned' in doc.lower()


def func_body(src, signature):
    start = src.index(signature)
    brace = src.index('{', start)
    depth = 0
    for i in range(brace, len(src)):
        if src[i] == '{':
            depth += 1
        elif src[i] == '}':
            depth -= 1
            if depth == 0:
                return src[start:i + 1]
    raise AssertionError('unbalanced: ' + signature)


view = (r/'AVDB/Views/Rankings/RankingsView.swift').read_text()

# --- 1. One helper decides "the monthly actor ranking is showing" ---
helper = func_body(view, 'private var showingActorRanking: Bool')
assert 'rankingKind == "actors"' in helper
assert 'RankingsViewModel.actorRankingType(for: tab) != nil' in helper

# --- 2. The period bar renders only outside actor mode ---
assert view.count('if !showingActorRanking {') == 1  # exactly one gated bar: the 作品 period bar
assert view.index('if !showingActorRanking {') < view.index('selection: $period')
assert 'tabs: RankPeriod.allCases.map { ($0, $0.title) },' in view  # the bar itself is unchanged

# --- 3. The request period is pinned to monthly in actor mode ---
reload_body = func_body(view, 'private func reload(force: Bool = false) async')
assert 'period: showingActorRanking ? .monthly : period,' in reload_body

# --- 4. The segment row and the actor machinery are untouched ---
assert 'if RankingsViewModel.actorRankingType(for: tab) != nil {' in view
assert '("movies", "作品")' in view and '("actors", "演員月榜")' in view
assert 'actorRankings(type: type, period: "monthly", page: r.page)' in view
assert 'ActorRankingGridContent' in view and 'ActorDetailView(actorID: actor.id)' in view

# --- 5. 看熱播 (a works ranking) keeps its period bar, ungated ---
assert 'selection: $playbackPeriod' in view
playback_block = view[view.index('if tab == .playback {'):view.index('} else if tab != .top250 {')]
assert 'showingActorRanking' not in playback_block

print('PASS test-actor-ranking-period347: the monthly actor '
      'ranking shows without the day/week/month period bar '
      '(hidden in actor mode, request pinned to monthly); the '
      'periods belong to 作品 only, release 347')
