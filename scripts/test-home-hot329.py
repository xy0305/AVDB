#!/usr/bin/env python3
"""Build 329 home: unblurred hero floor (quality rules never gate the floor),
3×3 vertical poster grids, DTO thumb preheat, late A/B after the 6s settle,
換一組 only on 最新上架 / 近期磁鏈更新. Static source contracts on Linux;
XCTest unit + UI tests run on CI."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '329' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 329;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2
assert 'HeroSwipePolicy.swift' in pbx and 'HeroCoverResolver.swift' in pbx

wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 329' in wf and 'feat/home-hot-329' in wf
assert 'feat/home-hot-328' in wf and 'feat/detail-auth-327' in wf
assert 'python3 scripts/test-home-hot329.py' in wf
assert 'python3 scripts/test-home-hot328.py' in wf
assert 'python3 scripts/test-home-hero-hq326.py' in wf
assert 'python3 scripts/test-detail-auth327.py' in wf
assert 'scripts/package-lut329.py' in wf and 'AVDB-329-release' in wf
assert 'AVDB-unsigned-1.0.2-329-home-hot.ipa' in (r/'scripts/package-lut329.py').read_text()
assert 'home-hot-329' in wf
assert 'HomeHot329Tests' in wf
assert 'test329HomeHotChrome' in wf
assert 'test329DelayedCDNPaintsSharpFloorThenUpgrades' in wf
assert 'test329PreheatFollowingDTOThumbs' in wf
assert 'test329OfflineColdStartRestoresSharpFloor' in wf

doc = (r/'Build329-HomeHot.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '329' in doc
assert '地板' in doc or 'floor' in doc.lower()
assert '3' in doc and ('三列' in doc or '3-column' in doc or '3×3' in doc or '3x3' in doc)
assert 'unsigned' in doc.lower() or '未签名' in doc or '未簽名' in doc

home = (r/'AVDB/Views/Home/HomeView.swift').read_text()
policy = (r/'AVDB/Views/Home/HeroSwipePolicy.swift').read_text()
resolver = (r/'AVDB/Services/HeroCoverResolver.swift').read_text()
loader = (r/'AVDB/Services/ImageLoader.swift').read_text()
sdk = (r/'AVDB/Services/JavDBSDK.swift').read_text()
bar = (r/'AVDB/Views/AVDBNativeTabBar.swift').read_text()
chrome = (r/'AVDB/Views/TabBarChrome.swift').read_text()
detail = (r/'AVDB/Views/Detail/MovieDetailView.swift').read_text()
app = (r/'AVDB/AVDBApp.swift').read_text()
client = (r/'AVDB/Networking/APIClient.swift').read_text()
grid = (r/'AVDB/Views/Components/JAVDBUI.swift').read_text()

# --- 328 hero source / swipe / light theme / 往期 placement stay ---
assert 'playbackRankings(filterBy: "high_score", period: "daily", page: 1)' in home
assert 'static let playbackHeroCap = 10' in home
assert 'static let homeGridCap = 9' in home
assert 'HeroCoverStore.shared.start(movies: movies, currentIndex: 0)' in home
assert 'movies: vm.playback' in home
assert '看熱播 · 日榜' in home and 'HomeHotChip' in home
assert 'title: "往期推薦"' in home
root = home.split('private func homeRoot')[1].split('// MARK: Hero')[0]
assert root.find('quickActionRow') < root.find('pastRecommendSection')
assert root.find('pastRecommendSection') < root.find('latestSection')
assert 'Color(.systemBackground)' in root
assert 'enum HeroSwipePolicy' in policy
assert 'case home, rankings, categories, actors, tangxin, one, me' in chrome
assert 'ForEach(AppTab.allCases)' in bar

# --- Hero main layer never blurs ---
page = home.split('private struct HomeHeroPage: View {')[1].split('private struct HomeHeroMoreButton')[0]
assert '.blur(' not in page
assert 'colorMultiply' not in page
assert 'HomeTheme.heroLoadingFloor' in page
assert 'HomeTheme.fallbackBase' not in page
assert 'floorImage' in page
assert 'movie.coverURL' in page and 'movie.thumbURL' in page
assert '.easeOut(duration: HeroCoverPolicy.crossfadeDuration)' in page
assert 'static let crossfadeDuration: TimeInterval = 0.45' in resolver
assert 'static let liveSREnabled = false' in resolver
assert 'VisibleHQPosterScheduler' not in resolver

# --- 6s is a provisional settle; late A/B may still upgrade ---
assert 'static let overallBudget: TimeInterval = 6' in resolver
assert 'static let upgradeTimeout: TimeInterval = 20' in resolver
assert 'var settled: Bool = false' in resolver
assert '已定案（可升级）' in resolver
assert 'var finished: Bool' not in resolver
assert 'var retryable: Bool' not in resolver
assert 'Provisional settle, not a cancel' in resolver or 'not a cancel of in-flight' in resolver
assert 'p.settled && !p.hasQuick' in home
assert 'current → +1 → −1 → +2 → −2' in resolver or '+1 → −1 → +2 → −2' in resolver
assert 'adjacentMovies' in resolver
assert 'floorCache' in resolver
assert 'HeroCoverDisk.image(for:' in resolver
assert 'enum HeroCIDMap' in resolver
assert 'movieDetail(movie.id)' in resolver
assert 'fixture://delay/' in loader and 'fixture://hang' in loader
assert 'thumb147' in loader

# --- Rail floor: 147×200 paintable; 360 is preference only ---
assert 'enum RailCoverFloor' in loader
assert 'static let minWidth = 360' in loader
assert 'static func prefers(' in loader
assert 'enum RailPosterPlaceholder' in loader
assert 'case filmIcon' in loader and 'case retry' in loader and 'case loading' in loader
assert 'enum HomeRailThumbPreheat' in loader
assert 'startThumbPreheat' in home
# JavDBImage floor path must not discard via rejects.
javdb = loader.split('public struct JavDBImage: View {')[1].split('enum VisibleHQPosterPolicy')[0]
assert 'RailCoverFloor.rejects' not in javdb
assert 'RailCoverFloor.prefers' in javdb
assert '點按重試' in javdb
assert 'film.stack' in javdb

# --- 3×3 grids, no horizontal cover rail, 換一組 only on two sections ---
assert 'private struct HomePosterGrid' in home
assert 'struct HomePosterRail' not in home
assert home.count('HomePosterGrid(upgradesVisibleHQ: true') == 4
assert home.count('upgradesVisibleHQ: true') == 5  # 4 home grids + PeriodMoviesView
assert 'MoviePosterCard(movie: movie, upgradesVisibleHQ: upgradesVisibleHQ)' in home
assert 'struct MoviePosterCard' in grid
assert 'movies.prefix(HomeViewModel.homeGridCap)' in home
assert 'private static let columns = 3' in home
latest = home.split('private func latestSection')[1].split('private func magnetSection')[0]
magnet = home.split('private func magnetSection')[1].split('homeListStatus')[0]
past = home.split('private func pastRecommendSection')[1].split('private func latestSection')[0]
follow = home.split('private func followingSection')[1].split('// Small list-only snapshot')[0]
assert 'shuffle:' in latest and '換一組' in home
assert 'shuffle:' in magnet
assert 'shuffle:' not in past
assert 'shuffle:' not in follow
assert 'home-following-more' in follow
assert 'FollowingTagDestination' in home or 'FollowingTagsView' in home
assert 'PastRecommendView()' in home
assert 'CatalogListView(title: "最新上架"' in home
assert 'CatalogListView(title: "近期磁鏈更新"' in home

# --- 327 auth + 326 HQ intact ---
assert 'useToken: true' in sdk.split('public func movieDetail(_ id: String')[1].split('public func movieDetailFull')[0]
assert 'markNeedsReauth()' in app
assert 'setToken(nil)' not in app.split('func markNeedsReauth()')[1].split('func restoreLogin()')[0]
assert '去登录' in detail
assert 'static let decodeCap = 2048' in resolver
assert 'static let wifiConcurrency = 5' in loader and 'static let cellularConcurrency = 2' in loader

unit = (r/'UITests/DetailPosterQualityTests.swift').read_text()
assert 'final class HomeHot329Tests' in unit
assert 'test329DelayedCDNPaintsSharpFloorThenUpgrades' in unit
assert 'test329PreheatFollowingDTOThumbs' in unit
assert 'test329OfflineColdStartRestoresSharpFloor' in unit
assert 'test329RailFloorAccepts147ThumbAnd360IsPreferenceOnly' in unit
assert 'fixture://delay/15' in unit
assert 'final class HomeHot328Tests' in unit

ui = (r/'UITests/PosterNavigationTests.swift').read_text()
assert 'func test329HomeHotChrome()' in ui
idx = ui.find('func test329HomeHotChrome()')
nearby = ui[idx:idx+3500]
assert 'home-hero-more' in nearby and 'home-past-header' in nearby
assert 'poster-past-9' in nearby and 'poster-past-10' in nearby
assert 'home-shuffle-最新上架' in nearby and 'home-shuffle-近期磁鏈更新' in nearby
assert 'home-following-more' in nearby and 'poster-follow-1' in nearby
assert '--home329-fixture' in nearby

print('PASS home-hot329 source contracts: unblurred floor, 3x3 grids, 147 floor, '
      'late A/B after settle, preheat, 換一組 only on two sections, release 329')
