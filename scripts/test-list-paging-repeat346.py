#!/usr/bin/env python3
"""Build 346 list paging repeat. Contracts: the shared movie-list
view model can no longer repeat a list forever. The user
screen-recorded the 第610期 recommend-period page on Build 344: its
ten movies cycled endlessly while scrolling. Verified live before
coding (2026-11-12, the app's own signing): GET
/api/v1/movies/recommend ignores `page` for a period query — pages
1, 2 and 3 for period 610 all return the identical ten movies — and
MovieListViewModel.loadMore appended every page verbatim, stopping
only on an empty page, so each "next page" re-appended the whole
period. The loop only became visible once Build 344 let the last
row rest in view and fire onAppearLast at rest. loadMore now drops
ids that are already shown (within the page and across pages) and
treats a page that contributes nothing new as the end of the list —
the same rule CatalogListViewModel already applies. Properly paged
endpoints are unaffected: their pages keep contributing new ids
until an empty page ends the list, exactly as before. Static source
contracts on Linux; behaviour verified live and on device."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '348' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 348;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2

wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 348' in wf and 'feat/list-paging-repeat-346' in wf
assert 'feat/western-actor-ranking-345' in wf and 'feat/list-tabbar-clearance-344' in wf
assert wf.count('python3 scripts/test-list-paging-repeat346.py') == 5  # dedicated job + zzt-ranking list + remove-javverse/detail-api jobs + release regressions
assert wf.count('python3 scripts/test-western-actor-ranking345.py') == 5  # the 345 gate keeps its 5 run lines
assert 'scripts/package-lut348.py' in wf and 'AVDB-348-release' in wf and 'AVDB-345-release' not in wf
pkg = (r/'scripts/package-lut348.py').read_text()
assert "=='348'" in pkg and 'AVDB-unsigned-1.0.2-348-actor-grid-scroll.ipa' in pkg and "MinimumOSVersion']=='17.0'" in pkg
assert '  list-paging-repeat-346:' in wf and '  western-actor-ranking-345:' in wf

doc = (r/'Build346-ListPagingRepeat.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '346' in doc
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


vm = (r/'AVDB/Services/MovieListViewModel.swift').read_text()
load_more = func_body(vm, 'func loadMore() async')

# --- 1. Appends are deduped against what is already shown ---
assert 'var known = Set(movies.map(\\.id))' in load_more
assert 'let fresh = result.filter { known.insert($0.id).inserted }' in load_more
assert 'movies.append(contentsOf: fresh)' in load_more
assert 'movies.append(contentsOf: result)' not in load_more  # the blind append is gone

# --- 2. A page with nothing new ends the list ---
assert 'if fresh.isEmpty { hasMore = false }' in load_more
assert 'if result.isEmpty {' in load_more  # the classic empty-page stop stays

# --- 3. The trigger path is unchanged: last cell still asks for more ---
assert 'func loadMoreIfNeeded(current movie: Movie)' in vm
grid_host = (r/'AVDB/Views/Home/HomeView.swift').read_text()
assert 'onAppearLast: { movie in' in grid_host and 'recommendMovies(page: page, period: p)' in grid_host

# --- 4. The catalogue VM's identical rule is untouched ---
catalog = func_body(vm, 'final class CatalogListViewModel')
assert 'self.hasMore = !result.isEmpty && appended > 0' in catalog

print('PASS test-list-paging-repeat346: shared list paging dedupes '
      'by id and stops when a page adds nothing new, so fixed-list '
      'endpoints (period recommendations) can no longer repeat '
      'forever, release 348')
