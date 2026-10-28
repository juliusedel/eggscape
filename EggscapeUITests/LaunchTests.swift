import XCTest

final class LaunchTests: XCTestCase {
    @MainActor
    func testTabsAppear() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["timeTrial.start"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.tabBars.buttons.count >= 4 || app.buttons["endless.start"].exists)
    }
}
