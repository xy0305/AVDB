import XCTest

final class ResumeUITests288: XCTestCase {
    override func setUp() { continueAfterFailure = true; XCUIDevice.shared.orientation = .portrait }
    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func launch(_ scene: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--scene", scene]; app.launch(); sleep(2); return app
    }
    func test01() {
        let dev = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "sim"
        var app = launch("before"); shot("01-before-287-\(dev)"); app.terminate()
        app = launch("after"); shot("02-after-288-\(dev)")
        let pill = app.buttons["portrait-hero-play"]
        if pill.waitForExistence(timeout: 5) {
            // One row: the pill's vertical centre is level with the icon group.
            pill.press(forDuration: 1.2); sleep(1); shot("03-after-288-longpress-menu-\(dev)")
            XCTAssertTrue(app.buttons["从头播放"].exists)
        }
        app.terminate()
        app = launch("widths"); shot("04-after-288-narrow-widths-\(dev)")
        for w in [339, 354, 366] {
            let p = app.otherElements["pill-\(w)"].exists ? app.otherElements["pill-\(w)"] : app.descendants(matching: .any)["pill-\(w)"]
            if p.exists { print("PILL288 \(w) frame=\(p.frame)") }
        }
        app.terminate()
    }
}
