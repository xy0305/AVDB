import XCTest

/// Build 290 screenshots: settings (云端增强图 / 本地缓存上限 / 仅 Wi‑Fi 上传 / 清除缓存 / stats / 507 note) and the hero
/// against a local mock Worker: cloud hit, cloud loading (slow server), miss → local enhancement → background upload.
final class AICoverUITests290: XCTestCase {
    override func setUp() { continueAfterFailure = true }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private var fast: String { ProcessInfo.processInfo.environment["MOCK_FAST"] ?? "http://127.0.0.1:8791" }
    private var slow: String { ProcessInfo.processInfo.environment["MOCK_SLOW"] ?? "http://127.0.0.1:8792" }
    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = args; app.launch(); return app
    }
    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    func test1Settings() {
        let s = launch(["--settings", "--mode", "auto", "--reset-cloud", "--seed-stats", "--seed-cache", "--clear-ai-cache", "--cloud-base", fast])
        XCTAssertTrue(el(s, "ai-cover-cloud-toggle").waitForExistence(timeout: 15), "云端增强图 toggle")
        sleep(2)
        XCTAssertTrue(el(s, "ai-cover-cache-cap").exists && el(s, "ai-cover-cloud-wifi").exists && el(s, "ai-cover-cache-clear").exists)
        shot(s, "01-290-settings-cloud")
        s.swipeUp(); sleep(1)
        shot(s, "02-290-settings-cloud-stats-diagnostics")
        s.terminate()
        let q = launch(["--settings", "--mode", "auto", "--reset-cloud", "--seed-stats", "--quota", "--cloud-base", fast])
        XCTAssertTrue(el(q, "ai-cover-cloud-quota").waitForExistence(timeout: 15), "507 note")
        q.swipeUp(); sleep(1)
        shot(q, "03-290-settings-507-note")
        q.terminate()
        let m = launch(["--settings", "--mode", "auto", "--reset-cloud", "--cloud-base", fast])
        let cap = el(m, "ai-cover-cache-cap")
        XCTAssertTrue(cap.waitForExistence(timeout: 15))
        cap.tap(); sleep(1)
        shot(m, "04-290-settings-cache-cap-menu")
    }

    func test2CloudHit() {
        let app = launch(["--mode", "auto", "--clear-ai-cache", "--reset-cloud", "--cloud-base", fast])
        let badge = el(app, "ai-cover-badge")
        XCTAssertTrue(badge.waitForExistence(timeout: 8), "cloud hit shows the enhanced cover without local inference")
        sleep(1)
        shot(app, "05-290-detail-cloud-hit")
    }

    func test3CloudLoading() {
        let app = launch(["--mode", "auto", "--clear-ai-cache", "--reset-cloud", "--defer-prepare", "3", "--cloud-base", slow])
        XCTAssertTrue(el(app, "portrait-hero-metadata").waitForExistence(timeout: 10))
        let p = el(app, "ai-cover-progress")
        XCTAssertTrue(p.waitForExistence(timeout: 8), "cloud loading chip")
        shot(app, "06-290-detail-cloud-loading")
        XCTAssertTrue(el(app, "ai-cover-badge").waitForExistence(timeout: 240), "slow cloud → enhanced cover (cloud hit, or silent local fallback if the HEAD budget is exceeded)")
    }

    func test4MissLocalUpload() {
        let app = launch(["--mode", "auto", "--clear-ai-cache", "--reset-cloud", "--miss", "--cloud-base", fast])
        let p = el(app, "ai-cover-progress")
        if p.waitForExistence(timeout: 20) { sleep(3); shot(app, "07-290-detail-miss-local-enhance") }
        XCTAssertTrue(el(app, "ai-cover-badge").waitForExistence(timeout: 240), "local enhancement after a cloud miss")
        sleep(8)          // background upload (utility) → the mock server logs the PUT
        shot(app, "08-290-detail-miss-enhanced-uploaded")
        app.terminate()
        let s = launch(["--settings", "--mode", "auto", "--cloud-base", fast])
        XCTAssertTrue(el(s, "ai-cover-cloud-stats").waitForExistence(timeout: 15))
        s.swipeUp(); sleep(1)
        shot(s, "09-290-settings-after-upload")
    }
}
