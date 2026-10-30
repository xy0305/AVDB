import XCTest

final class RecUITests281: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        return app
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func firstCard(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'rec.card.'")).firstMatch
    }

    func test1FeedHeroAndCarousels() {
        let app = launch(["--screen", "feed"])
        XCTAssertTrue(element(app, "rec.hero").waitForExistence(timeout: 30), app.debugDescription)
        sleep(1)
        shot(app, "01-feed-hero")
        XCTAssertTrue(firstCard(app).waitForExistence(timeout: 10))
        app.swipeUp()
        sleep(1)
        shot(app, "02-feed-carousels")
        app.swipeUp()
        sleep(1)
        shot(app, "02b-feed-carousels-more")
    }

    func test2LongPressMenuAndFeedback() {
        let app = launch(["--screen", "feed"])
        XCTAssertTrue(element(app, "rec.hero").waitForExistence(timeout: 30))
        app.swipeUp()
        let card = firstCard(app)
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.press(forDuration: 1.4)
        let notInterested = app.buttons["不感兴趣"].firstMatch
        // A busy CI simulator occasionally drops the first long press; retry once.
        if !notInterested.waitForExistence(timeout: 5) { card.press(forDuration: 2.0) }
        XCTAssertTrue(notInterested.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label BEGINSWITH '少推'")).firstMatch.exists)
        sleep(1)
        shot(app, "05-long-press-menu")
        notInterested.tap()
        let toast = element(app, "rec.toast")
        let toastText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '不再推荐'")).firstMatch
        let shown = toast.waitForExistence(timeout: 8) || toastText.exists
        shot(app, "06-feedback-toast")
        XCTAssertTrue(shown, app.debugDescription)
    }

    func test3Preferences() {
        let app = launch(["--screen", "prefs"])
        XCTAssertTrue(element(app, "rec.prefs").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["星野ひかり"].firstMatch.waitForExistence(timeout: 30), app.debugDescription)
        sleep(1)
        shot(app, "03-preferences")
        app.swipeUp()
        sleep(1)
        shot(app, "03b-preferences-more")
        let reset = element(app, "rec.prefs.reset")
        for _ in 0..<4 where !reset.isHittable { app.swipeUp() }
        reset.tap()
        sleep(1)
        shot(app, "03c-preferences-reset-confirm")
    }

    func test4ColdStart() {
        let app = launch(["--screen", "feed", "--rec-cold"])
        XCTAssertTrue(element(app, "rec.coldstart").waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(element(app, "rec.hero").waitForExistence(timeout: 30))
        sleep(1)
        shot(app, "04-cold-start")
    }

    func test5SkeletonDarkAndMine() {
        let skeleton = launch(["--screen", "feed", "--rec-slow"])
        XCTAssertTrue(element(skeleton, "rec.skeleton").waitForExistence(timeout: 10), skeleton.debugDescription)
        shot(skeleton, "07-loading-skeleton")
        skeleton.terminate()
        let dark = launch(["--screen", "feed", "--dark"])
        XCTAssertTrue(element(dark, "rec.hero").waitForExistence(timeout: 30))
        sleep(1)
        shot(dark, "08-feed-dark")
        dark.terminate()
        let mine = launch(["--screen", "mine"])
        XCTAssertTrue(element(mine, "me.rec.all").waitForExistence(timeout: 30))
        sleep(2)
        shot(mine, "09-mine-section")
        mine.terminate()
        let big = launch(["--screen", "feed", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        XCTAssertTrue(element(big, "rec.hero").waitForExistence(timeout: 30))
        sleep(1)
        shot(big, "10-feed-large-dynamic-type")
    }
}
