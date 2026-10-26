import XCTest

final class TangxinUITests261: XCTestCase {
    func shot(_ name:String) {
        let a = XCTAttachment(screenshot:XCUIApplication().screenshot()); a.name = "SYNTHETIC-261-"+name; a.lifetime = .keepAlways; add(a)
    }
    func testEmptyStatesAndManualAdvance262() {
        let app = XCUIApplication(); app.launchArguments = ["--empty-states262"]; app.launch()
        app.buttons["app.tab.4"].tap()
        let labels = ["filtered":"当前页无可显示内容", "sourceEmpty":"源暂无数据", "structureChanged":"来源结构变化"]
        for state in ["filtered", "sourceEmpty", "structureChanged"] {
            let view = app.staticTexts[labels[state]!]
            XCTAssertTrue(view.waitForExistence(timeout:8),state)
            XCTAssertFalse(app.buttons["tangxin.video.neutral1"].exists)
            shot("262-state-"+state)
            let more = app.buttons["tangxin.more"]
            if !more.isHittable { app.swipeUp() }
            XCTAssertTrue(more.isHittable); more.tap()
        }
        XCTAssertTrue(app.buttons["tangxin.video.neutral1"].waitForExistence(timeout:8))
        XCTAssertFalse(app.buttons["tangxin.video.blocked"].exists)
        XCTAssertFalse(app.buttons["tangxin.more"].exists)
        shot("262-mixed-safe-content")
    }
    func testNativeTabAuthorWorksAndBack() {
        let app = XCUIApplication(); app.launch()
        let tab = app.buttons["app.tab.4"]
        XCTAssertTrue(tab.waitForExistence(timeout:10)); XCTAssertTrue(tab.isHittable)
        for n in 0...5 {
            let button = app.buttons["app.tab.\(n)"]
            XCTAssertTrue(button.isHittable,"All six tabs, no More: \(n)")
            XCTAssertGreaterThanOrEqual(button.frame.height,44)
        }
        tab.tap()
        let author = app.buttons["tangxin.author.neutral1"]
        XCTAssertTrue(author.waitForExistence(timeout:8)); shot("native-list")
        let more = app.buttons["tangxin.more"]
        if !more.isHittable { app.swipeUp() }
        XCTAssertTrue(more.isHittable); more.tap()
        let second = app.buttons["tangxin.video.neutral2"]
        XCTAssertTrue(second.waitForExistence(timeout:5)); shot("pagination-dedup")
        if !author.isHittable { app.swipeDown() }
        author.tap()
        XCTAssertTrue(app.staticTexts["tangxin.author.heading"].waitForExistence(timeout:5)); shot("native-author")
        let work = app.buttons["tangxin.video.neutral1"]
        XCTAssertTrue(work.waitForExistence(timeout:5)); work.tap()
        XCTAssertTrue(app.buttons["tangxin.play"].waitForExistence(timeout:5))
        XCTAssertEqual(app.navigationBars.count,1,"No outer More navigation wrapper")
        XCTAssertEqual(app.tabBars.count,0,"Only the native six-button bar, no hidden/duplicate system bar")
        shot("native-detail-NO-playback")
        app.navigationBars.buttons.element(boundBy:0).tap()
        XCTAssertTrue(app.staticTexts["tangxin.author.heading"].waitForExistence(timeout:5))
        app.navigationBars.buttons.element(boundBy:0).tap()
        XCTAssertTrue(second.waitForExistence(timeout:5)); shot("returned-list-kept-pagination")
        app.buttons["app.tab.5"].tap()
        XCTAssertTrue(app.staticTexts["合成用户替身"].waitForExistence(timeout:5))
        tab.tap(); XCTAssertTrue(second.waitForExistence(timeout:5))
    }
}
