#!/usr/bin/env python3
"""Build 350 rankings auth. JavDB moved every rankings endpoint behind
the JWT gate (verified live 2026-11-14 with the official signature and
no token: /api/v1/rankings for types 0/1/2/3 x daily/weekly/monthly,
/api/v1/rankings/actors, and /api/v1/rankings/playback all return
success=0 / JWTVerificationError / 請登錄帳號). The same audit found
/api/v1/search_magnet flipped too (it was still guest-OK when Build 335
audited it), while recommend, latest, recommend_periods, movies/tags,
actors, series, makers, tags, articles, startup, about, ads,
magnet_apps and plans still answer anonymously, and /api/v4/movies/{id}
was already token-carrying in the SDK. Contracts: the three rankings
calls and searchMagnet send the account token (useToken: true), exactly
the Build 335 pattern; the still-anonymous endpoints stay anonymous.
Static source contracts on Linux; behaviour verified on device."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '350' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 350;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2

wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 350' in wf and 'feat/rankings-auth-350' in wf
assert 'feat/feed-prefill-349' in wf and 'feat/actor-grid-scroll-348' in wf
assert wf.count('python3 scripts/test-rankings-auth350.py') == 5  # dedicated job + shared lists + release regressions
assert wf.count('python3 scripts/test-feed-prefill349.py') == 5  # the 349 gate keeps its 5 run lines
assert 'scripts/package-lut350.py' in wf and 'AVDB-350-release' in wf and 'AVDB-349-release' not in wf
pkg = (r/'scripts/package-lut350.py').read_text()
assert "=='350'" in pkg and 'AVDB-unsigned-1.0.2-350-rankings-auth.ipa' in pkg and "MinimumOSVersion']=='17.0'" in pkg
assert '  rankings-auth-350:' in wf and '  feed-prefill-349:' in wf

doc = (r/'Build350-RankingsAuth.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '350' in doc
assert 'JWTVerificationError' in doc and 'unsigned' in doc.lower()
# Credit the user's requests.
assert '排行里所有都要求登录' in doc and '看热播' in doc

sdk = (r/'AVDB/Services/JavDBSDK.swift').read_text()


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
    raise AssertionError('unterminated body: ' + signature)


# --- 1. The three rankings endpoints send the token ---
rankings = func_body(sdk, 'public func rankings(type: String, period: String')
assert '"/api/v1/rankings"' in rankings and 'useToken: true' in rankings
actors = func_body(sdk, 'public func actorRankings(')
assert '"/api/v1/rankings/actors"' in actors and 'useToken: true' in actors
playback = func_body(sdk, 'public func playbackRankings(')
assert '"/api/v1/rankings/playback"' in playback and 'useToken: true' in playback

# --- 2. search_magnet flipped in the same audit; it sends the token too ---
magnet = func_body(sdk, 'public func searchMagnet(')
assert '"/api/v1/search_magnet"' in magnet and 'useToken: true' in magnet

# --- 3. Endpoints the audit found still anonymous stay anonymous ---
assert '"/api/v1/movies/recommend", query: query)' in sdk
assert '"/api/v1/movies/latest", query: query)' in sdk

print('PASS test-rankings-auth350: rankings + actor rankings + playback rankings and '
      'search_magnet send the token, still-anonymous endpoints untouched, release 350')
