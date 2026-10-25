import XCTest

final class PlaybackResourceUITests260: XCTestCase {
    func screenshot(_ name: String) {
        let shot = XCUIApplication().screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testRestoredCardsOpenOneSheetWithoutQuery() {
        let app = XCUIApplication()
        app.launch()
        let pan = app.buttons["detail.card.115"]
        let online = app.buttons["detail.card.online"]
        let external = app.buttons["detail.card.external"]
        XCTAssertTrue(pan.waitForExistence(timeout: 8))
        XCTAssertTrue(online.exists)
        XCTAssertTrue(external.exists)
        XCTAssertEqual(app.buttons.matching(identifier: "detail.resource.115").count, 0)
        XCTAssertEqual(app.buttons.matching(identifier: "detail.resource.online").count, 0)
        XCTAssertTrue(app.staticTexts["播放资源:"].exists)
        XCTAssertTrue(pan.label.contains("115 原画"))
        XCTAssertTrue(pan.label.contains("打开 115 匹配资源"))
        XCTAssertTrue(pan.label.contains("选择播放文件"))
        XCTAssertTrue(online.label.contains("在线播放"))
        XCTAssertLessThan(abs(pan.frame.midY - online.frame.midY), 8)
        XCTAssertLessThan(pan.frame.maxX, online.frame.minX)
        screenshot("260-resource-card-row")

        pan.tap()
        XCTAssertTrue(app.staticTexts["fixture.115"].label.contains("retained"))
        XCTAssertEqual(app.buttons.matching(identifier: "online.close").count, 0)

        online.tap()
        XCTAssertTrue(app.buttons["online.close"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "online.close").count, 1)
        for source in ["jable", "missav", "av123", "memojav"] {
            XCTAssertEqual(app.staticTexts["online.state." + source].label, "未查询")
        }
        screenshot("260-online-sheet-not-queried")
        app.buttons["online.close"].tap()
        XCTAssertTrue(online.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "online.close").count, 0)

        app.buttons["fixture.width"].tap()
        XCTAssertTrue(online.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(online.frame.minY, pan.frame.maxY - 4)
        screenshot("260-narrow-wrap")
    }
}
