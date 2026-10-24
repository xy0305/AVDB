import XCTest

final class JavVerseNavigationTests: XCTestCase {
    private func reach(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            if upward { app.swipeUp() } else { app.swipeDown() }
        }
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
        let homeCapture = XCTAttachment(screenshot: app.screenshot())
        homeCapture.name = "javverse241-neutral-four-tabs-date-first-cover"
        homeCapture.lifetime = .keepAlways
        add(homeCapture)
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
