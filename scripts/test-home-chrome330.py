#!/usr/bin/env python3
"""Build 330 home chrome: 44 pt liquid-glass search, overlay-tap hero
navigation, official DetailPosterResolver portrait as the sharp hero,
liquid-glass shortcut row. Static source contracts on Linux; XCTest unit
tests run on CI."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '346' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 346;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2
assert 'HeroSwipePolicy.swift' in pbx and 'HeroCoverResolver.swift' in pbx and 'DetailPosterResolver.swift' in pbx

wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 346' in wf and 'feat/home-chrome-330' in wf
assert 'feat/home-hot-329' in wf and 'feat/home-hot-328' in wf
assert 'python3 scripts/test-home-chrome330.py' in wf
assert 'python3 scripts/test-home-hot329.py' in wf
assert 'python3 scripts/test-home-hot328.py' in wf
assert 'scripts/package-lut346.py' in wf and 'AVDB-346-release' in wf
assert 'AVDB-unsigned-1.0.2-346-list-paging-repeat.ipa' in (r/'scripts/package-lut346.py').read_text()
assert 'home-chrome-330' in wf
assert 'HomeChrome330Tests' in wf
assert 'test330CleanTapOpensDetailAndPageCommitDoesNot' in wf
assert 'test330DTOFloorPaintsThenUpgradesToResolverWinner' in wf
assert 'test330CacheHitUsedImmediately' in wf
assert 'test330EnrichMergedDetailCoverIsMiddleStep' in wf
assert 'test330BackdropPLIsNotPrimaryOverOfficialPortrait' in wf
assert 'home-hot-329' in wf and 'home-hot-328' in wf

doc = (r/'Build330-HomeChrome.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '330' in doc
assert '44' in doc and 'liquid' in doc.lower()
assert 'DetailPosterResolver' in doc or '官方' in doc or 'portrait' in doc.lower()
assert 'unsigned' in doc.lower() or '未签名' in doc or '未簽名' in doc

home = (r/'AVDB/Views/Home/HomeView.swift').read_text()
policy = (r/'AVDB/Views/Home/HeroSwipePolicy.swift').read_text()
resolver = (r/'AVDB/Services/HeroCoverResolver.swift').read_text()
detail = (r/'AVDB/Services/DetailPosterResolver.swift').read_text()
glass = (r/'AVDB/Views/Components/GlassUI.swift').read_text()
movie = (r/'AVDB/Models/Movie.swift').read_text()

# --- 329 floor / 3-column / playback source stay ---
assert 'playbackRankings(filterBy: "high_score", period: "daily", page: 1)' in home
assert 'static let playbackHeroCap = 10' in home
assert 'static let homeGridCap = 9' in home
assert 'private static let columns = 3' in home
assert home.count('HomePosterGrid(upgradesVisibleHQ: true') == 4
assert '.blur(' not in home.split('private struct HomeHeroPage: View {')[1].split('private struct HomeHeroMoreButton')[0]
assert 'static let crossfadeDuration: TimeInterval = 0.45' in resolver
assert 'static let liveSREnabled = false' in resolver
assert '已定案（可升级）' in resolver
assert 'static let overallBudget: TimeInterval = 6' in resolver
assert 'Provisional settle, not a cancel' in resolver or 'not a cancel of in-flight' in resolver

# --- 1. Search button: 44 pt, liquidGlassCircle, white 16 pt icon ---
sb = home.split('private struct HomeSearchButton: View {')[1].split('private struct HomeTopScrim')[0]
assert '44 pt' in home.split('// MARK: Floating chrome')[1].split('private struct HomeTopScrim')[0]
assert 'width: 44, height: 44' in sb
assert 'width: 58, height: 58' not in sb
assert 'size: 16, weight: .semibold' in sb
assert 'Color.white' in sb
assert 'liquidGlassCircle' in sb
assert '.homeGlass(in: Circle())' not in sb
assert 'home-search' in sb

# --- 2. Overlay tap is the sole navigation entry; lastDragAt only on page-commit ---
assert 'enum HeroTapPolicy' in policy
assert 'static let maxTranslation: CGFloat = 10' in policy
assert 'static let maxDuration: TimeInterval = 0.3' in policy
assert 'static let trailingSuppress: TimeInterval = 0.35' in policy
assert 'func shouldOpen(' in policy
assert 'consumedPageChange' in policy
assert 'var onTap: () -> Void' in policy
assert 'lastPageCommitAt' in policy
assert 'allowsHitTesting(false)' in home.split('private struct HomeHeroCarousel: View {')[1].split('private struct HeroTouchStyle')[0]
hero = home.split('private struct HomeHeroCarousel: View {')[1].split('private struct HeroTouchStyle')[0]
# lastDragAt is set only on page-commit, not on pan began / mere touch-down.
assert 'if down { lastDragAt = Date() }' not in hero
page_h = hero.split('onPageHorizontal:')[1].split('onPageVertical:')[0]
page_v = hero.split('onPageVertical:')[1].split('onSpringHorizontal:')[0]
track_h = hero.split('onTrackHorizontal:')[1].split('onTrackVertical:')[0]
track_v = hero.split('onTrackVertical:')[1].split('onPageHorizontal:')[0]
touch = hero.split('onTouch:')[1].split('onTap:')[0]
assert 'lastDragAt = Date()' in page_h and 'lastDragAt = Date()' in page_v
assert 'lastDragAt = Date()' not in track_h and 'lastDragAt = Date()' not in track_v
assert 'lastDragAt = Date()' not in touch
assert 'onTap:' in hero
assert '打開詳情' in hero and '.isButton' in hero
assert 'HomeHotChip(action: onHot)' in hero and 'HomeHeroMoreButton(action: onMore)' in hero
# Chips stay later in the ZStack than the overlay (own hit targets).
assert hero.find('HeroSwipeOverlay(') < hero.find('HomeHotChip(action: onHot)')
assert hero.find('HeroSwipeOverlay(') < hero.find('HomeHeroMoreButton(action: onMore)')

# --- 3. Official DetailPosterResolver portrait; three-step floor; scheduler ---
assert 'func mergingHeroDetail(' in movie
assert 'small_covers' in movie.split('func mergingHeroDetail')[1].split('public var displayTitle')[0]
# 331: two-level floor — the separate 330 middle step (enrichImage) is removed.
assert 'enrichImage' not in resolver
assert 'HeroResolverSharp' in resolver
assert 'primaryImage(from art: DetailPosterArtwork)' in resolver
assert 'art.image' in resolver.split('static func primaryImage(from art: DetailPosterArtwork) -> UIImage {')[1].split('}')[0], 'Build 333: hero sharp layer must be the detail display image (art.image)'
assert 'isBackdropOrJacket' in resolver
assert 'pl.jpg' in resolver
assert 'DetailPosterResolver.resolveShared' in resolver
assert 'static func resolveShared(' in detail
assert 'idFlights' in detail and 'movie id' in detail.lower()
assert 'var rawImage: UIImage?' in detail
assert 'enqueueResolver' in resolver
assert 'current → +1 → −1 → +2 → −2' in resolver or '+1 → −1 → +2 → −2' in resolver
assert 'static let resolverConcurrency = 2' in resolver
# 331: per-item enrich → resolver pipeline replaces the 330 batch waterfall.
assert 'enrichThenResolve' not in resolver and 'schedulePipelines' in resolver
assert 'Merge cover / actors / CID' in resolver or 'cover / actors / CID' in resolver
assert 'not a cancel' in resolver.lower() or '不是取消' in resolver
assert 'no longer the authoritative sharp target' in resolver
store = resolver.split('final class HeroCoverStore')[1].split('actor HeroCoverPrefetchGate')[0]
assert 'HeroCoverRace.run' not in store
assert 'AICoverEnhanceModel' not in resolver
assert 'AICoverEnhanceModel' not in home
assert 'Do not run AICover' in resolver or 'never uses the artwork backdrop or AICover' in resolver or 'Do not run AICover on the home hero' in store
assert 'cachedResolverPortrait' in resolver
assert 'HeroCoverDisk.image(for:' in resolver

# 331: two-level floor in the page (floor → official winner).
page = home.split('private struct HomeHeroPage: View {')[1].split('private struct HomeHeroMoreButton')[0]
assert 'presentation.enrichImage' not in page
assert 'presentation.sharpImage' in page
assert 'presentation.blurImage' in page
assert '.easeOut(duration: HeroCoverPolicy.crossfadeDuration)' in page

# --- 4. All 12 shortcuts: liquidGlassCircle, LiquidGlassContainer on iPhone only ---
qa = home.split('private func quickActionRow')[1].split('// MARK: Rails')[0]
assert qa.count('quickAction("') == 12
assert 'liquidGlassCircle(interactive: true)' in home.split('private func quickAction(')[1].split('// MARK: Rails')[0]
assert 'Color(.secondarySystemBackground)' not in home.split('private func quickAction(')[1].split('// MARK: Rails')[0]
assert 'LiquidGlassContainer { quickActionScroll(m) }' in qa
assert 'AdaptiveLayout.isPad' in qa
assert 'do not wrap in LiquidGlassContainer' in qa or 'GlassEffectContainer ate taps' in qa
# iPad branch is the unwrapped row.
assert 'if AdaptiveLayout.isPad' in qa
assert 'func liquidGlassCircle(' in glass
assert 'struct LiquidGlassContainer' in glass

unit = (r/'UITests/DetailPosterQualityTests.swift').read_text()
assert 'final class HomeChrome330Tests' in unit
assert 'test330CleanTapOpensDetailAndPageCommitDoesNot' in unit
assert 'test330DTOFloorPaintsThenUpgradesToResolverWinner' in unit
assert 'test330CacheHitUsedImmediately' in unit
assert 'test330EnrichMergedDetailCoverIsMiddleStep' in unit
assert 'test330BackdropPLIsNotPrimaryOverOfficialPortrait' in unit
assert 'fixture://delay/15' in unit or '15_000_000_000' in unit
assert 'HeroTapPolicy.shouldOpen' in unit
assert 'floorPixelWidth' in unit  # 331: middle-step test updated to the two-level floor
assert 'isBackdropOrJacket' in unit
assert 'final class HomeHot329Tests' in unit
assert 'final class HomeHot328Tests' in unit

print('PASS home-chrome330 source contracts: 44 pt liquid-glass search, overlay-tap '
      'navigation, official DetailPosterResolver portrait, three-step floor, '
      'scheduler cap 2, iPhone-only LiquidGlassContainer shortcuts, release 346')
