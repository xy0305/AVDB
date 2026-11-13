#!/usr/bin/env python3
"""Build 348 actor grid scroll jank. Contracts: two verified
causes, both fixed. (1) ActorAvatarArtwork.identity is evaluated
on every cell body pass and calls JavBusActorService.names(),
which called ActorAliasCatalog.bundled() — and bundled() rebuilt
the catalog from scratch on every call: re-reading the bundled
ActorAliasIndex.json (922,092 bytes, 8,115 records) from disk,
re-decoding it and rebuilding the record/alias/conflict
dictionaries, on the main actor, with no cache anywhere in the
chain. Scrolling an actor grid therefore paid a full catalog
rebuild per newly created cell, and every view-model republish
made all visible cells pay it again at once. The bundled index
is immutable at runtime, so bundled() now returns a static
cached catalog built exactly once. (2) The actor rankings
endpoint ignores `page` (verified live 2026-11-13 with the app's
own signing: pages 1-3 of GET /api/v1/rankings/actors return the
identical list, 有碼 94 / 歐美 80), but RankingsViewModel.fetch
set hasMore from the raw page, so paging never ended and every
pass over the last cell refetched and republished the grid.
The actors branch now ends paging when a page appends nothing
new — the Build 346 rule — while the movies branch of the same
fetch (genuinely paged endpoints) is unchanged. The avatar
images themselves were ruled out by measurement: 100-320 px,
5-110 KB, decrypted/downsampled off-main and NSCache-cached.
Static source contracts on Linux; behaviour verified live
against the API and on device."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '349' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 349;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2

wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 349' in wf and 'feat/actor-grid-scroll-348' in wf
assert 'feat/actor-ranking-period-347' in wf and 'feat/list-paging-repeat-346' in wf
assert wf.count('python3 scripts/test-actor-grid-scroll348.py') == 5  # dedicated job + zzt-ranking list + remove-javverse/detail-api jobs + release regressions
assert wf.count('python3 scripts/test-actor-ranking-period347.py') == 5  # the 347 gate keeps its 5 run lines
assert 'scripts/package-lut349.py' in wf and 'AVDB-349-release' in wf and 'AVDB-347-release' not in wf
pkg = (r/'scripts/package-lut349.py').read_text()
assert "=='349'" in pkg and 'AVDB-unsigned-1.0.2-349-feed-prefill.ipa' in pkg and "MinimumOSVersion']=='17.0'" in pkg
assert '  actor-grid-scroll-348:' in wf and '  actor-ranking-period-347:' in wf

doc = (r/'Build348-ActorGridScroll.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '348' in doc
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


# --- 1. The bundled alias catalog is built exactly once ---
catalog = (r/'AVDB/Services/ActorAliasCatalog.swift').read_text()
assert 'private static let cached = ActorAliasCatalog(index: ActorAliasIndex.bundled()' in catalog
bundled_body = func_body(catalog, 'static func bundled() -> ActorAliasCatalog')
assert 'cached' in bundled_body and 'ActorAliasCatalog(index:' not in bundled_body  # no per-call rebuild
artwork = (r/'AVDB/Services/JavBusActorAvatar.swift').read_text()
assert 'ActorAliasCatalog.bundled()' in artwork  # the hot caller is unchanged; the fix sits behind it
assert 'JavBusActorService.names(actor)' in artwork  # identity still keys on the actor's names

# --- 2. Actor paging ends when a page appends nothing new ---
view = (r/'AVDB/Views/Rankings/RankingsView.swift').read_text()
vm = func_body(view, 'final class RankingsViewModel')
fetch = func_body(vm, 'private func fetch(_ next: Request, generation ticket: Int) async')
assert 'if next.kind == "actors", Self.actorRankingType(for: next.tab) != nil {' in fetch
assert 'let fresh = list.filter { !ids.contains($0.id) }' in fetch
assert 'hasMore = !fresh.isEmpty' in fetch
assert 'if next.page == 1 { actors = list; hasMore = !list.isEmpty }' in fetch

# --- 3. The movies branch of the same fetch is unchanged ---
movies_branch = fetch[fetch.index('} else {'):]
assert 'hasMore = !list.isEmpty' in movies_branch and 'fresh' not in movies_branch
assert 'sdk.rankings(type: type, period: r.period, page: r.page)' in vm

print('PASS test-actor-grid-scroll348: the alias catalog is '
      'built once instead of per actor cell, and actor paging '
      'stops when a page adds nothing new, release 349')
