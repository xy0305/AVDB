#!/usr/bin/env python3
"""Build 343 list landscape covers. Contracts: a poster cell whose only
artwork is an uncropped landscape image no longer renders that image as
a magnified centre slice. The reported case is HEYZO-2706 in the period
603 list: JavDB serves its cover as an 800x450 landscape promo (ratio
1.78), the recommend payload carries no portrait thumb, and
FrontPosterPolicy.isKnownWrap promotes the JavDB-CDN /covers/ URL to
lead with frontPoster cropping — but PosterColorCrop only crops jacket
ratios 1.35...1.65, so the raw landscape reached the cell and
JavDBImage's candidate loop published it through its landscapeFallback
path, where the cell's .fill content mode blew up the pale middle band
of the image across the whole portrait cell. The loop's portrait
preference is unchanged (a portrait fallback still wins whenever one
exists). What changes is only the final render: JavDBImage gains an
opt-in flag, and MoviePosterImage — the one shared list poster cell —
opts in, so a published image that is still landscape is shown whole
(.fit, letterboxed) instead of centre-sliced (.fill). Every other
JavDBImage caller keeps the default and renders exactly as before.
Static source contracts on Linux; behaviour verified on device."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '350' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 350;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2

wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 350' in wf and 'feat/list-landscape-cover-343' in wf
assert 'feat/reviews-panel-pending-342' in wf and 'feat/reviews-first-load-341' in wf
assert wf.count('python3 scripts/test-list-landscape-cover343.py') == 5  # dedicated job + zzt-ranking list + remove-javverse/detail-api jobs + release regressions
assert wf.count('python3 scripts/test-reviews-panel-pending342.py') == 5  # the 342 gate keeps its 5 run lines
assert 'scripts/package-lut350.py' in wf and 'AVDB-350-release' in wf and 'AVDB-342-release' not in wf
pkg = (r/'scripts/package-lut350.py').read_text()
assert "=='350'" in pkg and 'AVDB-unsigned-1.0.2-350-rankings-auth.ipa' in pkg and "MinimumOSVersion']=='17.0'" in pkg
assert '  list-landscape-cover-343:' in wf and '  reviews-panel-pending-342:' in wf

doc = (r/'Build343-ListLandscapeCover.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '343' in doc
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


loader = (r/'AVDB/Services/ImageLoader.swift').read_text()

# --- 1. JavDBImage gains the opt-in and renders through the effective mode ---
javdb_image = func_body(loader, 'public struct JavDBImage: View')
assert 'let fitUncroppedLandscape: Bool' in javdb_image
assert 'fitUncroppedLandscape: Bool = false' in javdb_image  # default off: other callers untouched
mode = func_body(javdb_image, 'private var displayedContentMode: ContentMode')
assert 'fitUncroppedLandscape' in mode and 'image.size.width > image.size.height' in mode
assert 'return .fit' in mode and 'return contentMode' in mode  # landscape -> whole image; anything else -> caller's mode
assert '.aspectRatio(contentMode: displayedContentMode)' in javdb_image

# --- 2. The candidate loop's portrait preference is unchanged ---
assert 'landscapeFallback = landscapeFallback ?? (img, candidate)' in javdb_image
assert 'if frontPoster, img.size.width > img.size.height' in javdb_image

# --- 3. Only the shared list poster cell opts in ---
poster = func_body(loader, 'public struct MoviePosterImage: View')
assert 'frontPoster: !original || wrapLead, fitUncroppedLandscape: true' in poster
assert loader.count('fitUncroppedLandscape: true') == 1

# --- 4. The jacket machinery is untouched ---
assert '(1.35...1.65).contains(ratio)' in loader  # crop band unchanged
assert 'PosterColorCrop.cropIfNeeded(original, source: source)' in loader

print('PASS test-list-landscape-cover343: poster cells show an uncropped '
      'landscape cover whole (.fit) instead of a magnified centre slice, '
      'portrait fallbacks still win, jacket cropping and every other '
      'JavDBImage caller unchanged, release 350')
