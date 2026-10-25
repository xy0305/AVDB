import XCTest

final class PlaybackResourceUITests258: XCTestCase {
    func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIApplication().screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func open(_ app: XCUIApplication) {
        app.buttons["detail.resource.online"].tap()
        XCTAssertTrue(app.buttons["online.close"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "online.close").count, 1)
    }
    func testPeerActionsSingleSheetAndPreservedState() {
        let app = XCUIApplication(); app.launchArguments = ["--saved"]; app.launch()
        let pan = app.buttons["detail.resource.115"], online = app.buttons["detail.resource.online"]
        XCTAssertTrue(pan.waitForExistence(timeout: 8)); XCTAssertTrue(online.exists)
        XCTAssertLessThan(abs(pan.frame.midY - online.frame.midY), 2)
        XCTAssertGreaterThanOrEqual(pan.frame.height, 44)
        XCTAssertGreaterThanOrEqual(online.frame.height, 44)
        XCTAssertLessThan(pan.frame.maxX, online.frame.minX + 2)
        screenshot("258-peer-actions")
        pan.tap(); XCTAssertTrue(app.staticTexts["fixture.115"].label.contains("retained"))
        open(app)
        XCTAssertEqual(app.switches.matching(identifier: "online.system-proxy-compatibility").count, 0)
        XCTAssertTrue(app.staticTexts["online.proxy-status"].label.contains("已开启"))
        for source in ["jable", "missav", "av123", "memojav"] {
            XCTAssertEqual(app.staticTexts["online.state." + source].label, "未查询")
        }
        screenshot("258-online-sheet-collapsed")
        // Explicit query is intercepted by the host's injected loader, never by URLSession/DNS.
        app.buttons["online.query.jable"].tap()
        let error = app.staticTexts["online.state.jable"]
        let predicate = NSPredicate(format: "label CONTAINS %@", "fixture.example.test")
        expectation(for: predicate, evaluatedWith: error)
        waitForExpectations(timeout: 8)
        XCTAssertTrue(error.label.contains("TLS")); XCTAssertTrue(error.label.contains("查询"))
        XCTAssertGreaterThan(error.frame.height, 20)
        screenshot("258-readable-typed-error")
        app.buttons["online.close"].tap(); XCTAssertTrue(online.waitForExistence(timeout: 5))
        open(app)
        XCTAssertTrue(app.staticTexts["online.state.jable"].label.contains("fixture.example.test"))
        XCTAssertEqual(app.switches.matching(identifier: "online.system-proxy-compatibility").count, 0)
        app.buttons["online.close"].tap()
        app.buttons["fixture.switch"].tap(); open(app)
        XCTAssertTrue(app.staticTexts["online.public-number"].label.contains("TEST-002"))
        XCTAssertEqual(app.staticTexts["online.state.jable"].label, "未查询")
        app.buttons["online.close"].tap()
    }
    func testAdvancedDefaultsPersistenceAndReturn() {
        let app = XCUIApplication(); app.launch(); open(app)
        XCTAssertTrue(app.staticTexts["online.proxy-status"].label.contains("关闭"))
        let advanced = app.buttons["online.advanced"]
        // Disclosure label is one native button with stable identifier.
        advanced.tap()
        let toggle = app.switches["online.system-proxy-compatibility"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5)); XCTAssertEqual(toggle.value as? String, "0")
        toggle.tap(); XCTAssertEqual(toggle.value as? String, "1")
        screenshot("258-advanced-user-enabled")
        app.buttons["online.close"].tap(); open(app)
        XCTAssertTrue(app.staticTexts["online.proxy-status"].label.contains("已开启"))
        XCTAssertEqual(app.switches.matching(identifier: "online.system-proxy-compatibility").count, 0)
        app.buttons["online.close"].tap()
        app.terminate(); app.launchArguments = ["--preserve"]; app.launch(); open(app)
        XCTAssertTrue(app.staticTexts["online.proxy-status"].label.contains("已开启"))
        app.buttons["online.close"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "online.close").count, 0)
        XCTAssertTrue(app.buttons["detail.resource.115"].exists)
    }
}
