#!/usr/bin/env python3
"""Build 334 home hero detail parity: the phone hero height mirrors
DetailPortraitGeometry.imageHeight exactly (min(width * 1.58, max(600,
height * 0.8))), so the home hero frames the same window of the poster as the
detail page; iPad keeps 600. Also pins the Build 333 test-target compile fix
(HomeHero333Tests must use HomeHero332Tests.sRGBImage and the plain Movie
initializer — the helpers it called in 333 do not exist). Static source
contracts on Linux; XCTest unit tests (HomeHero334Tests) run on CI."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '339' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 339;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2

wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 339' in wf and 'feat/home-hero-parity-334' in wf
assert 'feat/home-hero-detail-333' in wf and 'feat/home-hero-color-332' in wf
assert wf.count('python3 scripts/test-home-hero334.py') == 2  # static job + release regressions
assert 'python3 scripts/test-home-hero333.py' in wf
assert 'scripts/package-lut339.py' in wf and 'AVDB-339-release' in wf and 'AVDB-333-release' not in wf
pkg = (r/'scripts/package-lut339.py').read_text()
assert "=='339'" in pkg and 'AVDB-unsigned-1.0.2-339-clear-glass.ipa' in pkg and "MinimumOSVersion']=='17.0'" in pkg
job = wf.split('  home-hero-334:')[1]
assert '-only-testing:DetailPosterQualityTests/HomeHero334Tests' in job
assert 'AVDB-339-home-hero-parity-tests' in job
assert '  home-hero-333:' in wf and '  home-hero-332:' in wf

doc = (r/'Build334-HomeHeroParity.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '334' in doc
assert 'DetailPortraitGeometry' in doc and 'unsigned' in doc.lower()
# Credit the user's request.
assert '英雄区拉高' in doc

home = (r/'AVDB/Views/Home/HomeView.swift').read_text()
tests = (r/'UITests/DetailPosterQualityTests.swift').read_text()
metrics = home.split('struct HomeMetrics {')[1].split('/// Sections are capped')[0]

# --- 1. Phone hero height is the detail formula, fed by the real view height ---
assert 'var heroHeight: CGFloat { isPadWidth ? 600 : min(width * 1.58, max(600, height * 0.8)) }' in metrics
assert 'var height: CGFloat = 0' in metrics
assert 'HomeMetrics(width: proxy.size.width, safeTop: proxy.safeAreaInsets.top, height: proxy.size.height)' in home
detail = (r/'AVDB/Views/Detail/MovieDetailView.swift').read_text()
assert 'imageHeight = min(width * 1.58, max(600, availableSize.height * 0.8))' in detail

# --- 2. Build 333 contracts kept (display image + gradient) ---
resolver = (r/'AVDB/Services/HeroCoverResolver.swift').read_text()
primary = resolver.split('static func primaryImage(from art: DetailPosterArtwork) -> UIImage {')[1].split('}')[0]
assert 'art.image' in primary and 'rawImage' not in primary
assert 'let band: CGFloat = 56' in home

# --- 3. The 333 test-target compile fix stays fixed ---
hero333 = tests.split('final class HomeHero333Tests')[1].split('final class HomeHero334Tests')[0]
assert 'HomeHero332Tests.sRGBImage' in hero333
assert 'heroMovie' not in hero333 and 'render(width:' not in hero333
assert 'final class HomeHero334Tests' in tests

print('PASS test-home-hero334: phone hero height = DetailPortraitGeometry formula (detail parity), '
      'iPad 600 kept, 333 test compile fix pinned, release 339')
