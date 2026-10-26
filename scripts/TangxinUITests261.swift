import XCTest

final class TangxinUITests261: XCTestCase {
    func shot(_ name:String) {
        let a = XCTAttachment(screenshot:XCUIApplication().screenshot()); a.name = "SYNTHETIC-261-"+name; a.lifetime = .keepAlways; add(a)
    }
    func testAutomaticFailureRequiresManualRetry264() {
        let app = XCUIApplication(); app.launchArguments = ["--failure264", "--reset-network263"]; app.launch()
        app.buttons["app.tab.4"].tap(); app.swipeUp()
        let retry = app.buttons["重试"]
        XCTAssertTrue(retry.waitForExistence(timeout:8))
        for _ in 0..<3 { app.swipeUp() }
        XCTAssertTrue(retry.exists)
        XCTAssertFalse(app.buttons["tangxin.video.neutral2"].exists)
        shot("264-failed-auto-no-loop")
        retry.tap()
        XCTAssertTrue(app.buttons["tangxin.video.neutral2"].waitForExistence(timeout:8))
        shot("264-manual-retry-success")
    }
    func testAutomaticScrollHomeAndAuthor264() {
        let app = XCUIApplication(); app.launchArguments = ["--auto264", "--reset-network263"]; app.launch()
        app.buttons["app.tab.4"].tap()
        XCTAssertTrue(app.buttons["tangxin.video.scroll1"].waitForExistence(timeout:8))
        XCTAssertFalse(app.buttons["tangxin.video.tail264"].exists, "Must not fetch next at the top")
        for _ in 0..<16 {
            if app.buttons["tangxin.video.tail264"].exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["tangxin.video.tail264"].waitForExistence(timeout:8))
        shot("264-home-automatic-tail")
        let author = app.buttons["tangxin.author.tail264"]
        if !author.isHittable { app.swipeUp() }; author.tap()
        XCTAssertTrue(app.staticTexts["tangxin.author.heading"].waitForExistence(timeout:8))
        XCTAssertFalse(app.buttons["tangxin.video.tail264"].exists)
        for _ in 0..<16 {
            if app.buttons["tangxin.video.tail264"].exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["tangxin.video.tail264"].waitForExistence(timeout:8))
        shot("264-author-automatic-tail")
        app.navigationBars.buttons.element(boundBy:0).tap()
        XCTAssertTrue(app.buttons["tangxin.video.tail264"].waitForExistence(timeout:5))
        shot("264-back-retains-tail-position")
        let detailCard = app.buttons["tangxin.video.neutral1"]
        if !detailCard.isHittable { app.swipeDown() }; detailCard.tap()
        let tag = app.buttons["tangxin.tag.original"]
        XCTAssertTrue(tag.waitForExistence(timeout:8)); tag.tap()
        XCTAssertTrue(app.buttons["tangxin.video.scroll1"].waitForExistence(timeout:8))
        XCTAssertFalse(app.buttons["tangxin.video.tail264"].exists)
        for _ in 0..<16 {
            if app.buttons["tangxin.video.tail264"].exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["tangxin.video.tail264"].waitForExistence(timeout:8))
        shot("264-tag-native-list-auto-pagination")
        app.navigationBars.buttons.element(boundBy:0).tap()
        XCTAssertTrue(tag.waitForExistence(timeout:5))
    }
    func testNetworkDiagnostics263() {
        let app = XCUIApplication(); app.launchArguments = ["--network263", "--reset-network263"]; app.launch()
        app.buttons["app.tab.4"].tap()
        XCTAssertTrue(app.buttons["tangxin.network.open"].waitForExistence(timeout:8))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@", "严格模式拒绝合成")).firstMatch.waitForExistence(timeout:8))
        XCTAssertTrue(app.buttons["tangxin.retry"].exists || app.buttons["重试"].exists)
        shot("263-strict-exact-diagnostic")
        app.buttons["tangxin.network.open"].tap()
        let toggle = app.switches["tangxin.network.compatibility"]
        XCTAssertTrue(toggle.waitForExistence(timeout:5)); XCTAssertEqual(toggle.value as? String,"0")
        XCTAssertTrue(app.buttons["tangxin.network.run"].waitForExistence(timeout:8))
        app.buttons["tangxin.network.run"].tap()
        XCTAssertTrue(app.staticTexts["tangxin.network.status"].waitForExistence(timeout:8))
        XCTAssertTrue(app.staticTexts["tangxin.network.status"].label.contains("严格模式拒绝合成"))
        shot("263-native-network-sheet")
        // SwiftUI exposes the whole labelled Form row as Switch; tap the actual
        // trailing switch, not the row centre (which is only its text label).
        toggle.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)).tap()
        XCTAssertTrue(NSPredicate(format:"value == %@", "1").evaluate(with:toggle))
        let success = app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@", "HTTP 200")).firstMatch
        XCTAssertTrue(success.waitForExistence(timeout:8))
        shot("263-explicit-compatible-diagnostic")
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["tangxin.video.neutral1"].waitForExistence(timeout:8))
        // Relaunch without resetting UserDefaults: persisted mode must reach the
        // real production client before the first list request.
        app.terminate(); app.launchArguments = ["--network263"]; app.launch()
        app.buttons["app.tab.4"].tap()
        XCTAssertTrue(app.buttons["tangxin.video.neutral1"].waitForExistence(timeout:8))
        app.buttons["tangxin.network.open"].tap()
        let off = app.switches["tangxin.network.compatibility"]
        XCTAssertTrue(off.waitForExistence(timeout:5)); XCTAssertEqual(off.value as? String,"1")
        off.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)).tap()
        XCTAssertEqual(off.value as? String,"0"); app.buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@", "严格模式拒绝合成")).firstMatch.waitForExistence(timeout:8))
        shot("263-strict-restored-no-blank-state")
        app.terminate(); app.launch()
        app.buttons["app.tab.4"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@", "严格模式拒绝合成")).firstMatch.waitForExistence(timeout:8))
        app.buttons["tangxin.network.open"].tap()
        XCTAssertEqual(app.switches["tangxin.network.compatibility"].value as? String,"0")
        shot("263-persisted-strict-after-relaunch")
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
        let second = app.buttons["tangxin.video.neutral2"]
        app.swipeUp()
        XCTAssertTrue(second.waitForExistence(timeout:5)); shot("automatic-pagination-dedup")
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
