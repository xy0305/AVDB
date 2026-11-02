import XCTest
import SwiftUI
import UIKit
@testable import HomeHQ298

// Hosted in the iOS simulator. Exercises production VisibleHQPosterUpgrade inside
// a real UIWindow: onAppear starts one bounded upgrade, onDisappear cancels it.
// Rasters are generated locally. This is not a device visual acceptance.
@MainActor
final class HomeHQViewTests298: XCTestCase {
    func testCardAppearUpgradesAndDisappearCancels() async throws {
        await VisibleHQPosterScheduler.shared.resetForTests()
        ListHQCoverCache.resetForTests()
        ImageLoader.resetTestTransport()
        let started = expectation(description: "visible upgrade started")
        ImageLoader.testTransport = { url, pixels in
            XCTAssertLessThanOrEqual(pixels, VisibleHQPosterPolicy.maxPixelCap)
            XCTAssertGreaterThanOrEqual(pixels, VisibleHQPosterPolicy.minPixelFloor)
            started.fulfill()
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            return nil
        }
        let movie = Movie(id: "view-1", type: "0", number: "NEUTRAL-VIEW",
                          thumbURL: "fixture://thumb", coverURL: "fixture://cover")
        let host = UIHostingController(rootView: VisibleHQPosterUpgrade(movie: movie)
            .frame(width: 120, height: 172))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        await fulfillment(of: [started], timeout: 3)
        XCTAssertLessThanOrEqual(VisibleHQPosterScheduler.testPeakActive, 2)
        window.isHidden = true
        host.view.removeFromSuperview()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNil(ListHQCoverCache.url(for: "NEUTRAL-VIEW"))
        XCTAssertFalse(ListHQCoverCache.isNegative(number: "NEUTRAL-VIEW"))
        let pixels = VisibleHQPosterPolicy.targetPixels(displayPoints: host.view.bounds.size, scale: window.screen.scale)
        XCTAssertLessThanOrEqual(pixels, 900)
        XCTAssertGreaterThan(pixels, 360)
    }
}
