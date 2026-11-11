#!/usr/bin/env python3
"""Build 331 home hero front crop: no hero layer ever draws an uncropped DVD
jacket; two-level floor (front-cropped cover_url / thumb → official
DetailPosterResolver winner); bitmap lifecycle decided at result arrival with
disk-only restores; field-level merge by movie id; per-item enrich → resolver
pipeline; bidirectional winner sharing by movie id. Static source contracts
on Linux; XCTest unit tests (HomeHero331Tests) run on CI."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '332' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 332;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2

wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 332' in wf and 'feat/home-hero-crop-331' in wf and 'feat/home-chrome-330' in wf
assert 'feat/home-hero-color-332' in wf
assert wf.count('python3 scripts/test-home-hero331.py') == 2  # zzt-ranking job + release regressions
assert 'scripts/package-lut332.py' in wf and 'AVDB-332-release' in wf and 'AVDB-331-release' not in wf
pkg = (r/'scripts/package-lut332.py').read_text()
assert "=='332'" in pkg and 'AVDB-unsigned-1.0.2-332-home-hero-color.ipa' in pkg and "MinimumOSVersion']=='17.0'" in pkg
job = wf.split('  home-hero-331:')[1].split('  home-hero-332:')[0]
assert '-only-testing:DetailPosterQualityTests/HomeHero331Tests' in job
assert 'test330EnrichMergedDetailCoverIsMiddleStep' in job
assert 'AVDB-332-home-hero-tests' in job
assert 'home-chrome-330:' in wf and 'home-hot-329:' in wf and 'home-hot-328:' in wf

doc = (r/'Build331-HomeHeroCrop.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '331' in doc
assert 'loadPoster' in doc and 'HeroCoverDisk' in doc and 'unsigned' in doc.lower()

resolver = (r/'AVDB/Services/HeroCoverResolver.swift').read_text()
detail = (r/'AVDB/Services/DetailPosterResolver.swift').read_text()
home = (r/'AVDB/Views/Home/HomeView.swift').read_text()
loader = (r/'AVDB/Services/ImageLoader.swift').read_text()
movie = (r/'AVDB/Models/Movie.swift').read_text()
sdk = (r/'AVDB/Services/JavDBSDK.swift').read_text()
store = resolver.split('final class HeroCoverStore')[1].split('actor HeroCoverPrefetchGate')[0]
page = home.split('private struct HomeHeroPage: View {')[1].split('private struct HomeHeroMoreButton')[0]
fill = home.split('struct HomeAnchoredFill: View {')[1].split('/// Independent dots layer')[0]

# --- 1. Invariant (Build 332 mechanism): hero paints the original image;
# the visible window is the front region only. Purpose unchanged: no layer may
# show the back-cover collage. loadPoster remains for rails / detail, not the hero.
assert 'public func loadPoster(_ source: String, maxPixelSize: Int, timeout: TimeInterval = 20)' in loader
assert 'FrontPosterPolicy.cropRect' in loader
assert 'enum HeroFrontWindow' in resolver
assert 'ImageLoader.shared.load(' in store
assert 'ImageLoader.shared.loadPoster(' not in store, 'hero store paints the original decode, not a loadPoster crop'
assert 'ImageLoader.shared.load(' in page and 'ImageLoader.shared.loadPoster(' not in page
assert 'HeroFrontWindow.placement(' in fill
assert 'RailCoverFloor.prefers' not in page
assert 'enrichImage' not in resolver and 'enrichImage' not in home and 'loadEnrichCover' not in resolver
# Ambient = the currently displayed (front) region, no separate jacket fetch.
assert 'var displayedImage: UIImage? { sharpImage ?? blurImage }' in resolver
assert 'HomeAmbientColor.base(from: candidate.image, source: candidate.source)' in store
assert 'currently displayed' in resolver
assert 'hsb.h' in home.split('private var ambientKey: String {')[1].split('private func publishAmbient')[0]
# Safety net: residual non-jacket landscape right-anchored (HeroFillAnchor).
assert 'enum HeroFillAnchor' in home and 'iw > ih ? (w - dw) : (w - dw) / 2' in home
assert 'HeroFillAnchor.x(' in resolver
# No AICover on the hero.
assert 'AICoverEnhanceModel' not in resolver and 'AICoverEnhanceModel' not in home
assert 'art.rawImage ?? art.image' in resolver

# --- 2. Two-level floor ---
assert 'var floorSource: String?' in resolver and 'var floorPixelWidth: Int = 0' in resolver
assert 'private func floorSources(_ movie: Movie)' in store
fs = store.split('private func floorSources(_ movie: Movie)')[1].split('private static func isCoverSource')[0]
assert fs.find('movie.coverURL') < fs.find('movie.thumbURL'), 'cover_url preferred, thumb fallback'
assert '/small_covers/' in fs
assert 'let parallel = isInWindow(id)' in store, 'parallel race only for current ±1'
assert 'withTaskGroup(of: (String, UIImage?).self)' in store
assert 'floorRank' in store and 'height >= width ? 1_000_000 : 0' in store
assert 'startFloorLoad(merged)' in store, 'floor re-evaluates when enrich merges a better cover'
assert page.count('HomeAnchoredFill(') == 2, 'exactly two hero layers (floor, official winner)'
assert '.easeOut(duration: HeroCoverPolicy.crossfadeDuration)' in page
assert 'static let crossfadeDuration: TimeInterval = 0.45' in resolver
assert 'authoritative: true' in store, 'resolver winner overrides the floor on arrival'

# --- 3. Bitmap lifecycle ---
assert 'var hasSharpBitmap: Bool { sharpImage != nil || sharpOnDisk }' in resolver
assert 'var isAB: Bool { phase == .finalized && tier.isAB && hasSharpBitmap }' in resolver
assert 'var isSharp: Bool { phase == .finalized && winnerURL != nil && hasSharpBitmap }' in resolver
apply = store.split('private func applySharp(')[1].split('private func markSettled')[0]
assert 'let keep = isInWindow(id)' in apply, 'keep/evict decided at result-arrival time'
assert 'keepBitmaps' not in store and 'isAdjacent' not in store
assert 'let retrievable = bitmapPresent ||' in apply and 'if retrievable, !authoritative' in apply
assert 'guard keep || onDisk else { return }' in apply
assert 'HeroCoverDisk.storeWinner(' in apply
assert 'static func key(winnerURL: String, number: String?)' in resolver and 'hero-winner-331#' in resolver
restore = store.split('private func restoreBitmaps(for movie: Movie)')[1].split('private static let diskStandIn')[0]
assert 'HeroCoverDisk.image(winnerURL: winnerURL, number: number)' in restore
assert 'Task.detached' in restore, 'disk reads off the main actor'
assert 'resolveShared' not in restore and 'ImageLoader' not in restore and 'enqueueResolver(for: movie, force: true)' in restore
assert 'hero-hq-326#' in resolver and 'evictNonAdjacentBitmaps' in store

# --- 4. Field-level merge by movie id ---
assert 'func preservingHeroEnrichment(from enriched: Movie) -> Movie' in movie
assert 'if let incoming { movies = mergeRanking(incoming) }' in store
assert 'self.movies = movies' not in store
assert 'dto.preservingHeroEnrichment(from: merged)' in store

# --- 5. Per-item pipeline ---
assert 'static let enrichTimeout: TimeInterval = 8' in resolver
assert 'static let resolverConcurrency = 2' in resolver
assert 'private func schedulePipelines()' in store and 'enrichHeroCIDs' not in store and 'enrichFinished' not in store
assert 'current → +1 → −1 → +2 → −2' in store
assert 'self.enqueueResolver(for: latest, force: true)' in store, 'resolver starts as soon as that item enriched'
assert 'enrichRetried' in store and 'case running, merged, failed, skipped' in store
assert 'setPriority' in resolver and 'priority[waiters[lhs].id]' in resolver
assert 'movieDetail(movie.id, catalogue: false)' in store
assert 'HeroCIDMap.cid(from: native) != nil' in store and 'catalogueEnriched(native)' in store
assert 'catalogue: Bool = true' in sdk and 'public func catalogueEnriched(_ movie: Movie)' in sdk
assert 'not a cancel of in-flight' in resolver or 'Provisional settle, not a cancel' in resolver

# --- 6. Bidirectional winner sharing by movie id ---
assert 'enum DetailPosterWinners' in detail and 'detailPosterWinnerResolved' in detail
assert 'DetailPosterWinners.store(art, movieID: movie.id, account: account)' in detail
il = detail.split('static func initialLayout(')[1].split('static func resolveShared')[0]
assert 'DetailPosterWinners.winner(movieID: movie.id, account: account)' in il
rs = detail.split('static func resolveShared(')[1].split('static func resolve(')[0]
assert 'DetailPosterWinners.winner(movieID: id, account: account)' in rs
assert 'DetailPosterWinners.invalidate()' in detail
assert 'forName: .detailPosterWinnerResolved' in store and 'noteDetailWinner' in store
assert 'DetailPosterWinners.winner(movieID: id, account: APIClient.shared.token)' in restore

# Out of scope stays untouched.
assert 'static let liveSREnabled = false' in resolver
assert 'width: 44, height: 44' in home.split('private struct HomeSearchButton: View {')[1].split('private struct HomeTopScrim')[0]

# --- 7. Tests ---
unit = (r/'UITests/DetailPosterQualityTests.swift').read_text()
assert 'final class HomeHero331Tests' in unit
for name in ['test331ColdStartFirstFrameIsFrontPortrait', 'test331SwipeToFourthAndBackKeepsSharpWinner',
             'test331OfflineColdStartShowsDetailWinner', 'test331LandscapeFixtureNeverShowsUncroppedLayer',
             'test331ResolverNeverCompletesStaysOnSharpFrontFloor', 'test331EvictedWinnerRestoresWithZeroNetwork',
             'test331SetCurrentIndexKeepsMergedFields', 'test331DetailWinnerSharedByMovieID']:
    assert f'func {name}()' in unit, name
    assert name in wf, name
assert 'render(840, 568' in unit and 'render(166, 236' in unit
assert 'testTransportCalls' in unit and 'resolverRunCount' in unit
mid = unit.split('func test330EnrichMergedDetailCoverIsMiddleStep()')[1].split('func test330BackdropPLIsNotPrimaryOverOfficialPortrait')[0]
assert 'floorPixelWidth' in mid and 'enrichImage' not in mid
assert 'final class HomeChrome330Tests' in unit and 'final class HomeHot329Tests' in unit

print('PASS home-hero331 source contracts: original-bitmap hero + display-time front window, two-level floor, '
      'arrival-time keep/evict + disk-only restore, field-level merge, per-item pipeline cap 2 / 8s, '
      'by-id winner sharing, release 332')
