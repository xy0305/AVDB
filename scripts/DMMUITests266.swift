import XCTest
final class DMMUITests266: XCTestCase {
    func testImportedWeeklyRankAndExactDetailBoundary() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["週間 · 100榜位 · 统计起止未知"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["dmm-source-status"].label.contains("用户导入100"))
        // Maker-verified rows may already auto-resolve via onAppear; otherwise tap once.
        let verify = app.buttons["精确核对AVDB"].firstMatch
        if verify.waitForExistence(timeout: 3) { verify.tap() }
        let movie = app.descendants(matching: .any)["dmm-movie-1"].firstMatch
        XCTAssertTrue(movie.waitForExistence(timeout: 10), app.debugDescription)
        movie.tap()
        XCTAssertTrue(app.staticTexts["dmm-fixture-detail-id"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["dmm-fixture-detail-id"].label, "详情ID: avdb-real-fixture-id")
        app.navigationBars.buttons.firstMatch.tap()
        for _ in 0..<4 { app.buttons["下一页"].tap() }
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '#81 · DMM'")).firstMatch.waitForExistence(timeout: 5))
        for _ in 0..<12 {
            if app.staticTexts.containing(NSPredicate(format: "label CONTAINS '#100 · DMM'")).firstMatch.exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '#100 · DMM'")).firstMatch.exists)
        XCTAssertFalse(app.buttons["下一页"].isEnabled)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "DMM266-offline-rank100"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
