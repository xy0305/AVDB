import XCTest

final class AICoverUITests286: XCTestCase {
    override func setUp() { continueAfterFailure = true }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = args; app.launch(); return app
    }
    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    /// Nothing AI-related may sit above the metadata row (i.e. over the cover art / top chrome).
    private func assertBelowMetadata(_ app: XCUIApplication, _ ids: [String], _ file: StaticString = #filePath, _ line: UInt = #line) {
        let meta = el(app, "portrait-hero-metadata")
        XCTAssertTrue(meta.waitForExistence(timeout: 10), "metadata row", file: file, line: line)
        for id in ids where el(app, id).exists {
            XCTAssertGreaterThanOrEqual(el(app, id).frame.minY, meta.frame.maxY - 1, "\(id) must sit below the metadata row", file: file, line: line)
        }
    }
    func test1ManualEnhanceCompareViewer() {
        let app = launch(["--clear-ai-cache", "--mode", "manual"])
        let button = app.buttons["ai-cover-enhance-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 20), "manual 「AI 增强」 button")
        assertBelowMetadata(app, ["ai-cover-enhance-button"])
        shot(app, "01-detail-manual-button")
        button.tap()
        let progress = app.buttons["ai-cover-progress"]
        if progress.waitForExistence(timeout: 10) { sleep(2); assertBelowMetadata(app, ["ai-cover-progress"]); shot(app, "02-detail-progress") }
        let compare = el(app, "ai-cover-compare")
        XCTAssertTrue(compare.waitForExistence(timeout: 900), "enhanced: badge + compare (simulator CPU inference)")
        shot(app, "03-detail-enhanced-hint")          // 「长按封面也可对比原图」 shows for ~1.6 s
        sleep(3)
        assertBelowMetadata(app, ["ai-cover-badge", "ai-cover-compare"])
        shot(app, "04-detail-enhanced-badge")
        // Real long-press on the cover art: compare fires, the viewer does NOT open.
        let art = el(app, "detail-hero-artwork")
        art.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).press(forDuration: 1.2)
        sleep(1)
        XCTAssertEqual(el(app, "compare-events").label, "1", "long-press on the cover shows the original")
        XCTAssertEqual(el(app, "viewer-opens").label, "0", "long-press must not open the viewer")
        XCTAssertFalse(el(app, "ai-cover-viewer-close").exists)
        // Plain tap on the cover opens the fullscreen viewer.
        art.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertTrue(el(app, "ai-cover-viewer-compare").waitForExistence(timeout: 10), "viewer compare control")
        sleep(1)
        let image = el(app, "ai-cover-viewer-image"), bar = el(app, "ai-cover-viewer-compare"), close = el(app, "ai-cover-viewer-close")
        XCTAssertLessThanOrEqual(close.frame.maxY, image.frame.minY + 1, "close button above the image region")
        XCTAssertGreaterThanOrEqual(bar.frame.minY, image.frame.maxY - 1, "compare bar below the image region")
        shot(app, "05-viewer-enhanced")
        app.terminate()
        // Relaunch: disk-cached result instantly; hold-to-compare (original) state.
        let again = launch(["--mode", "manual", "--hold-original"])
        XCTAssertTrue(el(again, "ai-cover-compare").waitForExistence(timeout: 15), "disk-cached result on relaunch")
        sleep(1)
        shot(again, "06-detail-hold-compare-original")
        again.terminate()
        let viewer = launch(["--mode", "manual", "--open-viewer", "--hold-original"])
        XCTAssertTrue(el(viewer, "ai-cover-viewer-compare").waitForExistence(timeout: 15))
        sleep(1)
        shot(viewer, "07-viewer-hold-original")
    }
    func test2AutoProgress() {
        let app = launch(["--clear-ai-cache", "--mode", "auto"])
        XCTAssertTrue(app.buttons["ai-cover-progress"].waitForExistence(timeout: 20), "auto mode starts by itself")
        sleep(3)
        assertBelowMetadata(app, ["ai-cover-progress"])
        shot(app, "08-detail-auto-progress")
        app.terminate()
        let v = launch(["--mode", "manual", "--clear-ai-cache", "--open-viewer"])
        XCTAssertTrue(el(v, "ai-cover-viewer-enhance").waitForExistence(timeout: 15), "viewer manual 「AI 增强」")
        sleep(1)
        shot(v, "09-viewer-manual-button")
        el(v, "ai-cover-viewer-enhance").tap()
        if el(v, "ai-cover-viewer-progress").waitForExistence(timeout: 10) { sleep(2); shot(v, "10-viewer-progress") }
        v.terminate()
    }
    func test3HQNeverEnhancedAndSettings() {
        let app = launch(["--mode", "auto", "--hq"])
        sleep(3)
        XCTAssertFalse(app.buttons["ai-cover-enhance-button"].exists || app.buttons["ai-cover-progress"].exists, "HQ native cover: no AI control")
        shot(app, "11-detail-hq-native-no-ai")
        app.terminate()
        let s = launch(["--settings", "--mode", "auto"])
        XCTAssertTrue(s.segmentedControls["ai-cover-mode-setting"].waitForExistence(timeout: 10) || s.otherElements["ai-cover-mode-setting"].waitForExistence(timeout: 2))
        sleep(1)
        shot(s, "12-settings-ai-mode")
    }
}
