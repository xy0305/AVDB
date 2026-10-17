import XCTest

final class PosterNavigationTests: XCTestCase {
    func testLongDetailTitleThreeLinesExpandsAndPersistsVisibility() {
        verifyReadableDetail(accessibilitySize: false)
    }

    func testAccessibleDetailTitleAndLandscapeActions() {
        verifyReadableDetail(accessibilitySize: true)
    }

    // SwiftUI exposes the whole labelled row as a Switch. Its midpoint is the
    // label, not the trailing native thumb (notably after iPad rotation).
    // Tap the actual control and keep the value/persistence assertions intact.
    private func tapCoverTitleSwitch(_ control: XCUIElement) {
        XCTAssertTrue(control.isHittable)
        let diagnostic = XCTAttachment(string: "Cover-title switch frame: \(control.frame), value: \(String(describing: control.value))")
        diagnostic.name = "192-title-switch-hit-target"
        diagnostic.lifetime = .keepAlways; add(diagnostic)
        control.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: -25, dy: 0)).tap()
    }

    // Rotation notifications precede the AX root snapshot update. In run
    // 39010810783 the return tap used a 1376x1032 root snapshot with a
    // 1032x1376 event window and landed outside the 44pt back button.
    // Synchronize the observable app/window geometry, not another gesture.
    private func waitForInterfaceGeometry(_ app: XCUIApplication, portrait: Bool) {
        let geometry = NSPredicate { _, _ in
            let root = app.frame
            let window = app.windows.firstMatch.frame
            return root.width > 0 && window.width > 0
                && (root.width < root.height) == portrait
                && (window.width < window.height) == portrait
                && abs(root.width - window.width) < 1
                && abs(root.height - window.height) < 1
        }
        expectation(for: geometry, evaluatedWith: app)
        waitForExpectations(timeout: 10)
    }

    private func verifyReadableDetail(accessibilitySize: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--poster-navigation-fixture", "--detail-hero-fixture", "--long-detail-title"]
        if accessibilitySize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        let consent = app.buttons["我已满 18 岁，继续"]
        if consent.waitForExistence(timeout: 2) { consent.tap() }
        let visibility = app.switches["detail-cover-title-setting"]
        if visibility.exists && visibility.value as? String == "0" { tapCoverTitleSwitch(visibility) }
        app.buttons["neutral-portrait-link"].tap()
        let title = app.staticTexts["portrait-hero-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertLessThanOrEqual(title.frame.height, 180, "Default is at most three old-size lines")
        XCTAssertGreaterThan(title.frame.minY, app.buttons["返回"].frame.maxY, "Title stays over the original lower hero")
        let toggle = app.buttons["detail-title-toggle"]
        let reviewPanel = app.descendants(matching: .any)["detail-reviews-panel"].firstMatch
        XCTAssertTrue(reviewPanel.exists)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let collapsedHeight = title.frame.height
        let shownPlayY = app.buttons["portrait-hero-play"].frame.minY
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = accessibilitySize ? "192-neutral-three-lines-accessibility" : "192-neutral-three-lines-shown"
        shot.lifetime = .keepAlways; add(shot)
        for _ in 0..<5 where !toggle.isHittable || toggle.frame.maxY > reviewPanel.frame.minY { app.swipeUp() }
        XCTAssertTrue(toggle.isHittable); toggle.tap()
        XCTAssertGreaterThan(title.frame.height, collapsedHeight)
        XCTAssertEqual(toggle.label, "收起标题")
        let expandedPlay = app.buttons["portrait-hero-play"]
        for _ in 0..<12 where !expandedPlay.isHittable || expandedPlay.frame.maxY > reviewPanel.frame.minY { app.swipeUp() }
        XCTAssertTrue(expandedPlay.isHittable)
        XCTAssertGreaterThanOrEqual(expandedPlay.frame.height, 44)
        let expanded = XCTAttachment(screenshot: app.screenshot())
        expanded.name = "192-neutral-expanded-title-controls-reachable"
        expanded.lifetime = .keepAlways; add(expanded)
        for _ in 0..<6 where !toggle.isHittable { app.swipeDown() }
        for _ in 0..<12 where !toggle.isHittable || toggle.frame.maxY > reviewPanel.frame.minY { app.swipeUp() }
        XCTAssertTrue(toggle.isHittable); toggle.tap()
        XCTAssertEqual(toggle.label, "展开全文")
        XCTAssertEqual(title.frame.height, collapsedHeight, accuracy: 1)
        let play = app.buttons["portrait-hero-play"]
        for _ in 0..<8 where !play.isHittable { app.swipeDown() }
        if !play.isHittable { app.swipeUp() }
        XCTAssertTrue(play.isHittable)
        XCTAssertGreaterThanOrEqual(play.frame.height, 44)
        for name in ["下载资源", "存入清单", "想看", "看过"] {
            let action = app.buttons[name]
            let panel = app.descendants(matching: .any)["detail-reviews-panel"].firstMatch
            XCTAssertTrue(panel.exists)
            for _ in 0..<6 where !action.isHittable || action.frame.maxY > panel.frame.minY { app.swipeUp() }
            XCTAssertTrue(action.isHittable, name)
            XCTAssertGreaterThanOrEqual(action.frame.height, 44)
            XCTAssertLessThanOrEqual(action.frame.maxY, panel.frame.minY + 1, "Comments must not cover reachable actions")
        }
        let download = app.buttons["下载资源"]
        for _ in 0..<6 where !download.isHittable { app.swipeDown() }
        download.tap()
        XCTAssertTrue(app.navigationBars["播放与下载资源"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForInterfaceGeometry(app, portrait: false)
        let landscape = XCTAttachment(screenshot: app.screenshot())
        landscape.name = "192-neutral-original-hero-landscape"
        landscape.lifetime = .keepAlways; add(landscape)
        XCTAssertTrue(app.buttons["返回"].isHittable)
        XCUIDevice.shared.orientation = .portrait
        waitForInterfaceGeometry(app, portrait: true)
        app.buttons["返回"].tap()
        XCTAssertTrue(visibility.waitForExistence(timeout: 5)); tapCoverTitleSwitch(visibility)
        XCTAssertEqual(visibility.value as? String, "0")
        app.buttons["neutral-portrait-link"].tap()
        let hiddenPlay = app.buttons["portrait-hero-play"]
        XCTAssertTrue(hiddenPlay.waitForExistence(timeout: 10))
        XCTAssertFalse(title.exists, "Hidden title must not remain in accessibility tree")
        XCTAssertFalse(toggle.exists, "Hidden title must remove disclosure too")
        XCTAssertLessThan(hiddenPlay.frame.minY, shownPlayY - collapsedHeight + 4, "No reserved title/disclosure height")
        XCTAssertTrue(app.staticTexts["DEMO-123"].exists)
        let hidden = XCTAttachment(screenshot: app.screenshot())
        hidden.name = "192-neutral-original-hero-title-hidden"
        hidden.lifetime = .keepAlways; add(hidden)
        app.buttons["返回"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(visibility.waitForExistence(timeout: 10))
        XCTAssertEqual(visibility.value as? String, "0", "UserDefaults must survive app relaunch")
        app.buttons["neutral-portrait-link"].tap()
        XCTAssertTrue(hiddenPlay.waitForExistence(timeout: 10))
        XCTAssertFalse(title.exists); XCTAssertFalse(toggle.exists)
        app.buttons["返回"].tap()
        app.buttons["neutral-wide-link"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["legacy-landscape-header"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["landscape-detail-title"].exists)
        let widePlay = app.buttons["landscape-hero-play"]
        XCTAssertTrue(widePlay.isHittable)
        XCTAssertGreaterThanOrEqual(widePlay.frame.height, 44)
        for name in ["想看", "看過", "存入清單"] {
            let action = app.buttons[name]
            for _ in 0..<8 where !action.isHittable { app.swipeUp() }
            XCTAssertTrue(action.isHittable, name)
            XCTAssertGreaterThanOrEqual(action.frame.height, 44)
        }
        app.buttons["返回"].tap()
        tapCoverTitleSwitch(visibility)
        XCTAssertEqual(visibility.value as? String, "1")
    }

    // The real chrome auto-hides after five seconds. AX inspection/launch on CI
    // can consume that interval: run 39018850097 lost the button between frame
    // inspection and coordinate resolution. Refresh through the real single-tap
    // path, then target the real button; do not disable the production timer.
    private func refreshPlayerChrome(_ app: XCUIApplication) {
        let entry = app.buttons["player.subtitle.settings"]
        let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        // AX may report the pre-hide snapshot just as the timer expires. A tap
        // then reveals instead of hides; retry the observed state, boundedly.
        for _ in 0..<3 {
            if !entry.exists { break }
            center.tap()
            let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !entry.exists }, object: app)
            if XCTWaiter.wait(for: [hidden], timeout: 1.5) == .completed { break }
        }
        XCTAssertFalse(entry.exists, "Real center tap must hide chrome before refresh")
        center.tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(entry.isHittable, app.debugDescription)
    }

    private func scrollSubtitleForm(_ app: XCUIApplication) {
        if app.collectionViews.firstMatch.exists { app.collectionViews.firstMatch.swipeUp() }
        else if app.tables.firstMatch.exists { app.tables.firstMatch.swipeUp() }
        else { app.swipeUp() }
    }

    private func enterSubtitleLandscape(_ app: XCUIApplication) {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch.frame
        if min(window.width, window.height) > 600 {
            XCUIDevice.shared.orientation = .landscapeRight
        } else {
            // The launch fixture can request landscape before XCTest's device
            // orientation changes. Retain the real production menu transition,
            // then synchronize the event generator as well as AX geometry.
            refreshPlayerChrome(app)
            app.buttons["进入全屏幕"].tap()
            XCTAssertTrue(app.buttons["横屏全屏"].waitForExistence(timeout: 3))
            app.buttons["横屏全屏"].tap()
            XCUIDevice.shared.orientation = .landscapeRight
        }
        waitForInterfaceGeometry(app, portrait: false)
        let geometry = XCTAttachment(string: "App: \(app.frame); real player window: \(app.windows.firstMatch.frame)")
        geometry.name = "195-real-player-landscape-geometry"; geometry.lifetime = .keepAlways; add(geometry)
    }

    func testSubtitleControlsRealPlayerHitTargetsStyleAndDrag() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--poster-navigation-fixture", "--subtitle-controls-fixture"]
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        let consent = app.buttons["我已满 18 岁，继续"]
        if consent.waitForExistence(timeout: 2) { consent.tap() }
        // Await actual production window geometry, not a button coordinate.
        enterSubtitleLandscape(app)
        refreshPlayerChrome(app)
        let entry = app.buttons["player.subtitle.settings"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), app.debugDescription)
        // The player view itself must be landscape; the app root snapshot can lag.
        XCTAssertGreaterThan(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height, app.debugDescription)
        // IEEE-754 AX coordinates may subtract to 47.99999999999997 for 48pt.
        // This epsilon is sub-pixel numerical precision, not a smaller hit target.
        XCTAssertGreaterThanOrEqual(entry.frame.width + 0.000001, 48)
        XCTAssertGreaterThanOrEqual(entry.frame.height + 0.000001, 48)
        let originalOrientation = XCUIDevice.shared.orientation
        // Both center and near-edge points must reach the actual player button,
        // not a parallel fixture button or a transparent tap recognizer.
        for point in [CGVector(dx: 0.5, dy: 0.5), CGVector(dx: 0.06, dy: 0.06), CGVector(dx: 0.94, dy: 0.94)] {
            refreshPlayerChrome(app)
            entry.coordinate(withNormalizedOffset: point).tap()
            XCTAssertTrue(app.textFields["subtitle.query"].waitForExistence(timeout: 5), app.debugDescription)
            app.buttons["完成"].tap()
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
        }
        XCTAssertEqual(XCUIDevice.shared.orientation, originalOrientation)
        refreshPlayerChrome(app)
        XCTAssertTrue(app.buttons["player.source.settings"].isHittable)
        let play = app.buttons["player.play.toggle"]
        XCTAssertEqual(play.label, "暂停", "Opening/dismissing subtitles must not pause playback")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "194-neutral-player-white-source-caption"; shot.lifetime = .keepAlways; add(shot)
        entry.tap()
        func reveal(_ element: XCUIElement) {
            for _ in 0..<8 { if element.isHittable { return }; scrollSubtitleForm(app) }
            XCTAssertTrue(element.isHittable, app.debugDescription)
        }
        let reset = app.buttons["subtitle.appearance.reset"]
        reveal(reset); reset.tap()
        let increase = app.buttons["增大字号"]
        reveal(increase); increase.tap()
        XCTAssertEqual(app.staticTexts["subtitle.font.value"].label, "字号 19 pt")
        let edit = app.buttons["subtitle.position.edit"]
        reveal(edit); edit.tap()
        let caption = app.otherElements["subtitle.rendered"]
        XCTAssertTrue(caption.waitForExistence(timeout: 5), app.debugDescription)
        let before = caption.frame
        caption.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.2, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.34)))
        let after = caption.frame
        XCTAssertLessThan(after.midY, before.midY - 5)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(after), "Caption must clamp within visible bounds")
        let edited = XCTAttachment(screenshot: app.screenshot())
        edited.name = "194-neutral-position-edit"; edited.lifetime = .keepAlways; add(edited)
        app.buttons["subtitle.position.done"].tap()
        XCTAssertEqual(play.label, "暂停", "Caption drag must not pause/seek via player recognizers")
        XCTAssertFalse(app.otherElements["player.seek.preview"].exists)
        app.terminate(); app.launch()
        refreshPlayerChrome(app)
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap(); reveal(app.staticTexts["subtitle.font.value"])
        XCTAssertEqual(app.staticTexts["subtitle.font.value"].label, "字号 19 pt", "User style persists across application relaunch")
        reveal(reset); reset.tap()
        XCTAssertEqual(app.staticTexts["subtitle.font.value"].label, "字号 18 pt")
        app.buttons["完成"].tap()
    }

    func testSubtitleNoCuePreviewClampsAndRotates() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--poster-navigation-fixture", "--subtitle-controls-fixture", "--subtitle-no-cue"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        let consent = app.buttons["我已满 18 岁，继续"]
        if consent.waitForExistence(timeout: 2) { consent.tap() }
        // Await actual production window geometry, not a button coordinate.
        enterSubtitleLandscape(app)
        refreshPlayerChrome(app)
        let entry = app.buttons["player.subtitle.settings"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertGreaterThan(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height, app.debugDescription)
        entry.tap()
        XCTAssertTrue(app.textFields["subtitle.query"].waitForExistence(timeout: 5), app.debugDescription)
        let edit = app.buttons["subtitle.position.edit"]
        for _ in 0..<8 { if edit.isHittable { break }; scrollSubtitleForm(app) }
        XCTAssertTrue(edit.isHittable); edit.tap()
        let caption = app.otherElements["subtitle.rendered"]
        XCTAssertTrue(caption.waitForExistence(timeout: 5))
        XCTAssertEqual(caption.label, "字幕位置预览")
        caption.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.2, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99)))
        XCTAssertTrue(app.windows.firstMatch.frame.contains(caption.frame))
        let isPadWindow = min(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height) > 600
        if isPadWindow {
            XCUIDevice.shared.orientation = .portrait
            waitForInterfaceGeometry(app, portrait: true)
        } else {
            // iPhone production playback deliberately locks orientation. Exercise
            // its real portrait menu rather than expecting a sensor to unlock it.
            app.buttons["subtitle.position.done"].tap()
            refreshPlayerChrome(app)
            app.buttons["进入全屏幕"].tap()
            XCTAssertTrue(app.buttons["竖屏播放"].waitForExistence(timeout: 3))
            app.buttons["竖屏播放"].tap()
            XCUIDevice.shared.orientation = .portrait
            waitForInterfaceGeometry(app, portrait: true)
            refreshPlayerChrome(app)
            entry.tap()
            XCTAssertTrue(app.textFields["subtitle.query"].waitForExistence(timeout: 5))
            for _ in 0..<8 { if edit.isHittable { break }; scrollSubtitleForm(app) }
            XCTAssertTrue(edit.isHittable); edit.tap()
            XCTAssertTrue(caption.waitForExistence(timeout: 5))
            XCTAssertEqual(caption.label, "字幕位置预览")
        }
        XCTAssertLessThan(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(caption.frame), app.debugDescription)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "194-neutral-no-cue-portrait-clamp"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["subtitle.position.reset"].tap()
        app.buttons["subtitle.position.done"].tap()
        XCTAssertFalse(caption.exists, "No synthetic dialogue in normal playback")
    }

    func testRealPlayerSelectedSubtitleDisableSeekAndReselect() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--poster-navigation-fixture", "--subtitle-controls-fixture", "--subtitle-no-cue"]
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        let consent = app.buttons["我已满 18 岁，继续"]
        if consent.waitForExistence(timeout: 2) { consent.tap() }
        enterSubtitleLandscape(app)
        let entry = app.buttons["player.subtitle.settings"]
        let caption = app.otherElements["subtitle.rendered"]
        func selectSubtitle() {
            refreshPlayerChrome(app); entry.tap()
            XCTAssertTrue(app.textFields["subtitle.query"].waitForExistence(timeout: 5))
            app.buttons["subtitle.search"].tap()
            let candidate = app.buttons["subtitle.candidate"].firstMatch
            let searched = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.staticTexts["subtitle.status"].label == "请选择字幕；名称匹配不代表时间轴匹配"
            }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [searched], timeout: 5), .completed)
            // SwiftUI Form virtualizes off-screen result rows in short landscape
            // windows. Scroll the real form before asserting row existence.
            for _ in 0..<8 { if candidate.isHittable { break }; scrollSubtitleForm(app) }
            XCTAssertTrue(candidate.waitForExistence(timeout: 5))
            XCTAssertTrue(candidate.isHittable); candidate.tap()
            let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.staticTexts["subtitle.status"].label.contains("已加载")
            }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 5), .completed)
            // Completion stays pinned even after scrolling down to the result.
            XCTAssertTrue(app.buttons["subtitle.panel.done"].isHittable)
            app.buttons["subtitle.panel.done"].tap()
            XCTAssertTrue(caption.waitForExistence(timeout: 5))
        }
        selectSubtitle()
        refreshPlayerChrome(app)
        XCTAssertEqual(app.buttons["player.play.toggle"].label, "暂停")
        XCTAssertTrue(app.buttons["player.episode.settings"].isHittable)
        XCTAssertTrue(app.buttons["player.source.settings"].isHittable)
        let shown = XCTAttachment(screenshot: app.screenshot())
        shown.name = "195-neutral-selected-caption-white-episode-source"; shown.lifetime = .keepAlways; add(shown)
        refreshPlayerChrome(app); entry.tap()
        XCTAssertTrue(app.textFields["subtitle.query"].waitForExistence(timeout: 5))
        scrollSubtitleForm(app)
        let off = app.buttons["subtitle.disable"]
        XCTAssertTrue(off.isHittable, "关闭字幕必须固定可见")
        off.tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !caption.exists }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 3), .completed)
        XCTAssertFalse(app.textFields["subtitle.query"].exists)
        refreshPlayerChrome(app)
        XCTAssertEqual(app.buttons["player.play.toggle"].label, "暂停")
        app.sliders.firstMatch.adjust(toNormalizedSliderPosition: 0.65)
        let acrossCue = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !caption.exists }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [acrossCue], timeout: 3), .completed)
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        XCTAssertFalse(caption.exists, "关闭后跨字幕段落及seek仍不得重新显示")
        refreshPlayerChrome(app)
        let hidden = XCTAttachment(screenshot: app.screenshot())
        hidden.name = "195-neutral-disabled-after-seek-white-episode-source"; hidden.lifetime = .keepAlways; add(hidden)
        selectSubtitle()
        XCTAssertTrue(caption.label.contains("自创外置字幕"))
        refreshPlayerChrome(app); entry.tap()
        XCTAssertTrue(app.buttons["subtitle.disable"].waitForExistence(timeout: 5))
        app.buttons["subtitle.disable"].tap()
        XCTAssertFalse(caption.exists)
    }

    func testOnlineSubtitleConsentSelectionOffsetAndDisable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--poster-navigation-fixture", "--online-subtitle-fixture"]
        app.launch()
        defer { app.terminate() }
        let consent = app.buttons["我已满 18 岁，继续"]
        if consent.waitForExistence(timeout: 2) { consent.tap() }
        let entry = app.buttons["player.subtitle.settings"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
        XCTAssertTrue(app.textFields["subtitle.query"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["subtitle.candidate"].exists)
        app.buttons["subtitle.search"].tap()
        let candidate = app.buttons["subtitle.candidate"].firstMatch
        if !candidate.isHittable { app.swipeUp() }
        XCTAssertTrue(candidate.waitForExistence(timeout: 5)); candidate.tap()
        app.swipeDown()
        XCTAssertTrue(app.staticTexts["来源：迅雷 · 自创合法测试字幕"].waitForExistence(timeout: 5))
        app.buttons["subtitle.earlier"].tap()
        XCTAssertTrue(app.staticTexts["-0.5 秒"].exists)
        app.buttons["subtitle.later"].tap()
        let offsetReset = app.buttons["subtitle.reset"]
        for _ in 0..<8 { if offsetReset.isHittable { break }; scrollSubtitleForm(app) }
        XCTAssertTrue(offsetReset.isHittable); offsetReset.tap()
        XCTAssertTrue(app.staticTexts["+0.0 秒"].exists)
        app.buttons["subtitle.disable"].tap()
        XCTAssertFalse(app.textFields["subtitle.query"].exists, "关闭字幕同时返回播放")
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        XCTAssertTrue(app.staticTexts["subtitle.status"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["subtitle.status"].label.contains("已关闭"))
        app.buttons["完成"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
    }

    func testDelayedPosterNeverShowsOldLandscapeAndWarmWinnerIsImmediate() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--poster-navigation-fixture", "--detail-hero-fixture", "--delayed-detail-poster"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate() }
        let consent = app.buttons["我已满 18 岁，继续"]
        if consent.waitForExistence(timeout: 2) { consent.tap() }
        app.buttons["neutral-portrait-link"].tap()
        let pending = app.staticTexts["resolving-hero-title"]
        XCTAssertTrue(pending.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["legacy-landscape-header"].firstMatch.exists)
        XCTAssertTrue(app.buttons["portrait-hero-play"].isHittable)
        XCTAssertTrue(app.buttons["下载资源"].isHittable)
        let beforeY = app.buttons["portrait-hero-play"].frame.minY
        let pendingShot = XCTAttachment(screenshot: app.screenshot())
        pendingShot.name = "184-neutral-pending-no-old-landscape"
        pendingShot.lifetime = .keepAlways; add(pendingShot)
        let title = app.staticTexts["portrait-hero-title"]
        let deadline = Date().addingTimeInterval(10)
        while pending.exists && Date() < deadline {
            XCTAssertFalse(app.descendants(matching: .any)["legacy-landscape-header"].firstMatch.exists)
            if title.exists { break }
        }
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        XCTAssertEqual(app.buttons["portrait-hero-play"].frame.minY, beforeY, accuracy: 1)
        let finalShot = XCTAttachment(screenshot: app.screenshot())
        finalShot.name = "184-neutral-final-single-winner"
        finalShot.lifetime = .keepAlways; add(finalShot)
        app.buttons["返回"].tap()
        app.buttons["neutral-portrait-link"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        XCTAssertFalse(pending.exists, "Winner cache must not wait or re-publish a low-quality source")
        app.buttons["返回"].tap()
        app.buttons["neutral-wide-link"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["legacy-landscape-header"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(pending.exists)
        XCTAssertFalse(title.exists)
        let wideShot = XCTAttachment(screenshot: app.screenshot())
        wideShot.name = "184-neutral-known-wide-immediate-fallback"
        wideShot.lifetime = .keepAlways; add(wideShot)
    }

    func testConditionalPortraitHeroRealDetailAndWideFallback() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--poster-navigation-fixture", "--detail-hero-fixture"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let consent = app.buttons["我已满 18 岁，继续"]
        if consent.waitForExistence(timeout: 2) { consent.tap() }
        app.buttons["neutral-portrait-link"].tap()
        let title = app.staticTexts["portrait-hero-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), app.debugDescription)
        let play = app.buttons["portrait-hero-play"]
        XCTAssertTrue(play.isHittable)
        let back = app.buttons["返回"]
        XCTAssertTrue(back.isHittable)
        XCTAssertGreaterThanOrEqual(back.frame.minY, 24, "Back must clear the status bar safe area")
        XCTAssertGreaterThanOrEqual(play.frame.height, 44)
        XCTAssertGreaterThan(title.frame.minY, back.frame.maxY)
        XCTAssertLessThan(title.frame.maxY, play.frame.minY, "Original overlay title precedes old white play button")
        XCTAssertFalse(app.buttons["detail-title-toggle"].exists, "Short titles need no expansion control")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "native-neutral-portrait-hero-phone-or-ipad"
        shot.lifetime = .keepAlways; add(shot)
        app.buttons["下载资源"].tap()
        XCTAssertTrue(app.navigationBars["播放与下载资源"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["完成"].isHittable)
        app.buttons["完成"].tap()
        app.buttons["返回"].tap()
        XCTAssertTrue(app.buttons["neutral-wide-link"].waitForExistence(timeout: 5))
        app.buttons["neutral-wide-link"].tap()
        XCTAssertFalse(app.staticTexts["portrait-hero-title"].exists, "Wide/failure must preserve original detail")
        XCTAssertTrue(app.staticTexts["landscape-detail-title"].exists)
        let wide = XCTAttachment(screenshot: app.screenshot())
        wide.name = "native-neutral-original-wide-detail-fallback"
        wide.lifetime = .keepAlways; add(wide)
        app.terminate()
    }

    func testRecentMagnetCatalogRealViewReturnWithoutReload() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--poster-navigation-fixture", "--catalog-navigation-fixture"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate() }
        let consent = app.buttons["我已满 18 岁，继续"]
        if consent.waitForExistence(timeout: 2) { consent.tap() }
        let diagnostics = app.staticTexts["catalog-diagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 10))
        let ready = NSPredicate(format: "label == %@", "items=60 requests=1")
        expectation(for: ready, evaluatedWith: diagnostics)
        waitForExpectations(timeout: 10)
        let poster = app.buttons["poster-catalog-14"]
        let first = app.buttons["poster-catalog-1"]
        for _ in 0..<18 {
            if poster.isHittable && !first.isHittable { break }
            let window = app.windows.firstMatch
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.60)))
        }
        XCTAssertTrue(poster.isHittable, app.debugDescription)
        XCTAssertFalse(first.isHittable, "Fixture must exercise a scrolled catalog, not initial top")
        let beforeY = poster.frame.minY
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "recent-magnet-production-before-rank14"
        before.lifetime = .keepAlways
        add(before)
        poster.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28)).tap()
        XCTAssertTrue(app.staticTexts["detail-catalog-14"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(poster.waitForExistence(timeout: 5))
        XCTAssertTrue(poster.isHittable, "Return lost rank14")
        XCTAssertFalse(first.isHittable, "Return jumped to top")
        XCTAssertEqual(poster.frame.minY, beforeY, accuracy: 35, "Return shifted row offset")
        XCTAssertEqual(diagnostics.label, "items=60 requests=1", "Back must issue zero additional requests, not re-cache-fetch")
        XCTAssertFalse(app.progressIndicators["catalog-loading"].exists)
        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "recent-magnet-production-after-rank14-no-extra-requests"
        after.lifetime = .keepAlways
        add(after)
    }

    // Runs the shipping MissAVRankingView, real LazyVGrid, pagination and
    // NavigationStack. Only network/metadata and destination text are neutral
    // fixtures; this is executable UI coverage, not a source-string assertion.
    func testMissAVPagedReturnPreservesMovieOffsetAndQuery() {
        continueAfterFailure = false
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            let app = XCUIApplication()
            app.launchArguments = ["--poster-navigation-fixture", "--missav-scroll-fixture"]
            XCUIDevice.shared.orientation = orientation
            app.launch()
            let consent = app.buttons["我已满 18 岁，继续"]
            if consent.waitForExistence(timeout: 2) { consent.tap() }
            let diagnostics = app.staticTexts["missav-diagnostics"]
            XCTAssertTrue(diagnostics.waitForExistence(timeout: 10))
            let header = app.staticTexts["MissAV · 原站顺序"]
            XCTAssertTrue(header.isHittable)
            let initialHeaderY = header.frame.minY
            let more = app.buttons["missav-load-more"]
            for _ in 0..<24 where !more.isHittable { app.swipeUp() }
            XCTAssertTrue(more.isHittable, app.debugDescription)
            more.tap()
            expectation(for: NSPredicate(format: "label == %@", "period=weekly-hot items=48 requests=1"), evaluatedWith: diagnostics)
            waitForExpectations(timeout: 10)
            let poster = app.buttons["missav-movie-28"]
            let first = app.buttons["missav-movie-1"]
            for _ in 0..<40 {
                let window = app.windows.firstMatch
                if poster.isHittable && !first.isHittable && poster.frame.minY > 100 && poster.frame.maxY < window.frame.maxY - 40 { break }
                window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                    .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.60)))
            }
            XCTAssertTrue(poster.isHittable, app.debugDescription)
            XCTAssertFalse(first.isHittable)
            for round in 1...3 {
                let beforeY = poster.frame.minY
                poster.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28)).tap()
                XCTAssertTrue(app.staticTexts["missav-detail-28"].waitForExistence(timeout: 5))
                app.navigationBars.buttons.element(boundBy: 0).tap()
                XCTAssertTrue(poster.waitForExistence(timeout: 5))
                XCTAssertTrue(poster.isHittable, "Return lost page-2 rank28")
                XCTAssertFalse(first.isHittable, "Detail return jumped to top")
                XCTAssertEqual(poster.frame.minY, beforeY, accuracy: 35, "Return changed intra-row offset")
                XCTAssertEqual(diagnostics.label, "period=weekly-hot items=48 requests=1", "Back must not request/replace the ranking")
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = "missav-page2-return-\(round)-\(orientation.rawValue)"
                shot.lifetime = .keepAlways; add(shot)
            }
            // Pull-to-refresh is deliberate invalidation: return to page one.
            let weekly = app.buttons["本周热门"]
            // The chip bar exposes an accessibility proxy that can report hittable
            // before the vertical list reaches its top (reproducible on wide iPad).
            // Position by the original header geometry; do not spend the refresh
            // gesture merely scrolling the remaining rows into view.
            let window = app.windows.firstMatch
            for _ in 0..<40 {
                let remaining = initialHeaderY - header.frame.minY
                if remaining <= 2 { break }
                let distance = min(window.frame.height * 0.20, remaining)
                let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40))
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)))
            }
            XCTAssertTrue(header.isHittable, app.debugDescription)
            XCTAssertEqual(header.frame.minY, initialHeaderY, accuracy: 6, "Reach the true list top before pulling to refresh")
            XCTAssertTrue(weekly.isHittable, app.debugDescription)
            XCTAssertEqual(diagnostics.label, "period=weekly-hot items=48 requests=1")
            let scroll = app.scrollViews.firstMatch
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
                .press(forDuration: 0.1, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.90)))
            expectation(for: NSPredicate(format: "label == %@", "period=weekly-hot items=24 requests=2"), evaluatedWith: diagnostics)
            waitForExpectations(timeout: 10)
            XCTAssertTrue(first.isHittable, "Explicit refresh must reset to first page")
            app.buttons["今日热门"].tap()
            expectation(for: NSPredicate(format: "label == %@", "period=today-hot items=24 requests=3"), evaluatedWith: diagnostics)
            waitForExpectations(timeout: 10)
            XCTAssertTrue(first.isHittable)
            app.terminate()
        }
    }

    func testMissAVSwitchCancelsOldPagination() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--poster-navigation-fixture", "--missav-scroll-fixture", "--missav-slow-page"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate() }
        let consent = app.buttons["我已满 18 岁，继续"]
        if consent.waitForExistence(timeout: 2) { consent.tap() }
        let more = app.buttons["missav-load-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        for _ in 0..<24 where !more.isHittable { app.swipeUp() }
        XCTAssertTrue(more.isHittable)
        more.tap()
        let today = app.buttons["今日热门"]
        for _ in 0..<24 where !today.isHittable { app.swipeDown() }
        XCTAssertTrue(today.isHittable)
        today.tap()
        let diagnostics = app.staticTexts["missav-diagnostics"]
        expectation(for: NSPredicate(format: "label == %@", "period=today-hot items=24 requests=2"), evaluatedWith: diagnostics)
        waitForExpectations(timeout: 10)
        // Hold beyond the cancelled task's nominal delay; it must never append
        // old query rows or mutate the new query's next-page/loading state.
        let polluted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'items=48'"), object: diagnostics)
        polluted.isInverted = true
        wait(for: [polluted], timeout: 21)
        XCTAssertEqual(diagnostics.label, "period=today-hot items=24 requests=2")
        XCTAssertTrue(app.buttons["missav-movie-1"].isHittable)
    }

    func testUniformNeutralOriginalAndFrontPosterBounds() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--poster-size-fixture"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let consent = app.buttons["我已满 18 岁，继续"]
        if consent.waitForExistence(timeout: 2) { consent.tap() }
        for i in 0..<6 {
            let poster = app.descendants(matching: .any)["uniform-poster-\(i)"].firstMatch
            XCTAssertTrue(poster.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertEqual(poster.frame.width, 140, accuracy: 1)
            XCTAssertEqual(poster.frame.height, 200, accuracy: 1)
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "uniform-neutral-portrait-wrap-uncensored-HEYZO-western-FC2"
        shot.lifetime = .keepAlways
        add(shot)
        app.terminate()
    }

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
