#!/usr/bin/env python3
"""Build 324 首页大图卡: 竖版正面封套大卡 + 模糊海报背景渐变 + 一行标题 + 圆点下移.
Static source contracts on Linux."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '324' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 324;') == 2

wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 324' in wf and 'feat/home-hero-324' in wf
assert 'python3 scripts/test-home-hero324.py' in wf
assert 'scripts/package-lut324.py' in wf and 'AVDB-324-release' in wf and 'AVDB-323-' not in wf
pkg = (r/'scripts/package-lut324.py').read_text()
assert "=='324'" in pkg and 'AVDB-unsigned-1.0.2-324-home-hero.ipa' in pkg
assert (r/'Build324-HomeHero.md').is_file()

home = (r/'AVDB/Views/Home/HomeView.swift').read_text()
carousel = home.split('private struct RecommendCarousel: View {')[1].split('private struct RecommendHeroCard: View {')[0]
card = home.split('private struct RecommendHeroCard: View {')[1].split('struct ArticlesView: View {')[0]

# Hero card: portrait front poster, one-line number + title only — no date, score, stars or play button.
assert 'RecommendBannerCard' not in home and 'bannerHeight' not in home
assert 'frontPoster: true' in card
assert 'movie.displayNumber' in card and 'movie.displayTitle' in card and '.lineLimit(1)' in card
for banned in ['releaseDate', 'score', 'star.fill', 'play.circle']:
    assert banned not in card, banned

# Carousel: full-width card (no peek), height from the 3:4 poster ratio, dots below, no text block under the card.
assert 'cardWidth * 4 / 3' in carousel
assert '- 36' not in carousel and 'star.fill' not in carousel
assert 'Circle()' in carousel
assert carousel.index('ScrollView(.horizontal') < carousel.index('Circle()')

# Backdrop: blurred current poster fading into the page background, crossfading on page change.
assert 'private func backdrop' in carousel and '.blur(radius: 28)' in carousel
assert '.mask {' in carousel and 'frontPoster: true' in carousel

# Paging behaviour kept: scroll position binding + ~4 s auto-advance.
assert 'scrollPosition(id: $currentID)' in carousel and 'Timer.publish(every: 4' in carousel
print('PASS home-hero324 source contracts: portrait hero card, blurred backdrop, one-line title, dots below, release 324')
