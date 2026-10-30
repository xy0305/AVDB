import XCTest

final class LiveUITests287: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func launch(_ args: [String], landscape: Bool = false) -> XCUIApplication {
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        let app = XCUIApplication(); app.launchArguments = args; app.launch()
        if landscape { XCUIDevice.shared.orientation = .landscapeLeft }
        sleep(2)
        return app
    }

    func test01Portrait() {
        var app = launch(["--mode", "bilingual"]); XCTAssertTrue(app.otherElements["live.subtitle.rendered"].exists || app.staticTexts.count > 0)
        shot(app, "01-portrait-bilingual"); app.terminate()
        app = launch(["--mode", "bilingual", "--chrome"]); shot(app, "02-portrait-bilingual-chrome-lifted"); app.terminate()
        app = launch(["--mode", "japanese"]); shot(app, "03-portrait-japanese"); app.terminate()
        app = launch(["--mode", "chinese"]); shot(app, "04-portrait-chinese"); app.terminate()
        app = launch(["--mode", "bilingual", "--partial"]); shot(app, "05-portrait-partial-streaming-ja"); app.terminate()
        app = launch(["--mode", "bilingual", "--pending"]); shot(app, "06-portrait-ja-ready-zh-pending"); app.terminate()
    }

    func test02Landscape() {
        var app = launch(["--mode", "bilingual"], landscape: true); shot(app, "07-landscape-bilingual"); app.terminate()
        app = launch(["--mode", "bilingual", "--chrome"], landscape: true); shot(app, "08-landscape-bilingual-chrome-lifted")
        let menu = app.buttons["player.live.subtitle.menu"]
        if menu.waitForExistence(timeout: 5) { menu.tap(); sleep(1); shot(app, "09-landscape-mode-menu") }
        app.terminate()
        app = launch(["--mode", "chinese", "--font", "28", "--position", "0.55"], landscape: true); shot(app, "10-landscape-chinese-font28-mid"); app.terminate()
    }

    func test03MenuSettingsStatus() {
        var app = launch(["--mode", "bilingual", "--chrome"])
        let menu = app.buttons["player.live.subtitle.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap(); sleep(1); shot(app, "11-portrait-mode-menu")
        let japanese = app.buttons["日文"]
        if japanese.waitForExistence(timeout: 3) { japanese.tap(); sleep(1); shot(app, "12-portrait-switched-to-japanese") }
        app.terminate()
        app = launch(["--mode", "bilingual", "--settings"]); sleep(1); shot(app, "13-settings-sheet"); app.terminate()
        app = launch(["--mode", "bilingual", "--editing"]); shot(app, "14-position-editing"); app.terminate()
        app = launch(["--mode", "bilingual", "--thermal"]); shot(app, "15-thermal-paused-notice"); app.terminate()
        app = launch(["--mode", "bilingual", "--loading", "--chrome"]); shot(app, "16-loading-model"); app.terminate()
    }

    func test04Build288Loading() {
        var app = launch(["--mode", "bilingual", "--staged"]); shot(app, "17-288-small-running-turbo-compiling"); app.terminate()
        app = launch(["--mode", "bilingual", "--failed"])
        XCTAssertTrue(app.buttons["live.subtitle.retry"].waitForExistence(timeout: 5))
        shot(app, "18-288-load-failed-retry"); app.terminate()
        app = launch(["--mode", "bilingual", "--staged", "--settings"]); sleep(1)
        app.swipeUp(); sleep(1); shot(app, "19-288-settings-model-status-copylog"); app.terminate()
        app = launch(["--mode", "bilingual", "--failed", "--settings"]); sleep(1)
        app.swipeUp(); sleep(1); shot(app, "20-288-settings-failed-retry"); app.terminate()
    }
}
