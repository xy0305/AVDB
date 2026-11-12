#!/usr/bin/env python3
"""Build 333 home hero detail image: the hero's sharp layer paints the detail
page's display image (art.image) — for a jacket-sourced winner the resolver's
front display raster, never the uncropped raw envelope; the jacket floor stays
as the transition and the winner swaps in automatically; the hero bottom
graduates into the page background (detail-style) with the bottom chrome
riding above the fade band. Static source contracts on Linux; XCTest unit
tests (HomeHero333Tests) run on CI."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '345' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 345;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2

wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 345' in wf and 'feat/home-hero-detail-333' in wf
assert 'feat/home-hero-color-332' in wf and 'feat/home-hero-crop-331' in wf
assert wf.count('python3 scripts/test-home-hero333.py') == 2  # static job + release regressions
assert 'python3 scripts/test-home-hero332.py' in wf
assert 'scripts/package-lut345.py' in wf and 'AVDB-345-release' in wf and 'AVDB-332-release' not in wf
pkg = (r/'scripts/package-lut345.py').read_text()
assert "=='345'" in pkg and 'AVDB-unsigned-1.0.2-345-western-actor-ranking.ipa' in pkg and "MinimumOSVersion']=='17.0'" in pkg
job = wf.split('  home-hero-333:')[1]
assert '-only-testing:DetailPosterQualityTests/HomeHero333Tests' in job
assert 'AVDB-345-home-hero-detail-tests' in job
assert '  home-hero-332:' in wf and '  home-hero-331:' in wf

doc = (r/'Build333-HomeHeroDetail.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '333' in doc
assert 'art.image' in doc and 'gradient' in doc.lower()
assert 'unsigned' in doc.lower()
# Credit the user's request.
assert '直接用详情页大图' in doc

resolver = (r/'AVDB/Services/HeroCoverResolver.swift').read_text()
home = (r/'AVDB/Views/Home/HomeView.swift').read_text()
store = resolver.split('final class HeroCoverStore')[1].split('actor HeroCoverPrefetchGate')[0]
page = home.split('private struct HomeHeroPage: View {')[1].split('private struct HomeHeroMoreButton')[0]
hero = home.split('private struct HomeHeroCarousel: View {')[1].split('private struct HeroTouchStyle')[0]
scrims = hero.split('private var scrims: some View {')[1].split('private var textBlock')[0]

# --- 1. Sharp layer is the detail page's display image, not the raw envelope ---
primary = resolver.split('static func primaryImage(from art: DetailPosterArtwork) -> UIImage {')[1].split('}')[0]
assert 'art.image' in primary, 'hero sharp layer must be art.image (the detail display image)'
assert 'rawImage' not in primary, 'Build 333 supersedes the 332 rawImage choice in primaryImage'
assert 'HeroResolverSharp.primaryImage(from: art)' in store

# --- 2. Floor stays the original-bitmap transition (user's pick) ---
assert 'ImageLoader.shared.load(' in store
assert 'ImageLoader.shared.loadPoster(' not in store, 'hero store must not crop via loadPoster'
assert 'ImageLoader.shared.load(' in page and 'ImageLoader.shared.loadPoster(' not in page

# --- 3. Detail-style bottom gradient into the page background ---
assert 'let band: CGFloat = 56' in scrims
assert 'Color(.systemBackground).opacity(0)' in scrims
assert '.init(color: Color(.systemBackground), location: edge)' in scrims
assert '.init(color: .black.opacity(0), location: edge)' in scrims, 'black scrim must hand off inside the fade band'
assert 'heroContentOverlap' in scrims

# --- 4. Bottom chrome rides above the fade band ---
assert '.padding(.bottom, 46 + HomeMetrics.heroContentOverlap)' in hero, 'dots inset'
assert '(showsDots ? 66 : 50) + HomeMetrics.heroContentOverlap' in hero, 'text block inset'
assert '.padding(.bottom, 38 + HomeMetrics.heroContentOverlap)' in hero, 'more button inset'
assert 'HomeMetrics.heroContentOverlap' in home and 'static let heroContentOverlap: CGFloat = 32' in home

print('PASS test-home-hero333: sharp layer = detail display image (art.image), floor transition kept, '
      'detail-style bottom gradient into systemBackground, chrome above the fade band, release 345')
