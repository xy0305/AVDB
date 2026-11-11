#!/usr/bin/env python3
"""Build 328 home hero: 看熱播日榜 feed, blank-cover floor + per-item deadline,
vertical swipe arbitrator, 往期推薦 rail, light theme aligned with the detail
sheet. Static source contracts on Linux; XCTest unit + UI tests run on CI."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '331' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 331;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2
assert 'HeroSwipePolicy.swift' in pbx and 'HERO32800000000000001B' in pbx
assert 'HeroCoverResolver.swift' in pbx and 'HERO32600000000000001B' in pbx

wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 331' in wf and 'feat/home-hot-328' in wf
assert 'feat/detail-auth-327' in wf and 'feat/home-hero-hq-326' in wf
assert 'python3 scripts/test-home-hot328.py' in wf
assert 'python3 scripts/test-home-hero-hq326.py' in wf
assert 'python3 scripts/test-detail-auth327.py' in wf
assert 'scripts/package-lut331.py' in wf and 'AVDB-331-release' in wf
assert 'AVDB-unsigned-1.0.2-331-home-hero-crop.ipa' in (r/'scripts/package-lut331.py').read_text()
assert 'home-hero-hq-screenshots' in wf and 'test326HomeHeroHQScreenshots' in wf
assert 'detail-auth-327' in wf and 'test327DetailAuthErrorMessageVisible' in wf
assert 'home-hot-328' in wf
assert 'HomeHot328Tests' in wf
assert 'test328HomeHotChrome' in wf

doc = (r/'Build328-HomeHot.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '328' in doc
assert 'jointly' in doc.lower()
assert 'fullscreen' in doc.lower()
assert '失败页最小种子' in doc or '最小种子' in doc

home = (r/'AVDB/Views/Home/HomeView.swift').read_text()
policy = (r/'AVDB/Views/Home/HeroSwipePolicy.swift').read_text()
resolver = (r/'AVDB/Services/HeroCoverResolver.swift').read_text()
sdk = (r/'AVDB/Services/JavDBSDK.swift').read_text()
rankings = (r/'AVDB/Views/Rankings/RankingsView.swift').read_text()
bar = (r/'AVDB/Views/AVDBNativeTabBar.swift').read_text()
chrome = (r/'AVDB/Views/TabBarChrome.swift').read_text()
detail = (r/'AVDB/Views/Detail/MovieDetailView.swift').read_text()
app = (r/'AVDB/AVDBApp.swift').read_text()
client = (r/'AVDB/Networking/APIClient.swift').read_text()

# --- Hero feed = 看熱播日榜, cap 10, high_score + daily (not SDK default "all") ---
assert 'playbackRankings(filterBy: "high_score", period: "daily", page: 1)' in home
assert 'static let playbackHeroCap = 10' in home
assert '.prefix(Self.playbackHeroCap)' in home
assert 'filterBy: "all"' not in home.split('case .playback:')[1].split('case .latest')[0]
vm = home.split('final class HomeViewModel')[1].split('// MARK: - Build 325')[0]
changed_playback = vm.split('self.playback = movies')[1].split('case .latest')[0]
changed_recommended = vm.split('self.recommended = movies')[1].split('case .playback:')[0]
assert 'HeroCoverStore.shared.start(movies: movies, currentIndex: 0)' in changed_playback
assert 'HeroCoverStore.shared.start' not in changed_recommended
assert 'self.recommended = movies' in vm and 'self.playback = movies' in vm
assert 'playback.remove' not in home and 'movies.removeAll' not in home.split('private struct HomeHeroCarousel')[1].split('private struct HeroTouchStyle')[0]
hero = home.split('private struct HomeHeroCarousel: View {')[1].split('private struct HeroTouchStyle')[0]
assert 'HomeHeroCarousel(' in home
assert 'movies: vm.playback' in home
assert 'func nextABIndex()' in hero and 'currentCover.isAB && hasABPage' in hero
assert 'Task.sleep(nanoseconds: 5_000_000_000)' in hero
assert 'zoomed ? 1.05 : 1.0' in home and '.linear(duration: 5.6)' in home
assert 'accessibilityIdentifier("home-hero")' in hero
assert '高清封面加载失败，下拉刷新重试' in hero
assert 'p.settled && !p.hasQuick' in hero
assert 'hasDTOFloor' in hero

# Chip is 看熱播 · 日榜, not 往期, and opens the same filters as the hero.
assert 'HomePastChip' not in home
assert '看熱播 · 日榜' in home and 'HomeHotChip' in home
assert 'accessibilityIdentifier("home-hot-daily")' in home
assert 'initialPlaybackFilter: "high_score"' in home
assert 'initialPlaybackPeriod: .daily' in home
assert 'var initialPlaybackFilter: String = "high_score"' in rankings
assert 'var initialPlaybackPeriod: RankPeriod = .daily' in rankings
# Quick-action 看熱播 still exists.
assert 'quickAction("看熱播", "play.rectangle.fill", m) { goHot = true }' in home

# 往期推薦 is a normal rail below shortcuts, above 最新上架.
root = home.split('private func homeRoot')[1].split('// MARK: Hero')[0]
assert root.find('quickActionRow') < root.find('pastRecommendSection')
assert root.find('pastRecommendSection') < root.find('latestSection')
assert 'title: "往期推薦"' in home
assert 'titleIdentifier: "home-past-header"' in home
assert 'PastRecommendView()' in home
assert home.count('HomePosterGrid(upgradesVisibleHQ: true') == 4
assert home.count('upgradesVisibleHQ: true') == 5  # 4 home grids + PeriodMoviesView

# --- Blank hero fix: ungated floor, no #2A2019 visible empty, per-item deadline ---
page = home.split('private struct HomeHeroPage: View {')[1].split('private struct HomeHeroMoreButton')[0]
assert 'HomeTheme.heroLoadingFloor' in page
assert 'HomeTheme.fallbackBase' not in page
assert 'floorImage' in page
assert 'movie.coverURL' in page and 'movie.thumbURL' in page
assert '.blur(' not in page  # 329: hero main layer is never blurred
assert 'colorMultiply' not in page
assert 'HeroCoverPolicy.effectiveOverallBudget' in resolver
assert 'static let overallBudget: TimeInterval = 6' in resolver
assert 'fixture://hang' in resolver and 'fixture://hang' in (r/'AVDB/Services/ImageLoader.swift').read_text()
assert 'settled' in resolver and ('provisional settle' in resolver.lower() or '已定案' in resolver)

# Do not promote the DTO floor to a finalized A/B sharp (326 tier/race kept).
assert 'static let tierAWidth = 1000' in resolver
assert 'static let liveSREnabled = false' in resolver
assert 'VisibleHQPosterScheduler' not in resolver
assert 'isBannedAsSharpURL' in resolver

# --- Vertical swipe arbitrator ---
assert 'enum HeroSwipePolicy' in policy
assert 'axisLockDistance: CGFloat = 14' in policy
assert 'axisRatio: CGFloat = 1.5' in policy
assert 'verticalPageTranslation: CGFloat = 56' in policy
assert 'verticalFlickTranslation: CGFloat = 24' in policy
assert 'verticalFlickVelocity: CGFloat = 500' in policy
assert 'scrollOffset > 1 ? .scrollView : .hero' in policy
assert 'isVerticalPassthrough' in policy
assert 'consumedPageChange' in policy
assert 'shouldBeRequiredToFailBy' in policy
assert 'other.view is UIScrollView' in policy
assert 'shouldRecognizeSimultaneouslyWith' in policy
assert 'HeroSwipeOverlay' in hero
assert 'onPageVertical' in hero
assert 'slide: true, vertical: true' in hero
assert 'edge == .top || edge == .bottom' in hero
assert 'accessibilityIdentifier("home-hero-more")' in home
assert 'scrollTo("home-shortcuts"' in home
assert 'id("home-shortcuts")' in home
assert 'Text("更多")' in home
assert 'frame(width: 44, height: 44)' in home.split('private struct HomeHeroMoreButton')[1].split('private struct HomeAnchoredFill')[0]
assert 'HeroSwipePolicy.pageSpringResponse' in hero
assert 'pageSpringResponse: Double = 0.38' in policy
assert 'pageSpringDamping: Double = 0.88' in policy

# --- Light theme, detail-aligned ---
assert '.environment(\\.colorScheme, .dark)' not in home.split('struct HomeView: View {')[1].split('// MARK: Hero')[0]
assert 'preferredColorScheme(.dark)' not in home
assert 'Color(.systemBackground)' in root
assert 'HomeTheme.heroLoadingFloor' in home
assert 'static let primary = Color.primary' in home
assert 'liquidGlassCircle(interactive: true)' in home
assert 'Color(.systemGray5)' in home
assert 'HomeStatusBarStyle' in home
assert 'lightContent' in home
# Ambient must not paint #14100D under the rails.
assert 'heroHeight: m.heroHeight, scroll: scroll' in home
assert 'max(0, heroHeight - scroll.up) + scroll.pull' in home
assert 'Color(.systemBackground).opacity(0.94)' in home
# Search is 44 pt liquid glass + white glyph (Build 330; legible on hero and light page).
sb = home.split('private struct HomeSearchButton: View {')[1].split('private struct HomeTopScrim')[0]
assert 'width: 44, height: 44' in sb and 'Color.white' in sb and 'liquidGlassCircle' in sb
# TOP250 stays a dark island; tab bar not restyled beyond 0.66 fill for contrast.
assert 'HomeTheme.floor.opacity(0.94)' in home.split('private func top250Banner')[1].split('private func followingSection')[0]
assert 'HomeChevronCircle(onDark: true)' in home
assert 'case home, rankings, categories, actors, tangxin, one, me' in chrome
assert 'ForEach(AppTab.allCases)' in bar
assert 'selection == .home ? 0.32' not in bar
assert 'reduceTransparency ? 1 : 0.66' in bar

# --- 327 detail-auth and 326 HQ must stay intact ---
assert 'useToken: true' in sdk.split('public func movieDetail(_ id: String')[1].split('public func movieDetailFull')[0]
assert 'useToken: true' in sdk.split('public func movieDetailFull(_ id: String')[1].split('public func movieMagnets')[0]
assert 'markNeedsReauth()' in app
assert 'removeAllCachedResponses()' in client.split('public func setToken(_ token: String?)')[1].split('public var hasToken')[0]
assert 'sessionStatus = .needsReauth' in app.split('func markNeedsReauth()')[1].split('func restoreLogin()')[0]
assert 'setToken(nil)' not in app.split('func markNeedsReauth()')[1].split('func restoreLogin()')[0]
assert '去登录' in detail
assert 'static let decodeCap = 2048' in resolver
assert 'evictNonAdjacentBitmaps' in resolver

unit = (r/'UITests/DetailPosterQualityTests.swift').read_text()
assert 'final class HomeHot328Tests' in unit
assert 'test328ArbitratorAcceptanceTable' in unit
assert 'test328StuckSourceDeadlinePaintsFloorNotBrown' in unit
assert 'fixture://hang' in unit
assert 'fallbackBase' in unit or '#2A2019' in unit or '2A2019' in unit

ui = (r/'UITests/PosterNavigationTests.swift').read_text()
assert 'func test328HomeHotChrome()' in ui
idx = ui.find('func test328HomeHotChrome()')
nearby = ui[idx:idx+2500]
assert 'home-hot-daily' in nearby and 'home-hero-more' in nearby
assert 'home-past-recommend' in nearby
assert 'home-past-header' in nearby

print('PASS home-hot328 source contracts: playback high_score+daily cap 10, '
      'DTO floor + per-item deadline, 往期 rail, light tokens, vertical arbitrator, '
      '327 auth + 326 HQ intact, release 331')
