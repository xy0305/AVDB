#!/usr/bin/env python3
"""Build 339 clear glass. Contracts: at the user's direction the detail
page's play pill and portrait action group switch from iOS 26 `.regular`
Liquid Glass to the `.clear` variant, so the backdrop colour and image
show through instead of the milky pale sampling `.regular` produced over
the detail backdrop (#D0C6C4 sampled). The switch is a material-only
change scoped to exactly those two call sites: LiquidGlassEffect gains a
defaulted `clear` flag, the `.regular` path stays the default for every
other call site (home chrome, tab bar, search, shortcuts), and neither
layout, icons, text nor behaviour move. The pre-iOS 26 glassSurface
fallback is unchanged (its base is already .ultraThinMaterial and its
tintStrength only modulates the optional tint glaze neither call site
uses). Static source contracts on Linux; behaviour verified on device."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '342' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 342;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2

wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 342' in wf and 'feat/detail-glass-clear-339' in wf
assert 'feat/logout-access-338' in wf and 'feat/recommender-throttle-337' in wf
assert wf.count('python3 scripts/test-clear-glass339.py') == 5  # dedicated job + zzt-ranking list + remove-javverse/detail-api jobs + release regressions
assert wf.count('python3 scripts/test-logout-access338.py') == 5  # the 338 gate keeps its 5 run lines
assert 'scripts/package-lut342.py' in wf and 'AVDB-342-release' in wf and 'AVDB-338-release' not in wf
pkg = (r/'scripts/package-lut342.py').read_text()
assert "=='342'" in pkg and 'AVDB-unsigned-1.0.2-342-reviews-panel-pending.ipa' in pkg and "MinimumOSVersion']=='17.0'" in pkg
assert '  clear-glass-339:' in wf and '  logout-access-338:' in wf

doc = (r/'Build339-ClearGlass.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '339' in doc
assert 'unsigned' in doc.lower()

glass = (r/'AVDB/Views/Components/GlassUI.swift').read_text()
effect = glass.split('struct LiquidGlassEffect')[1].split('struct LiquidGlassRectEffect')[0]

# --- 1. Clear path exists for every tint/interactive combination; .regular stays the default ---
assert 'var clear: Bool = false' in effect
assert '.clear.tint(tint).interactive()' in effect and '.clear.tint(tint)' in effect
assert '.clear.interactive()' in effect and 'interactive ? .clear.interactive() : .clear' in effect
assert '.regular.tint(tint).interactive()' in effect and '.regular.tint(tint)' in effect
assert '.regular.interactive()' in effect and 'interactive ? .regular.interactive() : .regular' in effect
assert 'func liquidGlass(tint: Color? = nil, interactive: Bool = false, clear: Bool = false)' in glass
# The gradient edge stroke stays on both paths (edge definition over a visible backdrop).
assert 'Capsule().strokeBorder(' in effect and '.white.opacity(0.35)' in effect
# Pre-iOS 26 fallback untouched: same glassSurface call as before 339.
assert 'content.glassSurface(in: Capsule(), tint: tint, tintStrength: tint == nil ? 0 : 0.16)' in effect

# --- 2. Exactly the two detail call sites opt into clear glass ---
pill = (r/'AVDB/Views/Detail/DetailPlayPill.swift').read_text()
assert pill.count('clear: true') == 1
assert '.liquidGlass(interactive: true, clear: true)' in pill
detail = (r/'AVDB/Views/Detail/MovieDetailView.swift').read_text()
group = detail.split('private func portraitActionGroup')[1].split('private func posterAction')[0]
assert group.count('clear: true') == 1
assert '.liquidGlass(interactive: false, clear: true)' in group
total_clear = sum(p.read_text().count('clear: true')
                  for p in (r/'AVDB').rglob('*.swift'))
assert total_clear == 2  # scope containment: no other call site gets clear glass

# --- 3. Legibility over the now-visible backdrop: white foreground + shadow unchanged ---
assert '.foregroundStyle(.white)' in pill
assert '.shadow(color: .black.opacity(0.65), radius: 2, y: 1)' in pill

print('PASS test-clear-glass339: detail play pill and portrait action group on '
      '.clear liquid glass (backdrop shows through), every other call site '
      'still on the .regular default, release 342')
