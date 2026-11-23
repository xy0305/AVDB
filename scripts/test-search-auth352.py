#!/usr/bin/env python3
"""Build 352 search auth. JavDB moved search behind the JWT gate (the
user: 「javdb 现在搜索也要求登录了」). Live audit 2026-11-21 with the
official signature and no token: /api/v2/search (movie + actor types)
and /api/v2/search_image return success=0 / JWTVerificationError /
請登錄帳號, and the same session found four more flips since the Build
350 audit — /api/v1/movies/tags (was anonymous in 350; it backs
category browsing, list pages and the recommender's tag path and the
SDK called it without the token, so it was broken for everyone),
/api/v1/series (list; detail/letters still anonymous),
/api/v1/directors/{id} and /api/v1/makers/{id} (lists still anonymous).
/api/v4/movies/{id} is anonymous-rejected too but already token-carrying
with Build 340 auth handling. Contracts: the search family fails fast
with JavDBError.notLoggedIn when no token is stored; moviesByTag,
series list and the maker/director/publisher detail calls send the
token (the Build 335/350 pattern); the search UI shows a login prompt
on auth failure in all four result tabs (the actor/named/list tabs no
longer swallow errors with try?) and reloads after a successful login;
still-anonymous endpoints stay anonymous. Completion round the same
day (the user: 「查看 javdb 哪些接口要 token 全补上」): every SDK
endpoint was re-tested anonymously three times; /api/v2/tags,
/api/v1/movies/{id}/magnets and /api/v2/users/{id}/reviews are gated
too and their SDK callers (tagGroups, tags, movieMagnets, userReviews)
now send the token, as does codeDetail (same detail family, id not
harvestable anonymously). Static source contracts on Linux; behaviour
verified on device."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '353' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 353;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2

wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 353' in wf and 'feat/search-auth-352' in wf
assert 'feat/enrichment-351' in wf and 'revert/to-build-351' in wf
assert wf.count('python3 scripts/test-search-auth352.py') == 5  # dedicated job + shared lists + release regressions
assert wf.count('python3 scripts/test-enrichment351.py') == 5  # the 351 gate keeps its 5 run lines
assert 'scripts/package-lut353.py' in wf and 'AVDB-353-release' in wf and 'AVDB-351-release' not in wf
pkg = (r/'scripts/package-lut353.py').read_text()
assert "=='353'" in pkg and 'AVDB-unsigned-1.0.2-353-mplaykit.ipa' in pkg and "MinimumOSVersion']=='17.0'" in pkg
assert '  search-auth-352:' in wf and '  enrichment-351:' in wf

doc = (r/'Build352-SearchAuth.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '352' in doc
assert 'JWTVerificationError' in doc and 'unsigned' in doc.lower()
# Credit the user's request.
assert '现在搜索也要求登录' in doc
assert '哪些接口要 token 全补上' in doc

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


FAIL_FAST = 'guard client.token != nil else { throw JavDBError.notLoggedIn }'

# --- 1. The search family fails fast logged out and sends the token ---
for sig in ['public func search(',
            'public func searchActors(keyword: String',
            'public func searchNamed(keyword: String',
            'public func searchLists(keyword: String',
            'public func searchImage(_ imageURL: String)',
            'public func searchMagnet(']:
    body = func_body(sdk, sig)
    assert FAIL_FAST in body, sig
    assert 'useToken: true' in body, sig

# --- 2. The four newly-gated endpoints (plus publisher, same family) send the token ---
tags = func_body(sdk, 'public func moviesByTag(')
assert '"/api/v1/movies/tags", query: query, useToken: true' in tags
series = func_body(sdk, 'public func series(type: String')
assert '"/api/v1/series"' in series and 'useToken: true' in series
for sig, path in [('public func directorDetail(_ id: String)', '/api/v1/directors/'),
                  ('public func makerDetail(_ id: String)', '/api/v1/makers/'),
                  ('public func publisherDetail(_ id: String)', '/api/v1/publishers/')]:
    body = func_body(sdk, sig)
    assert path in body and 'useToken: true' in body, sig

# --- 2b. Completion round: tags, movie magnets, user reviews, code detail ---
magnets = func_body(sdk, 'public func movieMagnets(_ id: String')
assert 'magnets", query: ["page": "\\(page)"], useToken: true' in magnets
tag_groups = func_body(sdk, 'public func tagGroups(type: String)')
assert '"/api/v2/tags", query: ["type": type], useToken: true' in tag_groups
plain_tags = func_body(sdk, 'public func tags()')
assert '"/api/v2/tags", useToken: true' in plain_tags
user_reviews = func_body(sdk, 'public func userReviews(_ userID: Int)')
assert '"/api/v2/users/\\(userID)/reviews", useToken: true' in user_reviews
code_detail = func_body(sdk, 'public func codeDetail(_ id: String)')
assert '"/api/v1/codes/\\(id)", useToken: true' in code_detail

# --- 3. Endpoints the audit found still anonymous stay anonymous ---
assert '"/api/v1/movies/recommend", query: query)' in sdk
assert '"/api/v1/movies/latest", query: query)' in sdk
assert '"/api/v1/series/letters"' in sdk and '"/api/v1/makers", query' in sdk

# --- 4. Search UI: login prompt on auth failure in all four result tabs ---
search = (r/'AVDB/Views/Search/SearchView.swift').read_text()
assert 'struct SearchLoginPrompt: View' in search
assert '搜索需要登录' in search and 'search-error-login' in search
assert 'LoginView()' in search
assert search.count('SearchLoginPrompt()') == 4  # movie + actor + named + list tabs
assert 'JavDBError.isAuthenticationMessage(error)' in search  # movie tab branches on the VM string
assert search.count('JavDBError.isAuthenticationFailure(error)') == 3  # actor/named/list catch blocks
assert 'try? await JavDBSDK.shared.searchActors' not in search
assert 'try? await JavDBSDK.shared.searchNamed' not in search
assert 'try? await JavDBSDK.shared.searchLists' not in search
assert search.count('publisher(for: .avdbCatalogAccountChanged)') == 4  # every tab reloads after login

print('PASS test-search-auth352: search family fails fast logged out, movies/tags + series list + '
      'maker/director/publisher detail + v2/tags + movie magnets + user reviews + code detail send the token, '
      'search UI offers login in all four tabs, release 353')
