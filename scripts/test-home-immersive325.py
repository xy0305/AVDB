#!/usr/bin/env python3
"""Build 325 首页沉浸式改版: full-bleed hero carousel, warm ambient background, glass quick
actions, 2:3 poster rails, floating glass search button, warm glass tab bar.
Static source contracts on Linux (the Swift compile and simulator screenshots run on CI)."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '325' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 325;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2

# Release wiring.
wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 325' in wf and 'feat/home-immersive-325' in wf
assert 'python3 scripts/test-home-immersive325.py' in wf and 'test-home-hero324.py' not in wf
assert 'scripts/package-lut325.py' in wf and 'AVDB-325-release' in wf and 'AVDB-324-' not in wf
assert 'AVDB-325-home-screenshots' in wf and 'test325HomeImmersiveScreenshots' in wf
assert not (r/'scripts/test-home-hero324.py').exists() and not (r/'scripts/package-lut324.py').exists()
pkg = (r/'scripts/package-lut325.py').read_text()
assert "=='325'" in pkg and "MinimumOSVersion']=='17.0'" in pkg and 'AVDB-unsigned-1.0.2-325-home-immersive.ipa' in pkg
doc = (r/'Build325-HomeImmersive.md').read_text()
assert 'Muse' in doc and '325' in doc

home = (r/'AVDB/Views/Home/HomeView.swift').read_text()
view = home.split('struct HomeView: View {')[1].split('// Small list-only snapshot')[0]
hero = home.split('private struct HomeHeroCarousel: View {')[1].split('private struct HeroTouchStyle')[0]
page = home.split('private struct HomeHeroPage: View {')[1].split('private struct HomeAnchoredFill')[0]
metrics = home.split('struct HomeMetrics {')[1].split('extension View {')[0]

# --- 1. Hero: full-bleed, under the status bar, replaces the 佳片推薦 header + padded 3:4 card.
for gone in ['RecommendCarousel', 'RecommendHeroCard', 'cardWidth * 4 / 3', 'Text("佳片推薦")', 'private var searchBar']:
    assert gone not in home, gone
assert '.ignoresSafeArea(.container, edges: .top)' in view
assert 'HomeHeroCarousel(' in view
assert 'var heroHeight: CGFloat { isPadWidth ? 600 : min(max(width * 1.15, 430), 560) }' in metrics
assert 'var isPadWidth: Bool { width >= 768 }' in metrics
assert 'var padding: CGFloat { isPadWidth ? 24 : (width < 380 ? 16 : 20) }' in metrics
assert '.frame(width: width, height: height)' in hero and 'cornerRadius' not in hero.split('private var imageLayer')[1].split('private var scrims')[0]
assert 'var anchorY: CGFloat = 0.22' in home
assert 'pixelWidth < 500' in home and 'cornerRadius: 20' in page and '.blur(radius: 30, opaque: true)' in page
assert '.aspectRatio(contentMode: .fit)' in page
assert 'ListCoverPolicy.sources(movie: movie)' in home and 'loadPoster(source' in home
assert 'VisibleHQPosterPolicy.upgradeURL(movie: movie)' in home
assert 'for offset in 0..<min(3, movies.count)' in hero  # current + prefetch next 2
# Scrims (exact stops) + top scrim.
for stop in ['.init(color: .black.opacity(0), location: 0.35)', '.init(color: .black.opacity(0.18), location: 0.62)',
             '.init(color: .black.opacity(0.45), location: 0.82)', '.init(color: .black.opacity(0.66), location: 1.0)']:
    assert stop in hero, stop
assert '.black.opacity(0.28)' in hero and '.frame(height: 110)' in hero
# Text block: 23 bold 1 line, date 13 medium 72%, synopsis 13 regular 85% max 2 lines, spacing 6.
text = hero.split('private var textBlock: some View {')[1].split('private var swipe')[0]
assert 'VStack(alignment: .leading, spacing: 6)' in text
assert '.font(.system(size: 23, weight: .bold))' in text and '.lineLimit(1)' in text and '.shadow(' in text
assert '.font(.system(size: 13, weight: .medium))' in text and 'opacity(0.72)' in text
assert '.font(.system(size: 13, weight: .regular))' in text and 'opacity(0.85)' in text and '.lineLimit(2)' in text
assert '.padding(.bottom, showsDots ? 32 : 16)' in text
# Synopsis lazily from movieDetail, cached, current + next.
assert 'JavDBSDK.shared.movieDetail(movie.id)' in home and 'final class HomeHeroSynopsisStore' in home
assert 'for offset in 0..<min(2, movies.count)' in hero
# Dots: independent layer (not inside the text VStack), 6x6 45%, 18x6 selected, spacing 5, window 9.
assert 'HomeHeroDots(' not in text and 'HomeHeroDots(count:' in hero
dots = home.split('private struct HomeHeroDots: View {')[1].split('// MARK: Rails')[0]
assert 'HStack(spacing: 5)' in dots and 'width: i == index ? 18 : 6, height: 6' in dots and 'opacity(i == index ? 1 : 0.45)' in dots
assert 'min(count, 9)' in dots and '.spring(' in dots
assert '.padding(.bottom, 16)' in hero and 'private var showsDots: Bool { movies.count > 1 }' in hero
# Behaviour: 5 s autoplay crossfade 0.6, Ken Burns 1.05 / 5.6 s, pauses, spring paging, pull/parallax/fade.
assert 'Task.sleep(nanoseconds: 5_000_000_000)' in hero and '.easeInOut(duration: 0.6)' in hero
assert 'zoomed ? 1.05 : 1.0' in page and '.linear(duration: 5.6)' in page
for cond in ['!touching', '!dragging', 'scenePhase == .active', '!reduceMotion', '!voiceOver', 'movies.count > 1']:
    assert cond in hero, cond
assert '.spring(response: 0.38, dampingFraction: 0.88)' in hero
assert 'min(scroll.pull, 120) / height' in hero and 'scroll.up * 0.45' in hero and 'min(scroll.up, 120) / 120' in hero
assert 'onOpen(movie)' in hero and 'MovieDetailView(movie: movie)' in view
# 往期 kept reachable as a glass chip.
assert 'PastRecommendView()' in view and 'HomePastChip(' in hero
# Accessibility: one VO element, dots hidden.
assert '.accessibilityElement(children: .ignore)' in hero and '"\\(movie.displayNumber) \\(movie.displayTitle), \\(date)"' in hero
assert '.accessibilityHidden(true)' in hero.split('HomeHeroDots(count:')[1].split('HomePastChip(')[0]

# --- 2. Ambient warm dark background.
assert 'HomeAmbientBackground(ambient: ambient)' in view and 'LiquidGlassBackground()' not in view
amb = home.split('enum HomeAmbientColor {')[1].split('private struct HomeSearchButton')[0]
assert 'let side = 32' in amb and 'min(max(Double(sat), 0.25), 0.45)' in amb and 'min(max(Double(bri), 0.16), 0.22)' in amb
assert 'location: 0.45' in amb and 'location: 0.75' in amb and 'brightness: b * 0.55' in home
assert '.easeInOut(duration: 0.8)' in amb and 'accessibilityReduceTransparency' in amb
assert 'green: 16.0 / 255.0, blue: 13.0 / 255.0)     // #14100D' in home
assert 'static let fallback = HomeHSB(' in home and '#2A2019' in home
assert 'static let accent = Color(red: 1.0, green: 138.0 / 255.0, blue: 61.0 / 255.0)' in home
assert '.environment(\\.colorScheme, .dark)' in view and 'preferredColorScheme(.dark)' in view
# No rainbow colours left on home.
for rainbow in ['Color.orange', 'Color.red', 'Color.purple', 'Color.pink', 'Color.green', 'Color.blue',
                'Color.teal', 'Color.indigo', 'Color.yellow', '.foregroundStyle(.blue)', '.yellow.gradient']:
    assert rainbow not in view, rainbow

# --- 3. Glass quick actions with labels (same 12 destinations).
assert 'shortcutRow' not in home
qa = view.split('private func quickActionRow')[1].split('// MARK: Rails')[0]
assert qa.count('quickAction("') == 12
for label in ['稍後再看', '新作提醒', '三連挑戰', '每日抽簽', '看熱播', 'AV資訊', '看短評', '找磁鏈', '系列', '片商', '導演', 'TOP250']:
    assert f'quickAction("{label}"' in qa, label
assert '.homeGlass(in: Circle())' in qa and '.font(.system(size: 22, weight: .semibold))' in qa
assert '.font(.system(size: 11, weight: .medium))' in qa and 'VStack(spacing: 4)' in qa and '.accessibilityLabel(title)' in qa
assert 'HomePressStyle(scale: 0.92)' in qa and 'GlassHaptic.tap()' in qa
assert 'var quickItem: CGFloat { width <= 375 ? 56 : 60 }' in metrics and 'var quickCircle: CGFloat { width <= 375 ? 48 : 52 }' in metrics
glass = home.split('func homeGlass<S: InsettableShape>(in shape: S)')[1].split('struct HomePressStyle')[0]
assert '.ultraThinMaterial' in glass and 'HomeTheme.glassFill' in glass and 'accent.opacity(0.10)' in glass
assert 'Color.white.opacity(0.16), lineWidth: 0.5' in glass
assert '.padding(.top, 18)' in view

# --- 4. Rails 2:3, headers with chevron circle, shimmer / retry, spacing 26 / 22.
assert 'MoviePosterGrid(' not in view
assert view.count('HomePosterRail(upgradesVisibleHQ: true') == 3
assert 'min(max(usable / 2.75, 108), 132)' in metrics and 'min(max(usable / 4.6, 132), 156)' in metrics
assert 'var cardHeight: CGFloat { (cardWidth * 1.5).rounded() }' in metrics
rail = home.split('private struct HomePosterRail: View {')[1].split('enum HomePlaceholder')[0]
assert 'LazyHStack(alignment: .top, spacing: 12)' in rail and '.scrollTargetBehavior(.viewAligned)' in rail
assert '.contentMargins(.horizontal, metrics.padding, for: .scrollContent)' in rail
assert 'cornerRadius: 12, style: .continuous' in rail and 'Color.white.opacity(0.08), lineWidth: 0.5' in rail
assert '.shadow(color: .black.opacity(0.25), radius: 10, y: 4)' in rail and 'HomePressStyle(scale: 0.97, spring: true)' in rail
assert 'height: 34' in rail and 'spacing: 6' in rail and 'size: 12, weight: .medium' in rail and 'size: 11' in rail
assert 'HomeHQPosterPrefetch.scheduleAhead(movies: movies, around: idx)' in rail
assert 'accessibilityIdentifier("poster-\\(movie.id)")' in rail
header = home.split('private struct HomeRailHeader: View {')[1].split('private struct HomePosterRail')[0]
assert '.font(.system(size: 17, weight: .bold))' in header and '換一組' in header and 'HomeChevronCircle()' in header
assert 'width: 26, height: 26' in home and 'Rectangle().inset(by: -9)' in header
assert '.padding(.top, 22)' in view and view.count('.padding(.top, 26)') == 3
ph = home.split('private struct HomePlaceholderView: View {')[1].split('private struct HomeShimmer')[0]
assert 'film.stack' in ph and 'retry()' in ph and 'HomeShimmer()' in ph
assert 'goLatest = true' in view and 'goMagnets = true' in view and 'shuffleLatest' in view and 'shuffleMagnets' in view
assert 'TOP250' in view.split('private func top250Banner')[1]

# --- 5. Search: no top bar on home, floating 58 pt glass button → SearchView.
assert '搜索番號 / 關鍵詞' not in home
sb = home.split('private struct HomeSearchButton: View {')[1].split('private struct HomeTopScrim')[0]
assert 'width: 58, height: 58' in sb and 'magnifyingglass' in sb and '.font(.system(size: 21, weight: .semibold))' in sb
assert '.shadow(color: .black.opacity(0.35), radius: 16, y: 6)' in sb and '.homeGlass(in: Circle())' in sb
assert 'HomeSearchButton(scroll: scroll)' in view and 'goSearch = true' in view and 'SearchView()' in view
search = (r/'AVDB/Views/Search/SearchView.swift').read_text()
assert 'barcode.viewfinder' in search and 'isSearchFocused = true' in search

# --- 6. Tab bar: 7 tabs kept, warm glass, accent selection.
bar = (r/'AVDB/Views/AVDBNativeTabBar.swift').read_text()
chrome = (r/'AVDB/Views/TabBarChrome.swift').read_text()
assert 'case home, rankings, categories, actors, tangxin, one, me' in chrome
assert 'ForEach(AppTab.allCases)' in bar and 'accessibilityIdentifier("app.tab.\\(tab.rawValue)")' in bar
assert 'green: 138.0 / 255.0, blue: 61.0 / 255.0' in bar and 'Color.white.opacity(0.55)' in bar and 'Color.white.opacity(0.12)' in bar
assert '.ultraThinMaterial' in bar and 'strokeBorder(Color.white.opacity(0.16), lineWidth:0.5)' in bar
assert '.environment(\\.selectedAppTab, selection)' in chrome and 'var selectedAppTab: AppTab?' in chrome

# --- 7. iPad: content capped at 1100.
assert '.frame(maxWidth: m.contentWidth, alignment: .leading)' in view and 'min(width, AdaptiveLayout.contentMaxWidth)' in metrics

# --- Screenshot fixture + UI test.
assert '--home325-fixture' in home
ui = (r/'UITests/PosterNavigationTests.swift').read_text()
assert 'func test325HomeImmersiveScreenshots()' in ui and '325-home-immersive-top' in ui

print('PASS home-immersive325 source contracts: full-bleed hero + scrims + dots layer, warm ambient, '
      'glass quick actions, 2:3 rails, floating glass search, warm glass 7-tab bar, release 325')
