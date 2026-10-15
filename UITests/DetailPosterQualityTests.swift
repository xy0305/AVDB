import XCTest
import UIKit
import ImageIO
@testable import AVDB

final class DetailPosterQualityTests: XCTestCase {
    private func jpeg(_ width: Int, _ height: Int, orientation: Int = 1) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.gray.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image.cgImage!, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
    func testActualDecodedNativeFrontEXIFAndInvalidImages() {
        let wrap = DetailPosterResolver.decode(data: jpeg(800, 538), sourceURL: "https://tp.spfcas.com/covers/test.jpg", derive: true)!
        XCTAssertEqual(wrap.quality.width, 376); XCTAssertEqual(wrap.quality.height, 538)
        XCTAssertFalse(wrap.quality.originalPortrait)
        let full = DetailPosterResolver.decode(data: jpeg(1000, 700, orientation: 6), sourceURL: "official", derive: true)!
        XCTAssertEqual(full.quality.width, 700); XCTAssertEqual(full.quality.height, 1000)
        XCTAssertTrue(full.quality.originalPortrait)
        XCTAssertEqual(DetailPosterQuality.winner([wrap.quality, full.quality])?.source, "official")
        XCTAssertNil(DetailPosterResolver.decode(data: jpeg(147, 200), sourceURL: "thumbnail", derive: true))
        XCTAssertNil(DetailPosterResolver.decode(data: Data("<html>blocked</html>".utf8), sourceURL: "invalid", derive: true))
        XCTAssertNil(DetailPosterResolver.decode(data: jpeg(800, 538), sourceURL: "https://tp.spfcas.com/covers/test.jpg", derive: false))
        let large = DetailPosterResolver.decode(data: jpeg(1400, 2000), sourceURL: "large", derive: false)!
        XCTAssertEqual(large.quality.height, 2000)
        XCTAssertEqual(large.image.cgImage?.height, 1800)
        XCTAssertEqual(large.quality.score, 1800)
    }
    func testResolutionPreferenceAndDeterministicTies() {
        let crop = DetailPosterQuality(source: "crop", width: 700, height: 1000, originalPortrait: false)
        let near = DetailPosterQuality(source: "original", width: 672, height: 960, originalPortrait: true)
        let low = DetailPosterQuality(source: "low", width: 376, height: 538, originalPortrait: true)
        XCTAssertEqual(DetailPosterQuality.winner([crop, near, low])?.source, "original")
        XCTAssertEqual(DetailPosterQuality.winner([low, crop])?.source, "crop")
        let a = DetailPosterQuality(source: "a", width: 700, height: 1000, originalPortrait: true)
        let z = DetailPosterQuality(source: "z", width: 700, height: 1000, originalPortrait: true)
        XCTAssertEqual(DetailPosterQuality.winner([z, a])?.source, "a")
        XCTAssertEqual(DetailPosterQuality.winner([a, z])?.source, "a")
    }
    func testLowFirstHighLaterSinglePublicationAndBudget() async {
        let low = DetailPosterResolver.decode(data: jpeg(376, 538), sourceURL: "low", derive: false)!
        let high = DetailPosterResolver.decode(data: jpeg(700, 1000), sourceURL: "high", derive: false)!
        let values: [DetailPosterResolver.DecodedPoster] = await DetailPosterSelection.collect(sources: ["low", "high", "invalid", "timeout"], budget: 0.15) { source, _ in
            do {
                try await Task.sleep(nanoseconds: source == "timeout" ? 2_000_000_000 : source == "high" ? 50_000_000 : 5_000_000)
            } catch { return nil }
            return source == "low" ? low : source == "high" ? high : nil
        }
        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(DetailPosterQuality.winner(values.map(\.quality))?.source, "high")
        let generation = UUID()
        var presentation = DetailPosterPresentation<Int>(key: "new/account", generation: generation, layout: .resolving)
        presentation.complete(1, key: "old/account", generation: generation)
        XCTAssertNil(presentation.layout.artwork)
        presentation.complete(2, key: "new/account", generation: UUID())
        XCTAssertNil(presentation.layout.artwork)
        presentation.complete(7, key: "new/account", generation: generation)
        presentation.complete(9, key: "new/account", generation: generation)
        XCTAssertEqual(presentation.layout.artwork, 7)
        let task = Task { await DetailPosterSelection.collect(sources: ["late"], budget: 1) { _, _ -> Int? in
            try? await Task.sleep(nanoseconds: 500_000_000); return 99
        } }
        task.cancel()
        let cancelled = await task.value
        XCTAssertTrue(cancelled.isEmpty)
    }
}
