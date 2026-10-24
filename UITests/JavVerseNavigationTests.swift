import XCTest
import UIKit

final class JavVerseNavigationTests: XCTestCase {
    func testReleaseBundleColdLaunchRealSnapshot() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--javverse-release-bundle-ui"]
        app.launch()
        defer { app.terminate() }
        let first = app.staticTexts["javverse-row-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 20), "Real Release bundle must decode on cold launch")
        XCTAssertEqual(first.label, "SONE-371")
        XCTAssertFalse(app.staticTexts["javverse-load-failure"].exists)
        XCTAssertTrue(app.images["javverse-release-neutral-1"].firstMatch.waitForExistence(timeout: 5))
        for (tab, expected) in [("周榜", "MFYD-204"), ("月榜", "SNOS-377"), ("日榜", "SONE-371")] {
            app.buttons[tab].firstMatch.tap()
            XCTAssertTrue(first.waitForExistence(timeout: 5))
            XCTAssertEqual(first.label, expected)
            XCTAssertFalse(app.staticTexts["javverse-load-failure"].exists)
        }
        app.buttons["javverse-period-menu"].tap()
        app.buttons["javverse-period-2026-10-21"].tap()
        let historicalRow = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "SONE-269"), object: first)
        XCTAssertEqual(XCTWaiter.wait(for: [historicalRow], timeout: 10), .completed, "Wait for the real historical row after the period menu transition")
        XCTAssertEqual(first.label, "SONE-269", "Actual historical period must remain selectable")
        app.buttons["Grok Top250"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["javverse-grok-yui-hatano"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["javverse-load-failure"].exists)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "javverse247-release-real-bundle-neutral-no-image-network"
        capture.lifetime = .keepAlways
        add(capture)
        print("JAVVERSE247 Release real Bundle cold launch daily weekly monthly history Grok visible; mapper disabled; neutral artwork")
    }
    private func reach(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            if upward { app.swipeUp() } else { app.swipeDown() }
        }
    }
    func testThreeColumnsAtLargeDynamicType() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--poster-navigation-fixture", "--jr-design-fixture", "--rankings235-fixture", "--javverse-neutral-ui", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["ranking-source-menu"].waitForExistence(timeout: 20))
        app.buttons["ranking-source-menu"].tap()
        app.buttons["javverse-source-entry"].tap()
        let images = (1...4).map { app.images["javverse-neutral-cover-\($0)"].firstMatch }
        for image in images { XCTAssertTrue(image.waitForExistence(timeout: 15)) }
        let f = images.map(\.frame)
        XCTAssertLessThan(f[0].midX, f[1].midX)
        XCTAssertLessThan(f[1].midX, f[2].midX)
        XCTAssertEqual(f[0].minY, f[2].minY, accuracy: 2)
        XCTAssertGreaterThan(f[3].minY, f[0].maxY)
        XCTAssertEqual(app.staticTexts["javverse-row-4"].label, "TEST-004")
        print("JAVVERSE242 largeTypeGridGeometry frames=\(f) columns=3")
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "javverse242-neutral-large-dynamic-type-three-columns"
        capture.lifetime = .keepAlways
        add(capture)
    }
    func testIndependentEntryStaticLabelPaginationAndReturn() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--poster-navigation-fixture", "--jr-design-fixture", "--rankings235-fixture", "--javverse-neutral-ui"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["ranking-source-menu"].waitForExistence(timeout: 20))
        app.buttons["ranking-source-menu"].tap()
        XCTAssertTrue(app.buttons["javranking-home-entry"].waitForExistence(timeout: 5), "JR must remain independent")
        let entry = app.buttons["javverse-source-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        let textStart = ProcessInfo.processInfo.systemUptime
        entry.tap()
        let first = app.staticTexts["javverse-row-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 10), "Bundled list must appear without artwork wait")
        print("JAVVERSE241 textFirstVisibleMs=\((ProcessInfo.processInfo.systemUptime-textStart)*1000) neutralUI=true coldEntry=true")
        XCTAssertTrue(app.staticTexts["静态快照，非实时"].firstMatch.exists)
        let tabs = ["日榜", "周榜", "月榜", "Grok Top250"].map { app.buttons[$0].firstMatch }
        for tab in tabs { XCTAssertTrue(tab.isHittable, tab.label) }
        for tab in tabs.dropFirst() { XCTAssertLessThan(abs(tab.frame.midY-tabs[0].frame.midY), 3, "Four tabs must occupy one compact underline row") }
        let cover = app.images["javverse-neutral-cover-1"].firstMatch
        XCTAssertTrue(cover.waitForExistence(timeout: 15), "Automatic visible-page mapping must present fabricated neutral artwork")
        var frames: [CGRect] = []
        for rank in 1...4 {
            let image = app.images["javverse-neutral-cover-\(rank)"].firstMatch
            XCTAssertTrue(image.waitForExistence(timeout: 15))
            frames.append(image.frame)
            XCTAssertEqual(app.staticTexts["javverse-row-\(rank)"].label, String(format: "TEST-%03d", rank))
        }
        XCTAssertLessThan(frames[0].midX, frames[1].midX)
        XCTAssertLessThan(frames[1].midX, frames[2].midX)
        XCTAssertEqual(frames[0].minY, frames[1].minY, accuracy: 2)
        XCTAssertEqual(frames[1].minY, frames[2].minY, accuracy: 2)
        XCTAssertGreaterThan(frames[3].minY, frames[0].maxY)
        XCTAssertEqual(frames[3].minX, frames[0].minX, accuracy: 2)
        for frame in frames {
            XCTAssertEqual(frame.width / frame.height, 0.7, accuracy: 0.06)
            XCTAssertGreaterThan(frame.width, 70)
        }
        print("JAVVERSE242 gridGeometry device=\(UIDevice.current.userInterfaceIdiom.rawValue) frames=\(frames) sourceRanks=1,2,3,4")
        let homeCapture = XCTAttachment(screenshot: app.screenshot())
        homeCapture.name = "javverse242-neutral-three-column-first-four"
        homeCapture.lifetime = .keepAlways
        add(homeCapture)
        first.tap()
        XCTAssertTrue(app.staticTexts["javverse-detail-1"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["javverse-detail-1"].label, "Neutral detail TEST-001")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let seventh = app.staticTexts["javverse-row-7"]
        reach(seventh, in: app)
        XCTAssertTrue(app.staticTexts["javverse-state-7"].label.contains("尚未核验"), "Nonautomatic entries must explain the bounded queue")
        seventh.tap()
        XCTAssertTrue(app.images["javverse-neutral-cover-7"].firstMatch.waitForExistence(timeout: 15), "Whole-card action must resolve entries beyond the automatic first six")
        reach(first, in: app, upward: false)
        app.buttons["javverse-period-menu"].tap()
        app.buttons["javverse-period-neutral-previous-day"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertEqual(first.label, "PAST-001", "Historical date selects a different fixture identity")
        tabs[1].tap()
        XCTAssertEqual(first.label, "WEEK-001")
        tabs[0].tap()
        XCTAssertEqual(first.label, "PAST-001", "Daily selection survives changing board")
        app.buttons["javverse-period-menu"].tap()
        app.buttons["javverse-period-daily"].tap()
        XCTAssertEqual(first.label, "TEST-001")
        tabs[2].tap()
        XCTAssertTrue(app.staticTexts["原站仅一期"].exists)
        XCTAssertTrue(app.staticTexts["javverse-selected-period"].label.contains("unknown-year"))
        tabs[3].tap()
        XCTAssertTrue(app.staticTexts["javverse-grok-neutral-1"].waitForExistence(timeout: 5))
        let secondGrok = app.staticTexts["javverse-grok-neutral-2"]
        XCTAssertTrue(secondGrok.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["javverse-grok-neutral-1"].frame.minX, secondGrok.frame.minX, accuracy: 3, "Grok must remain a vertical actor list")
        XCTAssertGreaterThan(secondGrok.frame.minY, app.staticTexts["javverse-grok-neutral-1"].frame.minY)
        app.buttons["颜值"].tap()
        XCTAssertTrue(app.staticTexts["javverse-grok-neutral-250"].waitForExistence(timeout: 5), "Metric must reorder actual rows")
        app.buttons["作品"].tap()
        XCTAssertTrue(app.staticTexts["javverse-grok-neutral-1"].waitForExistence(timeout: 5))
        let grokCapture = XCTAttachment(screenshot: app.screenshot())
        grokCapture.name = "javverse241-neutral-grok-metric-switch"
        grokCapture.lifetime = .keepAlways
        add(grokCapture)
        tabs[0].tap()
        let next = app.buttons["下一页"]
        reach(next, in: app)
        XCTAssertTrue(next.isHittable)
        next.tap()
        let twentyOne = app.staticTexts["javverse-row-21"]
        reach(twentyOne, in: app, upward: false)
        XCTAssertTrue(twentyOne.exists)
        XCTAssertEqual(twentyOne.label, "TEST-021", "Source rank survives unmatched placeholder")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "javverse-neutral-page-two-static-snapshot"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["javverse-other-boards"].tap()
        XCTAssertTrue(app.buttons["javverse-board-featured"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["ranking-source-menu"].waitForExistence(timeout: 5))
    }
}
