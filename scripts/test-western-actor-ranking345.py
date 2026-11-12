#!/usr/bin/env python3
"""Build 345 western monthly actor ranking. Contracts: the 演員月榜
segment that used to exist only on the 有碼 board — with the API type
hardcoded to "0" — now reaches every board that has a genuine monthly
actor ranking on the server. The user supplied a screenshot of the
official app's 歐美 board showing 日榜 / 周榜 / 月榜 / 演員月榜 and
asked for that endpoint to be added, with its related operations.
The endpoint is GET /api/v1/rankings/actors, already present in the
SDK; verified live (2026-11-12, anonymous, the app's own signing):
type 2 (歐美) returns 80 actors whose first rows match the official
app exactly (Kendra Sunderland, Melody Marks, Angela White), type 1
(無碼) returns its own list, and type 3 (FC2) merely echoes the
censored board's list — so the segment is offered on 有碼 / 無碼 /
歐美 and deliberately not on FC2. One source of truth,
RankingsViewModel.actorRankingType(for:), drives the chip row's
visibility, the view model's showingActors, the fetch branch and
the actor loader's type; the related operations ride the existing
machinery (the shared actor grid, pagination, pull-to-refresh, and
tap-through to ActorDetailView). Movie rankings, TOP250, playback
and the other sources are untouched. Static source contracts on
Linux; behaviour verified live against the API and on device."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '345' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 345;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2

wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 345' in wf and 'feat/western-actor-ranking-345' in wf
assert 'feat/list-tabbar-clearance-344' in wf and 'feat/list-landscape-cover-343' in wf
assert wf.count('python3 scripts/test-western-actor-ranking345.py') == 5  # dedicated job + zzt-ranking list + remove-javverse/detail-api jobs + release regressions
assert wf.count('python3 scripts/test-list-tabbar-clearance344.py') == 5  # the 344 gate keeps its 5 run lines
assert 'scripts/package-lut345.py' in wf and 'AVDB-345-release' in wf and 'AVDB-344-release' not in wf
pkg = (r/'scripts/package-lut345.py').read_text()
assert "=='345'" in pkg and 'AVDB-unsigned-1.0.2-345-western-actor-ranking.ipa' in pkg and "MinimumOSVersion']=='17.0'" in pkg
assert '  western-actor-ranking-345:' in wf and '  list-tabbar-clearance-344:' in wf

doc = (r/'Build345-WesternActorRanking.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '345' in doc
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
vm = func_body(view, 'final class RankingsViewModel')

# --- 1. One source of truth maps boards to actor-ranking types ---
helper = func_body(view, 'static func actorRankingType(for tab: RankingTab) -> String?')
assert 'case .censored: return "0"' in helper
assert 'case .uncensored: return "1"' in helper
assert 'case .western: return "2"' in helper
assert 'case .fc2' not in helper  # FC2 only echoes the censored list server-side

# --- 2. The chip row follows the helper, not the censored board ---
assert 'if RankingsViewModel.actorRankingType(for: tab) != nil {' in view
assert 'if tab == .censored {' not in view
assert '("actors", "演員月榜")' in view and '("movies", "作品")' in view

# --- 3. The view model follows the helper everywhere ---
assert 'return Self.actorRankingType(for: request.tab) != nil' in vm
assert 'request?.tab == .censored && request?.kind == "actors"' not in view
assert 'if next.kind == "actors", Self.actorRankingType(for: next.tab) != nil {' in vm
assert 'next.tab == .censored && next.kind == "actors"' not in view
assert 'guard let type = RankingsViewModel.actorRankingType(for: r.tab) else { return [] }' in vm
assert 'actorRankings(type: type, period: "monthly", page: r.page)' in vm
assert 'actorRankings(type: "0", period: "monthly"' not in view  # the old hardcoded loader

# --- 4. Related operations stay wired: grid, tap-through, paging ---
assert 'ActorRankingGridContent' in view and 'ActorDetailView(actorID: actor.id)' in view
assert 'sdk.rankings(type: type, period: r.period, page: r.page)' in vm
sdk = (r/'AVDB/Services/JavDBSDK.swift').read_text()
assert '"/api/v1/rankings/actors"' in sdk  # the endpoint itself, unchanged

print('PASS test-western-actor-ranking345: the monthly actor ranking '
      'segment is driven by the board type (censored 0, uncensored 1, '
      'western 2; FC2 excluded) across the chip row, the view model '
      'and the loader, release 345')
