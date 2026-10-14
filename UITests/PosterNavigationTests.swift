import XCTest

final class PosterNavigationTests: XCTestCase {
    func testJAVLibrarySnapshotPagingNativeCoverAndReturn() {
        continueAfterFailure = false
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            let app = XCUIApplication()
            app.launchArguments = ["--poster-navigation-fixture", "--javlibrary-navigation-fixture"]
            XCUIDevice.shared.orientation = orientation
            app.launch()
            let consent = app.buttons["我已满 18 岁，继续"]
            if consent.waitForExistence(timeout: 2) { consent.tap() }
            let more = app.buttons["javlibrary-load-more"]
            XCTAssertTrue(more.waitForExistence(timeout: 10), app.debugDescription)
            for _ in 0..<15 where !more.isHittable { app.swipeUp() }
            XCTAssertTrue(more.isHittable, app.debugDescription)
            more.tap()
            let poster = app.buttons["javlibrary-movie-28"]
            for _ in 0..<10 where !poster.isHittable { app.swipeUp() }
            XCTAssertTrue(poster.isHittable, app.debugDescription)
            let y = poster.frame.minY
            poster.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28)).tap()
            XCTAssertTrue(app.staticTexts["javlibrary-detail-28"].waitForExistence(timeout: 5))
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(poster.waitForExistence(timeout: 5))
            XCTAssertTrue(poster.isHittable, "JAVLibrary return lost loaded page")
            XCTAssertEqual(poster.frame.minY, y, accuracy: 60)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "javlibrary-native-return-\(orientation.rawValue)"
            shot.lifetime = .keepAlways
            add(shot)
            app.terminate()
        }
    }

    func testExternalDatabaseSettingsEntryDoesNotRevealStoredToken() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--poster-navigation-fixture"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate() }
        // iPadOS 26 floating tabs are buttons under Other, not a TabBar container.
        let me = app.buttons["我的"].firstMatch
        XCTAssertTrue(me.waitForExistence(timeout: 10), app.debugDescription)
        me.tap()
        let entry = app.buttons["external-settings-entry"]
        for _ in 0..<8 where !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        let field = app.secureTextFields["external-token"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let displayed = field.value as? String ?? ""
        XCTAssertTrue(displayed.isEmpty || displayed == "新令牌（留空保留已保存令牌）", "The secure field must remain empty/placeholder-only")
        XCTAssertTrue(app.buttons["external-save"].exists)
        XCTAssertTrue(app.buttons["external-clear"].exists)
        XCTAssertTrue(app.staticTexts["external-token-status"].exists)
        // Navigation-only: never save a credential, query the service, or submit a 115 task.
    }
    func testRankingLoadMoreDetailBackPreservesVisibleRank() {
        continueAfterFailure = false
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            let app = XCUIApplication()
            // Reuse neutral poster image harness, but mount the shipping JR page/grid.
            app.launchArguments = ["--poster-navigation-fixture", "--jr-navigation-fixture"]
            XCUIDevice.shared.orientation = orientation
            app.launch()
            let more = app.buttons["jr-load-more"]
            XCTAssertTrue(more.waitForExistence(timeout: 10))
            for _ in 0..<12 where !more.isHittable { app.swipeUp() }
            XCTAssertTrue(more.isHittable, app.debugDescription)
            more.tap()
            let poster = app.buttons["jr-poster-14"]
            for _ in 0..<8 where !poster.isHittable { app.swipeUp() }
            XCTAssertTrue(poster.isHittable, app.debugDescription)
            let beforeY = poster.frame.minY
            let before = XCTAttachment(screenshot: app.screenshot())
            before.name = "ranking-before-rank14-\(orientation.rawValue)"
            before.lifetime = .keepAlways
            add(before)
            poster.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28)).tap()
            XCTAssertTrue(app.staticTexts["jr-detail-14"].waitForExistence(timeout: 5))
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(poster.waitForExistence(timeout: 5))
            XCTAssertTrue(poster.isHittable, "Returning discarded loaded count/anchor: \(app.debugDescription)")
            XCTAssertFalse(app.buttons["jr-poster-1"].isHittable, "Returned to rank 1")
            XCTAssertEqual(poster.frame.minY, beforeY, accuracy: 60, "Returning shifted more than row offset tolerance")
            let after = XCTAttachment(screenshot: app.screenshot())
            after.name = "ranking-after-rank14-\(orientation.rawValue)"
            after.lifetime = .keepAlways
            add(after)
            app.terminate()
        }
    }

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
            let header = app.staticTexts["home-latest-header"].firstMatch
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
        let header = app.staticTexts["home-latest-header"].firstMatch
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
