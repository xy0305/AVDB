#!/usr/bin/env python3
"""Build 332 home hero color: the hero main layer paints the loader's decoded
original bitmap (zero pixel reprocessing); landscape jackets are shown only
through a display-time window equal to FrontPosterPolicy.cropRect; lower
content overlaps the hero by 32 pt; loadPoster / resolver crops are a tightly
packed sRGB 32 bpp translate-redraw; HeroCoverDisk JPEG keeps the ICC.
Static source contracts on Linux; XCTest unit tests (HomeHero332Tests) run on CI."""
from pathlib import Path
import plistlib

r = Path(__file__).resolve().parents[1]
plist = plistlib.loads((r/'AVDB/Resources/Info.plist').read_bytes())
pbx = (r/'AVDB.xcodeproj/project.pbxproj').read_text()
assert plist['CFBundleVersion'] == '338' and plist['CFBundleShortVersionString'] == '1.0.2'
assert pbx.count('CURRENT_PROJECT_VERSION = 338;') == 2 and pbx.count('MARKETING_VERSION = 1.0.2;') == 2

wf = (r/'.github/workflows/home-hq298.yml').read_text()
assert 'Home HQ posters App 338' in wf and 'feat/home-hero-color-332' in wf
assert 'feat/home-hero-crop-331' in wf and 'feat/home-chrome-330' in wf
assert wf.count('python3 scripts/test-home-hero332.py') == 2  # zzt-ranking job + release regressions
assert 'python3 scripts/test-home-hero331.py' in wf
assert 'scripts/package-lut338.py' in wf and 'AVDB-338-release' in wf and 'AVDB-331-release' not in wf
pkg = (r/'scripts/package-lut338.py').read_text()
assert "=='338'" in pkg and 'AVDB-unsigned-1.0.2-338-logout-access.ipa' in pkg and "MinimumOSVersion']=='17.0'" in pkg
job = wf.split('  home-hero-332:')[1]
assert '-only-testing:DetailPosterQualityTests/HomeHero332Tests' in job
assert 'AVDB-338-home-hero-tests' in job or 'AVDB-338-home-hero-color-tests' in job
assert '  home-hero-331:' in wf and 'home-chrome-330:' in wf and 'home-hot-329:' in wf

doc = (r/'Build332-HomeHeroColor.md').read_text()
assert 'Muse' in doc and 'Kai' in doc and '332' in doc
assert 'original' in doc.lower() and 'overlap' in doc.lower()
assert 'unsigned' in doc.lower()
# Credit the user's request.
assert '原图' in doc or 'original image' in doc.lower() or 'use the original' in doc.lower()

resolver = (r/'AVDB/Services/HeroCoverResolver.swift').read_text()
detail = (r/'AVDB/Services/DetailPosterResolver.swift').read_text()
home = (r/'AVDB/Views/Home/HomeView.swift').read_text()
loader = (r/'AVDB/Services/ImageLoader.swift').read_text()
store = resolver.split('final class HeroCoverStore')[1].split('actor HeroCoverPrefetchGate')[0]
page = home.split('private struct HomeHeroPage: View {')[1].split('private struct HomeHeroMoreButton')[0]
fill = home.split('struct HomeAnchoredFill: View {')[1].split('/// Independent dots layer')[0]
hero = home.split('private struct HomeHeroCarousel: View {')[1].split('private struct HeroTouchStyle')[0]

# --- 1. Hero paints the original bitmap; no cropped-bitmap source, no color filters ---
assert 'public enum PosterColorCrop' in loader
assert 'ctx.translateBy(x: -x, y: -y)' in loader
assert 'cg.cropping(to:' not in loader
assert 'ImageLoader.shared.load(' in store
assert 'ImageLoader.shared.loadPoster(' not in store, 'hero store must not crop via loadPoster'
assert 'ImageLoader.shared.load(' in page and 'ImageLoader.shared.loadPoster(' not in page
assert 'cropping(to:' not in page and 'cropping(to:' not in fill
assert 'colorMultiply' not in page and 'colorMultiply' not in fill
assert '.blur(' not in page and 'brightness(' not in page
assert '.interpolation(.high)' in fill
assert 'enum HeroFrontWindow' in resolver
assert 'HeroFrontWindow.placement(' in fill
assert 'FrontPosterPolicy.cropRect' in resolver.split('enum HeroFrontWindow')[1].split('enum HeroCoverPhase')[0]
# Two-level floor stays.
assert page.count('HomeAnchoredFill(') == 2
assert '.easeOut(duration: HeroCoverPolicy.crossfadeDuration)' in page
assert 'static let crossfadeDuration: TimeInterval = 0.45' in resolver
assert 'cover_url preferred' in resolver or 'cover_url' in store

# --- 2. Overlap 32 pt; bottom UI insets grow; overlap is not in the gesture hit area ---
assert 'static let heroContentOverlap: CGFloat = 32' in home
assert '.padding(.top, -HomeMetrics.heroContentOverlap)' in home
assert '46 + HomeMetrics.heroContentOverlap' in hero  # dots (Build 333: raised above the fade band)
assert '(showsDots ? 66 : 50) + HomeMetrics.heroContentOverlap' in hero  # title / date (Build 333)
assert '38 + HomeMetrics.heroContentOverlap' in hero  # 更多 (Build 333)
assert 'height - HomeMetrics.heroContentOverlap' in hero  # gesture hit area
# 看熱播 stays top-left (safe-top inset, not a bottom inset).
assert 'metrics.safeTop + 13' in hero

# --- 3. loadPoster / resolver pixel-crop is the sRGB 32 bpp translate-redraw ---
assert 'PosterColorCrop.cropIfNeeded' in loader
assert 'front-v2#' in loader
assert 'PosterColorCrop.crop(' in detail
assert 'cg.cropping(to:' not in detail
assert 'PosterColorCrop.crop(' in resolver  # HeroCoverRace.loadSharp
# JPEG ICC preserved on HeroCoverDisk / HQPosterDiskCache.
assert 'enum PosterJPEGColor' in loader
assert 'PosterJPEGColor.data(' in loader and 'PosterJPEGColor.image(from:' in loader
assert 'kCGImageDestinationLossyCompressionQuality' in loader

# --- 4. Locked 331 items stay ---
assert 'var hasSharpBitmap: Bool { sharpImage != nil || sharpOnDisk }' in resolver
assert 'HeroCoverDisk.storeWinner(' in store
assert 'static func key(winnerURL: String, number: String?)' in resolver
assert 'func preservingHeroEnrichment(from enriched: Movie) -> Movie' in (r/'AVDB/Models/Movie.swift').read_text()
assert 'static let enrichTimeout: TimeInterval = 8' in resolver
assert 'static let resolverConcurrency = 2' in resolver
assert 'current → +1 → −1 → +2 → −2' in store
assert 'enum DetailPosterWinners' in detail
assert 'art.image' in resolver.split('static func primaryImage(from art: DetailPosterArtwork) -> UIImage {')[1].split('}')[0], 'Build 333: hero sharp layer must be the detail display image (art.image)'
assert 'static let liveSREnabled = false' in resolver
assert 'width: 44, height: 44' in home.split('private struct HomeSearchButton: View {')[1].split('private struct HomeTopScrim')[0]
assert 'liquidGlassCircle(interactive: true)' in home
assert 'private static let columns = 3' in home
assert 'Color(.systemBackground)' in home.split('private func homeRoot')[1].split('// MARK: Hero')[0]

# --- 5. Tests ---
unit = (r/'UITests/DetailPosterQualityTests.swift').read_text()
assert 'final class HomeHero332Tests' in unit
for name in ['test332FloorIsOriginalBitmapAndWindowIsFront',
             'test332SnosWinnerRenderDeltaEAgainstReferenceImage',
             'test332VisibleWindowHidesBackCoverOnThreeFixtures',
             'test332FloorToWinnerCrossfadeKeepsColorTemperature',
             'test332OverlapKeepsBottomUIAndFacesVisible',
             'test332LoadPosterCropIsPackedSRGBAndDeltaEUnder2',
             'test332HeroCoverDiskJPEGPreservesSRGBProfile']:
    assert f'func {name}(' in unit, name
    assert name in wf, name
assert 'final class HomeHero331Tests' in unit
assert 'final class HomeChrome330Tests' in unit

print('PASS home-hero332 source contracts: original-bitmap hero + display-time front window, '
      '32 pt overlap, sRGB 32 bpp translate-redraw crop, ICC-preserving JPEG, release 338')
