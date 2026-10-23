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
        entry.tap()
        XCTAssertTrue(app.navigationBars["JavVerse · 原站名单"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["静态快照，非实时"].firstMatch.exists)
        let daily = app.buttons["javverse-board-daily"]
        reach(daily, in: app)
        XCTAssertTrue(daily.isHittable)
        daily.tap()
        XCTAssertTrue(app.navigationBars["中性分页测试"].waitForExistence(timeout: 5))
        let first = app.staticTexts["javverse-row-1"]
        reach(first, in: app)
        XCTAssertTrue(first.exists)
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
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["JavVerse · 原站名单"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["ranking-source-menu"].waitForExistence(timeout: 5))
    }
}
