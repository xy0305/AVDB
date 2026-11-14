#!/usr/bin/env python3
"""Build 344 poster-grid bottom clearance. Contracts: the last row of a
poster grid no longer rests underneath the floating tab bar. The bar
overlays the bottom ~94 pt of the screen (a ~60 pt pill above the
home-indicator zone), and grid pages never received that bottom inset:
on Build 343 the user screen-recorded the period-610 list, whose last
row (KSBJ-416 / IPZZ-809) sat behind the bar at rest and could only be
seen while holding a rubber-band overscroll. MoviePosterGrid — the one
grid shared by the period lists, list pages, actor filmographies,
category movie pages, search results, rankings and library pages — now
reserves a fixed bottom clearance as padding after the grid, so every
page using it can rest its last row clear of the bar. Nothing else
about the grid changes: columns, spacing, cell content, navigation and
the onAppear pagination hook are untouched, and the home rails (a
different component, HomePosterGrid) are not affected. Static source
contracts on Linux; behaviour verified on device."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '350' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 350;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2

wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 350' in wf and 'feat/list-tabbar-clearance-344' in wf
assert 'feat/list-landscape-cover-343' in wf and 'feat/reviews-panel-pending-342' in wf
assert wf.count('python3 scripts/test-list-tabbar-clearance344.py') == 5  # dedicated job + zzt-ranking list + remove-javverse/detail-api jobs + release regressions
assert wf.count('python3 scripts/test-list-landscape-cover343.py') == 5  # the 343 gate keeps its 5 run lines
assert 'scripts/package-lut350.py' in wf and 'AVDB-350-release' in wf and 'AVDB-343-release' not in wf
pkg = (r/'scripts/package-lut350.py').read_text()
assert "=='350'" in pkg and 'AVDB-unsigned-1.0.2-350-rankings-auth.ipa' in pkg and "MinimumOSVersion']=='17.0'" in pkg
assert '  list-tabbar-clearance-344:' in wf and '  list-landscape-cover-343:' in wf

doc = (r/'Build344-ListTabBarClearance.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '344' in doc
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


ui = (r/'AVDB/Views/Components/JAVDBUI.swift').read_text()
grid = func_body(ui, 'struct MoviePosterGrid: View')

# --- 1. The clearance is declared once, on the shared grid ---
assert 'static let tabBarBottomClearance: CGFloat = 100' in grid

# --- 2. …and applied as bottom padding after the grid ---
assert '.padding(.bottom, Self.tabBarBottomClearance)' in grid
assert grid.count('tabBarBottomClearance') == 2  # declaration + the one application

# --- 3. The grid itself is otherwise unchanged ---
assert 'LazyVGrid(columns: columns, spacing: 16)' in grid
assert '.padding(.horizontal, AdaptiveLayout.gridPadding)' in grid
assert 'MoviePosterCard(movie: movie' in grid
assert 'onAppearLast?(movie)' in grid

print('PASS test-list-tabbar-clearance344: MoviePosterGrid reserves a '
      '100 pt bottom clearance so the last row rests clear of the '
      'floating tab bar on every grid page, release 350')
