import XCTest

final class TabUITests283: XCTestCase {
    func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    func testSearchHidesFloatingTabBar() throws {
        let app = XCUIApplication(); app.launch()
        let homeTab = app.buttons["app.tab.0"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 10), "tab bar visible on home")
        shot(app, "01-home-tabbar-visible")
        app.buttons["fixture.search.首頁"].firstMatch.tap()
        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 5))
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: homeTab); waitForExpectations(timeout: 5)
        sleep(1)
        shot(app, "02-search-keyboard-tabbar-hidden")
        app.buttons["search.cancel"].tap()
        XCTAssertTrue(homeTab.waitForExistence(timeout: 5), "tab bar restored after cancel")
        sleep(1)
        shot(app, "03-search-cancel-tabbar-restored")
        // Other screens with text fields: keyboard up hides the bar, dismiss restores it.
        app.buttons["app.tab.5"].tap()
        let field = app.textFields["me.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap()
        if app.keyboards.firstMatch.waitForExistence(timeout: 5) {
            expectation(for: gone, evaluatedWith: app.buttons["app.tab.5"]); waitForExpectations(timeout: 5)
            sleep(1)
            shot(app, "04-me-textfield-keyboard-tabbar-hidden")
        }
    }
}
