import XCTest

final class PosterNavigationTests: XCTestCase {
    func testHomeLatestCoverNavigatesInNarrowAndWideWindows() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--poster-navigation-fixture"]
        app.launch()

        // Portrait is the narrow window; landscape is the wide window on the
        // same iPad simulator. Resizing an XCUIElement frame does not resize
        // the scene, so orientation is the reliable geometry change.
        let windows: [(String, UIDeviceOrientation)] = [
            ("narrow", .portrait),
            ("wide", .landscapeLeft)
        ]
        for (name, orientation) in windows {
            XCUIDevice.shared.orientation = orientation
            let header = app.descendants(matching: .any)["home-latest-header"]
            XCTAssertTrue(header.waitForExistence(timeout: 12), app.debugDescription)
            let window = app.windows.firstMatch
            XCTAssertTrue(window.waitForExistence(timeout: 4))
            if name == "narrow" {
                XCTAssertLessThan(window.frame.width, window.frame.height)
            } else {
                XCTAssertGreaterThan(window.frame.width, window.frame.height)
            }
            let poster = visibleLatestPoster(in: app, preferSecondRow: name == "wide")
            XCTAssertTrue(poster.waitForExistence(timeout: 8), app.debugDescription)
            XCTAssertTrue(poster.isHittable, "Latest cover is visible but not hittable in \(name): \(poster.frame)")
            XCTAssertGreaterThan(poster.frame.minY, header.frame.maxY)

            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "before-\(name)-\(Int(window.frame.width))x\(Int(window.frame.height))"
            attachment.lifetime = .keepAlways
            add(attachment)

            // 0.28 is inside the portrait cover (aspect 0.72). It stays inside
            // the clipped card instead of using the expanded grid-cell frame.
            let cover = poster.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28))
            cover.tap()
            let detail = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'detail-fixture-'")).firstMatch
            if !detail.waitForExistence(timeout: 6) {
                let failed = XCTAttachment(screenshot: app.screenshot())
                failed.name = "FAILED-\(name)"
                failed.lifetime = .keepAlways
                add(failed)
            }
            XCTAssertTrue(detail.exists, "Visible latest cover did not navigate in \(name) \(window.frame): \(app.debugDescription)")
            let back = app.navigationBars.buttons.element(boundBy: 0)
            XCTAssertTrue(back.waitForExistence(timeout: 4), app.debugDescription)
            back.tap()
            XCTAssertTrue(header.waitForExistence(timeout: 6))
        }
    }

    private func visibleLatestPoster(in app: XCUIApplication, preferSecondRow: Bool) -> XCUIElement {
        let header = app.descendants(matching: .any)["home-latest-header"]
        let posters = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'poster-fixture-'"))
        for _ in 0..<6 {
            let visible = posters.allElementsBoundByIndex.filter { element in
                element.exists && element.isHittable && element.frame.minY > header.frame.maxY
            }
            if !visible.isEmpty {
                if preferSecondRow, visible.count > 1 {
                    let rows = Dictionary(grouping: visible) { Int($0.frame.minY / 20) }
                    let ordered = rows.keys.sorted()
                    if ordered.count > 1, let second = rows[ordered[1]]?.first {
                        return second
                    }
                }
                return visible[0]
            }
            app.swipeUp()
        }
        return posters.firstMatch
    }
}
