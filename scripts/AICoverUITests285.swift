import XCTest

final class AICoverUITests285: XCTestCase {
    override func setUp() { continueAfterFailure = true }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = args; app.launch(); return app
    }
    func test1ManualEnhanceCompareViewer() {
        let app = launch(["--clear-ai-cache", "--mode", "manual"])
        let button = app.buttons["ai-cover-enhance-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 20), "manual 「AI 增强」 button")
        shot(app, "01-detail-manual-button")
        button.tap()
        let progress = app.buttons["ai-cover-progress"]
        if progress.waitForExistence(timeout: 10) { sleep(2); shot(app, "02-detail-progress") }
        let done = app.descendants(matching: .any)["ai-cover-compare"]
        XCTAssertTrue(done.waitForExistence(timeout: 900), "enhanced: badge + compare (simulator CPU inference)")
        sleep(1)
        shot(app, "03-detail-enhanced-badge")
        app.descendants(matching: .any)["detail-hero-artwork"].firstMatch.tap()
        let compare = app.descendants(matching: .any)["ai-cover-viewer-compare"]
        XCTAssertTrue(compare.waitForExistence(timeout: 10), "viewer compare control")
        sleep(1)
        shot(app, "04-viewer-enhanced")
        app.terminate()
        // Second launch: result comes from the persistent disk cache instantly; hold-to-compare state.
        let again = launch(["--mode", "manual", "--hold-original"])
        XCTAssertTrue(again.descendants(matching: .any)["ai-cover-compare"].waitForExistence(timeout: 15), "disk-cached result on relaunch")
        sleep(1)
        shot(again, "05-detail-hold-compare-original")
        again.terminate()
        let viewer = launch(["--mode", "manual", "--open-viewer", "--hold-original"])
        XCTAssertTrue(viewer.descendants(matching: .any)["ai-cover-viewer-compare"].waitForExistence(timeout: 15))
        sleep(1)
        shot(viewer, "06-viewer-hold-original")
    }
    func test2AutoProgress() {
        let app = launch(["--clear-ai-cache", "--mode", "auto"])
        XCTAssertTrue(app.buttons["ai-cover-progress"].waitForExistence(timeout: 20), "auto mode starts by itself")
        sleep(3)
        shot(app, "07-detail-auto-progress")
        app.terminate()
    }
    func test3HQNeverEnhancedAndSettings() {
        let app = launch(["--mode", "auto", "--hq"])
        sleep(3)
        XCTAssertFalse(app.buttons["ai-cover-enhance-button"].exists || app.buttons["ai-cover-progress"].exists, "HQ native cover: no AI control")
        shot(app, "08-detail-hq-native-no-ai")
        app.terminate()
        let s = launch(["--settings", "--mode", "auto"])
        XCTAssertTrue(s.segmentedControls["ai-cover-mode-setting"].waitForExistence(timeout: 10) || s.otherElements["ai-cover-mode-setting"].waitForExistence(timeout: 2))
        sleep(1)
        shot(s, "09-settings-ai-mode")
    }
}
