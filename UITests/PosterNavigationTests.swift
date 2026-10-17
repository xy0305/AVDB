import XCTest

final class PosterNavigationTests: XCTestCase {
    func testLongDetailTitleThreeLinesExpandsAndPersistsVisibility() {
        verifyReadableDetail(accessibilitySize: false)
    }

    func testAccessibleDetailTitleAndLandscapeActions() {
        verifyReadableDetail(accessibilitySize: true)
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
        if visibility.exists && visibility.value as? String == "0" { visibility.tap() }
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
        let landscape = XCTAttachment(screenshot: app.screenshot())
        landscape.name = "192-neutral-original-hero-landscape"
        landscape.lifetime = .keepAlways; add(landscape)
        XCTAssertTrue(app.buttons["返回"].isHittable)
        XCUIDevice.shared.orientation = .portrait
        app.buttons["返回"].tap()
        XCTAssertTrue(visibility.waitForExistence(timeout: 5)); visibility.tap()
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
        visibility.tap()
        XCTAssertEqual(visibility.value as? String, "1")
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
        app.buttons["subtitle.reset"].tap()
        app.buttons["subtitle.disable"].tap()
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
