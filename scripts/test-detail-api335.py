#!/usr/bin/env python3
"""Build 335 detail glass + API auth change. The JavDB API moved search and
may_also_like behind the JWT gate (verified live against the official
v1.9.29 client: anonymous calls return success=0 / JWTVerificationError).
Contracts: the SDK search family and mayAlsoLike send the account token; the
detail page's 猜你喜欢 rail is fed by mayAlsoLike merged ahead of the payload
relatives; Ta 还出演过 upgrades through the official actor endpoint; the
portrait play pill and action group use the home Liquid Glass capsule; a
failed search surfaces its error instead of a silent empty page. Static
source contracts on Linux; behaviour verified on device."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '340' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 340;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2

wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 340' in wf and 'feat/detail-api-335' in wf
assert 'feat/home-hero-parity-334' in wf and 'feat/home-hero-detail-333' in wf
assert wf.count('python3 scripts/test-detail-api335.py') == 3  # dedicated job + zzt-ranking job + release regressions
assert 'python3 scripts/test-home-hero334.py' in wf
assert 'scripts/package-lut340.py' in wf and 'AVDB-340-release' in wf and 'AVDB-334-release' not in wf
pkg = (r/'scripts/package-lut340.py').read_text()
assert "=='340'" in pkg and 'AVDB-unsigned-1.0.2-340-session-revalidate.ipa' in pkg and "MinimumOSVersion']=='17.0'" in pkg
assert '  detail-api-335:' in wf and '  home-hero-334:' in wf

doc = (r/'Build335-DetailAPI.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '335' in doc
assert 'JWTVerificationError' in doc and 'unsigned' in doc.lower()
# Credit the user's requests.
assert '猜你喜欢怎么没了' in doc and '搜索也不行' in doc

sdk = (r/'AVDB/Services/JavDBSDK.swift').read_text()

# --- 1. Search family + may_also_like send the token ---
assert 'client.get("/api/v2/search", query: query, useToken: true)' in sdk
assert sdk.count('"/api/v2/search", query: query, useToken: true') == 4  # movies/actors/named/lists
assert '"/api/v2/search_image", query: ["image_url": imageURL], useToken: true' in sdk
assert '"/api/v1/movies/may_also_like", query: ["id": id, "limit": "9"], useToken: true' in sdk
# recommend/latest stay anonymous (server still allows them).
assert '"/api/v1/movies/recommend", query: query)' in sdk

detail = (r/'AVDB/Views/Detail/MovieDetailView.swift').read_text()

# --- 2. 猜你喜欢: endpoint-fed, payload relatives as fallback ---
assert 'GlassSectionHeader(title: "猜你喜欢", icon: "sparkles", trailingTitle: nil)' in detail
assert 'try? await sdk.mayAlsoLike(movieID)' in detail
assert 'for item in liked + relatedMovies where seen.insert(item.id).inserted' in detail
# --- 3. Ta 还出演过: official actor endpoint upgrade, current movie dropped ---
assert 'try? await sdk.actorMovies(primary.id, page: 1, limit: 21, type: catalogType)' in detail
assert 'item.id != movieID' in detail
# --- 4. Liquid glass hero buttons ---
group = detail.split('private func portraitActionGroup')[1].split('private func posterAction')[0]
assert '.liquidGlass(interactive: false, clear: true)' in group  # 339: clear glass, backdrop shows through
assert '.background(.clear, in: Capsule())' not in group
pill = (r/'AVDB/Views/Detail/DetailPlayPill.swift').read_text()
assert '.liquidGlass(interactive: true, clear: true)' in pill  # 339: clear glass, backdrop shows through
assert '.background(.clear, in: Capsule())' not in pill
assert 'Capsule().stroke(.white.opacity(0.72)' not in pill

# --- 5. Search errors surface instead of a silent empty page ---
search = (r/'AVDB/Views/Search/SearchView.swift').read_text()
assert 'vm.movies.isEmpty, !vm.isLoading, let error = vm.errorMessage' in search

# --- 6. Rail HD for original-type items: catalogue portrait poster upgrade ---
loader = (r/'AVDB/Services/ImageLoader.swift').read_text()
policy = loader.split('enum VisibleHQPosterPolicy')[1].split('actor VisibleHQPosterScheduler')[0]
assert 'movie.catalogueMetadata?.poster' in policy
assert 'poster != movie.thumbURL' in policy
assert '!original || movie.catalogueMetadata?.poster != nil' in loader
assert 'enrichRailCovers' in detail and 'sdk.catalogueEnriched(item)' in detail
assert detail.count('await enrichRailCovers(') == 2  # both rails

print('PASS test-detail-api335: search family + mayAlsoLike send the token, detail 猜你喜欢 fed by '
      'may_also_like with payload fallback, Ta 还出演过 via the actor endpoint, portrait hero buttons '
      'on Liquid Glass, search errors surfaced, release 340')
