#!/usr/bin/env python3
"""Build 326 home hero HQ image pipeline: independent HeroCoverResolver, A/B/C
tiers, no inset-card fallback, no carousel eviction, autoplay A/B-only, rail
floor, decode cap 2048. Static source contracts on Linux (Swift compile and
simulator screenshots run on CI)."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '330' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 330;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2
assert 'HeroCoverResolver.swift' in pbx and 'HERO32600000000000001B' in pbx

# Release wiring.
wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 330' in wf and 'feat/home-hero-hq-326' in wf
assert 'python3 scripts/test-home-hero-hq326.py' in wf and 'test-home-immersive325.py' not in wf
assert 'scripts/package-lut330.py' in wf and 'AVDB-330-release' in wf and 'AVDB-325-' not in wf
assert 'AVDB-330-home-screenshots' in wf and 'test326HomeHeroHQScreenshots' in wf
assert 'home-hero-hq-screenshots' in wf
assert 'llama|SherpaOnnxC' in wf  # screenshot job still drops device-only xcframeworks
assert not (r/'scripts/test-home-immersive325.py').exists() and not (r/'scripts/package-lut325.py').exists()
pkg = (r/'scripts/package-lut330.py').read_text()
assert "=='330'" in pkg and "MinimumOSVersion']=='17.0'" in pkg and 'AVDB-unsigned-1.0.2-330-home-chrome.ipa' in pkg
doc = (r/'Build326-HomeHeroHQ.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '326' in doc

home = (r/'AVDB/Views/Home/HomeView.swift').read_text()
resolver = (r/'AVDB/Services/HeroCoverResolver.swift').read_text()
view = home.split('struct HomeView: View {')[1].split('// Small list-only snapshot')[0]
hero = home.split('private struct HomeHeroCarousel: View {')[1].split('private struct HeroTouchStyle')[0]
page = home.split('private struct HomeHeroPage: View {')[1].split('private struct HomeAnchoredFill')[0]
metrics = home.split('struct HomeMetrics {')[1].split('extension View {')[0]
loader = (r/'AVDB/Services/ImageLoader.swift').read_text()
detail = (r/'AVDB/Services/DetailPosterResolver.swift').read_text()

# --- Resolver: independent pipeline, not VisibleHQPosterPolicy ---
assert 'enum HeroCoverPolicy' in resolver and 'enum HeroCoverResolver' not in resolver  # façade is HeroCoverStore
assert 'final class HeroCoverStore' in resolver and 'enum HeroCoverRace' in resolver
assert 'static let decodeCap = 2048' in resolver
assert 'static let sourceTimeout: TimeInterval = 4' in resolver
assert 'static let overallBudget: TimeInterval = 6' in resolver
assert 'static let graceWindow: TimeInterval = 0.4' in resolver
assert 'static let crossfadeDuration: TimeInterval = 0.45' in resolver
assert 'static let prefetchConcurrency = 3' in resolver
assert 'static let resolverConcurrency = 2' in resolver
assert 'static let lowPowerPrefetchConcurrency = 1' in resolver
assert 'static let negativeTTL: TimeInterval = 60' in resolver
assert 'static let aspectMin = 1.30' in resolver and 'static let aspectMax = 1.55' in resolver
assert 'static let tierAWidth = 1000' in resolver
assert 'static let tierBWidth = 700' in resolver
assert 'static let tierCWidth = 360' in resolver
assert 'static let sameTierWidthEpsilon = 0.10' in resolver
assert 'func prefers(' in resolver
assert 'isNativePortraitPS' in resolver
# Must not reuse VisibleHQ for hero.
assert 'VisibleHQPosterScheduler' not in resolver
assert 'VisibleHQPosterPolicy.upgradeURL' not in resolver and 'VisibleHQPosterPolicy.maxPixelCap' not in resolver
assert 'VisibleHQPosterPolicy' not in hero and 'VisibleHQPosterScheduler' not in hero
assert 'HomeHeroImageLoader' not in home and 'struct HomeHeroImage ' not in home
assert 'enum HeroCoverNegativeCache' in resolver and 'hero-hq-326#' in resolver
assert 'ListHQCoverCache.storeNegative' not in resolver
# Source priority + banned thumbs.
assert 'DetailPosterPolicy.candidates' in resolver
assert 'DMMCoverURLs.upgrade' in resolver
assert 'AmazonPoster.allowedImage' in resolver
assert 'TenhowPoster.allowedImage' in resolver and 'AvbaseMetadata.allowedDiscoveredImage' in resolver
assert 'isBannedAsSharpURL' in resolver and 'pics.dmm.co.jp' in resolver and 'small_covers' in resolver
assert 'HeroCoverDisk.image(for:' in resolver and 'hero-hq-326#' in resolver
# Low Power must not skip hero resolution; only prefetch concurrency / non-adjacent deferral.
assert 'isLowPowerModeEnabled' in resolver
assert 'Must not skip' in resolver or 'always highest priority' in resolver or 'isCurrent' in resolver
assert 'if ProcessInfo.processInfo.isLowPowerModeEnabled { return nil }' not in resolver
# Decode cap 2048 on sharp loads.
assert 'maxPixelSize: HeroCoverPolicy.decodeCap' in resolver
# Four phases, no spinner.
assert 'case empty' in resolver and 'case blur' in resolver and 'case provisional' in resolver and 'case finalized' in resolver
assert 'ProgressView' not in resolver and 'ProgressView' not in page
# Memory: current + next only.
assert 'evictNonAdjacentBitmaps' in resolver
# CoverSR hook is off the acceptance path.
assert 'enum HeroCoverSRHook' in resolver and 'static let liveSREnabled = false' in resolver
assert 'TODO(Build 326+)' in resolver
assert 'Do not replace the in-memory current page' in resolver or 'hot-swap' in resolver
# Never mutate the movie array.
assert 'recommended.remove' not in home and 'movies.removeAll' not in hero
assert 'self.recommended = movies' in home
assert 'dot count stays fixed' in home or 'never mutates this array' in home

# --- Home: no inset card, four full-bleed states, 0.45s easeOut ---
assert 'pixelWidth < 500' not in home
assert 'cornerRadius: 20' not in page
assert '.aspectRatio(contentMode: .fit)' not in page
assert 'HomeShimmer()' not in page
assert '.blur(' not in page  # 329: hero main layer is never blurred
assert 'colorMultiply' not in page
assert 'HomeTheme.heroLoadingFloor' in page
assert 'HomeTheme.fallbackBase' not in page  # 328: never paint #2A2019 as the empty floor
assert '.easeOut(duration: HeroCoverPolicy.crossfadeDuration)' in page
assert 'HeroCoverStore.shared' in hero
assert 'presentation: cover(movie)' in hero or 'presentation: cover(movie)' in home
assert 'func nextABIndex()' in hero and 'currentCover.isAB && hasABPage' in hero
assert 'go(to: next, slide: false, delta: 1)' in hero
assert '高清封面加载失败，下拉刷新重试' in hero
assert 'showCoverFailure' in hero
assert 'clearNegativesAndRetry' in view
assert 'retryOnForeground' in hero
assert 'heroCoverNetworkRecovered' in hero
assert 'm.heroHeight' in view
assert 'frame(height: 220' not in home and 'height: 220' not in home
assert 'accessibilityIdentifier("home-hero")' in hero
assert '--home326-fixture' in home
assert 'var heroHeight: CGFloat { isPadWidth ? 600 : min(max(width * 1.15, 430), 560) }' in metrics

# --- Rails: floor only, pipeline otherwise unchanged ---
assert 'enum RailCoverFloor' in loader and 'static let minWidth = 360' in loader
assert 'RailCoverFloor.rejects' in loader
assert 'pics.dmm.co.jp' in loader.split('enum RailCoverFloor')[1].split('public enum ListCoverPolicy')[0]
assert loader.count('HomePosterRail(upgradesVisibleHQ: true') == 0  # that's in HomeView
assert view.count('HomePosterGrid(upgradesVisibleHQ: true') == 4  # 329 3×3 grids; 328 added 往期推薦
assert 'static let maxPixelCap = 900' in loader

# --- Detail write-back ---
assert 'HeroCoverDisk.storeAccepted' in detail
assert 'title-scoped hero key' in detail or 'priority 1' in detail

# --- 325 immersive contracts kept (typography, scrims, glass, rails, search, tabs) ---
assert '.ignoresSafeArea(.container, edges: .top)' in view
assert 'HomeHeroCarousel(' in view
for stop in ['.init(color: .black.opacity(0), location: 0.35)', '.init(color: .black.opacity(0.18), location: 0.62)',
             '.init(color: .black.opacity(0.45), location: 0.82)', '.init(color: .black.opacity(0.66), location: 1.0)']:
    assert stop in hero, stop
assert '.black.opacity(0.28)' in hero and '.frame(height: 110)' in hero
text = hero.split('private var textBlock: some View {')[1].split('private var swipe')[0]
assert 'VStack(alignment: .leading, spacing: 6)' in text
assert '.font(.system(size: 23, weight: .bold))' in text and '.lineLimit(1)' in text
assert '.font(.system(size: 13, weight: .medium))' in text and 'opacity(0.72)' in text
assert '.font(.system(size: 13, weight: .regular))' in text and 'opacity(0.85)' in text and '.lineLimit(2)' in text
assert 'final class HomeHeroSynopsisStore' in home
assert 'HomeHeroDots(' not in text and 'HomeHeroDots(count:' in hero
dots = home.split('private struct HomeHeroDots: View {')[1].split('// MARK: Rails')[0]
assert 'HStack(spacing: 5)' in dots and 'width: i == index ? 18 : 6, height: 6' in dots
assert 'Task.sleep(nanoseconds: 5_000_000_000)' in hero and '.easeInOut(duration: 0.6)' in hero
assert 'zoomed ? 1.05 : 1.0' in page and '.linear(duration: 5.6)' in page
for cond in ['!touching', '!dragging', 'scenePhase == .active', '!reduceMotion', '!voiceOver', 'movies.count > 1']:
    assert cond in hero, cond
assert 'HeroSwipePolicy.pageSpringResponse' in hero or '.spring(response: 0.38, dampingFraction: 0.88)' in hero
assert 'pageSpringResponse: Double = 0.38' in (r/'AVDB/Views/Home/HeroSwipePolicy.swift').read_text()
assert 'PastRecommendView()' in view and 'HomeHotChip(' in hero and 'HomePastChip' not in home
assert '看熱播 · 日榜' in home
assert 'HomeAmbientBackground(ambient: ambient' in view
assert 'static let accent = Color(red: 1.0, green: 138.0 / 255.0, blue: 61.0 / 255.0)' in home
assert 'shortcutRow' not in home
qa = view.split('private func quickActionRow')[1].split('// MARK: Rails')[0]
assert qa.count('quickAction("') == 12
assert 'MoviePosterGrid(' not in view
assert 'usable / 3' in metrics  # 329: 3-column grid card width
sb = home.split('private struct HomeSearchButton: View {')[1].split('private struct HomeTopScrim')[0]
assert 'width: 44, height: 44' in sb
bar = (r/'AVDB/Views/AVDBNativeTabBar.swift').read_text()
chrome = (r/'AVDB/Views/TabBarChrome.swift').read_text()
assert 'case home, rankings, categories, actors, tangxin, one, me' in chrome
assert 'ForEach(AppTab.allCases)' in bar

ui = (r/'UITests/PosterNavigationTests.swift').read_text()
assert 'func test326HomeHeroHQScreenshots()' in ui and '326-home-hero-hq-top' in ui
assert 'home-hero' in ui.split('func test326HomeHeroHQScreenshots()')[1].split('func test236')[0]
assert 'hero.frame.width, window.frame.width' in ui

print('PASS home-hero-hq326 source contracts: independent HQ resolver, A/B/C tiers, no inset, '
      'no eviction, autoplay A/B-only, rail floor, decode cap 2048, release 330')
