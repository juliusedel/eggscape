import XCTest

final class LaunchTests: XCTestCase {
    @MainActor
    func testStartScreenAppears() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["start.title"].waitForExistence(timeout: 10))
    }
}
