#!/usr/bin/env python3
"""Build 336 remove the JavVerse ranking. Contracts: the rankings source
menu has no JavVerse section/destination; the view, live client, snapshot
resource, board/Grok models and release probe are gone from the app and
the project; the dedicated JavVerse test/CI surface is deleted; the
shared ranked-entry resolution layer (Entry/Identity/Failure/Mapper and
the two resolvers) stays because DMMRankingView builds its rows on it.
Static source contracts on Linux; behaviour verified on device."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '339' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 339;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2

wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 339' in wf and 'feat/remove-javverse-336' in wf
assert 'feat/detail-api-335' in wf and 'feat/home-hero-parity-334' in wf
assert wf.count('python3 scripts/test-remove-javverse336.py') == 4  # dedicated job + zzt-ranking job + detail-api-335 job + release regressions
assert 'scripts/package-lut339.py' in wf and 'AVDB-339-release' in wf and 'AVDB-335-release' not in wf
pkg = (r/'scripts/package-lut339.py').read_text()
assert "=='339'" in pkg and 'AVDB-unsigned-1.0.2-339-clear-glass.ipa' in pkg and "MinimumOSVersion']=='17.0'" in pkg
assert '  remove-javverse-336:' in wf and '  detail-api-335:' in wf

doc = (r/'Build336-RemoveJavVerse.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '336' in doc
assert 'unsigned' in doc.lower()
assert '移除 javverse 榜单' in doc

# --- 1. Gone files ---
for gone in ('AVDB/Views/JavVerseView.swift', 'AVDB/Services/JavVerseLiveClient.swift',
             'AVDB/Resources/JavVerseSnapshot.json',
             'UITests/JavVerseBehaviorTests.swift', 'UITests/JavVerseIdentityTests.swift',
             'UITests/JavVerseNavigationTests.swift',
             'scripts/test-javverse.py', 'scripts/test-javverse247.py',
             'scripts/register-javverse.rb', 'scripts/verify-javverse-provenance.py',
             '.github/workflows/javverse-acceptance.yml', '.github/workflows/javverse-schema247.yml'):
    assert not (r/gone).exists(), gone
assert not (r/'scripts/javverse-fixtures').exists()

# --- 2. No dangling references in the app ---
rankings = (r/'AVDB/Views/Rankings/RankingsView.swift').read_text()
assert 'JavVerse' not in rankings and 'javverse-source-entry' not in rankings
assert 'javRankingHome' in rankings and 'zhongZhiTong' in rankings  # other sources stay
app = (r/'AVDB/AVDBApp.swift').read_text()
assert 'JavVerse' not in app and 'ContentView()' in app
assert 'JavVerseView.swift' not in pbx and 'JavVerseLiveClient' not in pbx and 'JavVerseSnapshot' not in pbx

# --- 3. Shared resolution layer stays (DMM depends on it) ---
source = (r/'AVDB/Services/JavVerseSource.swift').read_text()
for kept in ('struct JavVerseEntry', 'enum JavVerseIdentity', 'enum JavVerseFailure', 'final class JavVerseMapper'):
    assert kept in source, kept
for gone in ('JavVerseSnapshot', 'JavVerseBoard', 'JavVerseGrok', 'JavVerseReleaseProbe', 'JavVerseHTTPProbe'):
    assert gone not in source, gone
policy = (r/'AVDB/Services/JavVersePolicy.swift').read_text()
assert 'JavVerseMovieResolver' in policy and 'JavVerseActorResolver' in policy
assert 'JavVersePagination' not in policy and 'JavVerseNeutralFixture' not in policy
dmm = (r/'AVDB/Views/Rankings/DMMRankingView.swift').read_text()
assert 'JavVerseMapper' in dmm and 'JavVerseEntry' in dmm

print('PASS test-remove-javverse336: JavVerse ranking surface removed (menu/view/live/snapshot/probe/tests), '
      'shared entry-resolution layer kept for DMM, release 339')
