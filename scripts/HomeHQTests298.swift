import XCTest
import UIKit
@testable import HomeHQ298

// Runs inside the iOS simulator against production ImageLoader / scheduler.
// Images are generated locally. No adult cover and no remote host.
final class HomeHQTests298: XCTestCase {
    override func setUp() async throws {
        await VisibleHQPosterScheduler.shared.resetForTests()
        ListHQCoverCache.resetForTests()
        ImageLoader.resetTestTransport()
        await ImageLoader.shared.resetCachesForTests()
        HQPosterDiskCache.removeAll()
        VisibleHQPosterScheduler.testPeakActive = 0
    }

    func testVisibleUpgradeDownsamplesAndCaches() async throws {
        let movie = Movie(id: "n1", type: "0", number: "NEUTRAL-1",
                          thumbURL: "fixture://small", coverURL: "fixture://cover")
        let url = "https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/fixture/fixtureps.jpg"
        ImageLoader.testTransport = { requested, pixels in
            XCTAssertEqual(requested, url)
            XCTAssertLessThanOrEqual(pixels, VisibleHQPosterPolicy.maxPixelCap)
            return Self.raster(pixels: pixels, color: .systemTeal)
        }
        // Build 303 quantizes 513 → 540 so disk keys match prefetch buckets.
        let image = await VisibleHQPosterScheduler.shared.upgrade(movie: movie, url: url, maxPixelSize: 513)
        let cg = try XCTUnwrap(image?.cgImage)
        XCTAssertLessThanOrEqual(max(cg.width, cg.height), 540)
        XCTAssertGreaterThan(max(cg.width, cg.height), 360)
        XCTAssertEqual(ListHQCoverCache.url(for: "NEUTRAL-1"), url)
        XCTAssertFalse(ListHQCoverCache.isNegative(number: "NEUTRAL-1"))
    }

    func testOffscreenCancelDoesNotPoisonCache() async {
        let movie = Movie(id: "n2", type: "0", number: "NEUTRAL-2")
        let url = "https://awsimgsrc.dmm.co.jp/pics_dig/digital/video/fixture/slowps.jpg"
        ImageLoader.testTransport = { _, pixels in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { return nil }
            return Self.raster(pixels: pixels, color: .systemOrange)
        }
        let task = Task { await VisibleHQPosterScheduler.shared.upgrade(movie: movie, url: url, maxPixelSize: 513) }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        let image = await task.value
        XCTAssertNil(image)
        XCTAssertNil(ListHQCoverCache.url(for: "NEUTRAL-2"))
        XCTAssertFalse(ListHQCoverCache.isNegative(number: "NEUTRAL-2"))
    }

    func testConcurrencyCapAndFailureTTL() async {
        // Fail by URL, not by raw pixel size: upgrade() quantizes before load (400→540).
        ImageLoader.testTransport = { url, pixels in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return nil }
            return url.contains("/fail/") ? nil : Self.raster(pixels: pixels, color: .systemGreen)
        }
        let urls = (0..<4).map { i -> String in
            i == 3
                ? "https://image.mgstage.com/images/prestige/abp/fail/pf_e_abp-3.jpg"
                : "https://image.mgstage.com/images/prestige/abp/\(i)/pf_e_abp-\(i).jpg"
        }
        await withTaskGroup(of: UIImage?.self) { group in
            for (i, url) in urls.enumerated() {
                let movie = Movie(id: "c\(i)", type: "0", number: "CAP-\(i)")
                group.addTask { await VisibleHQPosterScheduler.shared.upgrade(movie: movie, url: url, maxPixelSize: 513) }
            }
        }
        XCTAssertLessThanOrEqual(VisibleHQPosterScheduler.testPeakActive, VisibleHQPosterPolicy.wifiConcurrency)
        XCTAssertTrue(ListHQCoverCache.isNegative(number: "CAP-3"))
        ListHQCoverCache.storeNegative(number: "CAP-3", ttl: 0.01)
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertFalse(ListHQCoverCache.isNegative(number: "CAP-3"))
    }

    func testPixelsFollowDisplayedCard() {
        let pixels = VisibleHQPosterPolicy.targetPixels(displayPoints: CGSize(width: 120, height: 171.4), scale: 3)
        // Build 303: quantized buckets so disk keys match prefetch (513 → 540).
        XCTAssertEqual(pixels, 540)
        XCTAssertEqual(VisibleHQPosterPolicy.targetPixels(displayPoints: CGSize(width: 2000, height: 3000), scale: 3), 900)
        XCTAssertEqual(VisibleHQPosterPolicy.listPrefetchPixels, 540)
    }

    private static func raster(pixels: Int, color: UIColor) -> UIImage {
        let side = min(pixels, VisibleHQPosterPolicy.maxPixelCap)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            color.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }
}
