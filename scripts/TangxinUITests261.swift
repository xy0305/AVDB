import XCTest

final class TangxinUITests261: XCTestCase {
    func shot(_ name:String) {
        let a = XCTAttachment(screenshot:XCUIApplication().screenshot()); a.name = "SYNTHETIC-261-"+name; a.lifetime = .keepAlways; add(a)
    }
    func scrollToPlay265(_ app: XCUIApplication) -> XCUIElement {
        let play = app.buttons["tangxin.play"]
        XCTAssertTrue(play.waitForExistence(timeout:8))
        // Real viewport swipes, not scroll-to-accessibility or only isHittable.
        for _ in 0..<12 {
            let frame = play.frame
            let tabTop = app.buttons["app.tab.4"].frame.minY
            if play.isHittable && frame.minY > 0 && frame.maxY + 8 <= tabTop { break }
            app.swipeUp()
        }
        XCTAssertTrue(play.isHittable)
        XCTAssertGreaterThan(play.frame.height,43)
        XCTAssertLessThanOrEqual(play.frame.maxY + 8, app.buttons["app.tab.4"].frame.minY,
                                 "Entire playback target must clear native tab bar")
        return play
    }
    func testCompactTagsAndActualPlaybackTap265() {
        let app = XCUIApplication(); app.launchArguments = ["--layout265", "--reset-network263"]; app.launch()
        app.buttons["app.tab.4"].tap()
        let video = app.buttons["tangxin.video.neutral1"]
        XCTAssertTrue(video.waitForExistence(timeout:8)); video.tap()
        let play = scrollToPlay265(app)
        let chips = (1...12).map { app.buttons["tangxin.tag.layout\($0)"] }
        for chip in chips { XCTAssertTrue(chip.exists); XCTAssertGreaterThanOrEqual(chip.frame.height,44) }
        let frames = chips.map { $0.frame }
        let rows = Set(frames.map { Int($0.minY.rounded()) })
        XCTAssertGreaterThanOrEqual(rows.count,2,"Twelve chips must wrap on both selected devices")
        XCTAssertLessThan(rows.count,12,"Regression: one full-width vertical row per chip")
        XCTAssertEqual(frames[0].minY,frames[1].minY,accuracy:2)
        XCTAssertGreaterThan(frames[1].minX,frames[0].maxX)
        let top = frames.map { $0.minY }.min()!, bottom = frames.map { $0.maxY }.max()!
        XCTAssertLessThanOrEqual(bottom-top,CGFloat(rows.count)*52+2,"Compact 44pt chips + 8pt row gap")
        XCTAssertLessThanOrEqual(bottom-top,312,"Bounded total chip block height")
        print("LAYOUT265 viewport=\(app.frame) chips=\(frames) rows=\(rows.count) totalHeight=\(bottom-top) play=\(play.frame) tab=\(app.buttons["app.tab.4"].frame)")
        shot("265-compact-chips-play-clears-tab")
        // Tag navigation uses the real production NavigationLink, then returns.
        let tag = chips[0]
        for _ in 0..<4 { if tag.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(tag.isHittable); tag.tap()
        XCTAssertTrue(app.buttons["tangxin.video.neutral1"].waitForExistence(timeout:8))
        shot("265-tag-navigation")
        app.navigationBars.buttons.element(boundBy:0).tap()
        XCTAssertTrue(app.buttons["tangxin.tag.layout1"].waitForExistence(timeout:8))
        // Author round trip must also retain the detail destination.
        let author = app.buttons["tangxin.detail.author"]
        for _ in 0..<8 { if author.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(author.isHittable); author.tap()
        XCTAssertTrue(app.staticTexts["tangxin.author.heading"].waitForExistence(timeout:8))
        app.navigationBars.buttons.element(boundBy:0).tap()
        let actualPlay = scrollToPlay265(app)
        actualPlay.tap()
        XCTAssertTrue(app.staticTexts["tangxin.fixture.player"].waitForExistence(timeout:10),
                      "Tap must finish real Tangxin HLS/key preflight and enter inert KSChromePlayer substitute")
        shot("265-actual-play-tap-entered-player-substitute")
    }
    func testPlaybackKeyFailureDoesNotEnterPlayer265() {
        let app = XCUIApplication(); app.launchArguments = ["--layout265", "--playback-fail265", "--reset-network263"]; app.launch()
        app.buttons["app.tab.4"].tap()
        let video = app.buttons["tangxin.video.neutral1"]
        XCTAssertTrue(video.waitForExistence(timeout:8)); video.tap()
        scrollToPlay265(app).tap()
        XCTAssertTrue(app.buttons["重试"].waitForExistence(timeout:8),"Key preflight failure must be shown, not mistaken for tab occlusion")
        XCTAssertFalse(app.staticTexts["tangxin.fixture.player"].exists)
        shot("265-key-preflight-failure-is-not-hit-testing")
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
        app.swipeUp()
        XCTAssertFalse(app.buttons["tangxin.video.tail264"].exists, "One swipe through 48 cards must not count as near-bottom")
        shot("264-first-scroll-no-prefetch")
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
        let labels = ["sourceEmpty":"源暂无数据", "structureChanged":"来源结构变化"]
        for state in ["sourceEmpty", "structureChanged"] {
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
        shot("262-safe-content")
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
