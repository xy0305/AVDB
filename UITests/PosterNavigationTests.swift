import XCTest

final class PosterNavigationTests: XCTestCase {
    func testHomePosterCentersAfterScrollAndReturn() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--poster-navigation-fixture"]
        app.launch()
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            for index in [8, 7, 9, 2] {
                let poster = app.buttons["poster-fixture-\(index)"]
                for _ in 0..<8 {
                    if poster.exists {
                        let centerY = poster.frame.minY + poster.frame.width / 0.72 / 2
                        if poster.isHittable && centerY > 130 && centerY < app.frame.maxY - 70 { break }
                        if centerY < 130 { app.swipeDown(); continue }
                    }
                    app.swipeUp()
                }
                XCTAssertTrue(poster.waitForExistence(timeout: 10), app.debugDescription)
                let attachment = XCTAttachment(screenshot: app.screenshot())
                attachment.name = "before-\(orientation.rawValue)-slot-\(index)"
                attachment.lifetime = .keepAlways
                add(attachment)
                // Cover center rather than label center: cover occupies first width / 0.72 points.
                let point = poster.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: poster.frame.width / 2, dy: poster.frame.width / 0.72 / 2))
                point.tap()
                let detail = app.staticTexts["detail-fixture-\(index)"]
                if !detail.waitForExistence(timeout: 5) {
                    let failed = XCTAttachment(screenshot: app.screenshot())
                    failed.name = "FAILED-slot-\(index)"
                    failed.lifetime = .keepAlways
                    add(failed)
                    add(XCTAttachment(string: app.debugDescription))
                }
                XCTAssertTrue(detail.exists, "Cover center did not navigate to correct movie: \(app.debugDescription)")
                app.navigationBars.buttons.element(boundBy: 0).tap()
                XCTAssertTrue(poster.waitForExistence(timeout: 5))
            }
        }
    }
}
