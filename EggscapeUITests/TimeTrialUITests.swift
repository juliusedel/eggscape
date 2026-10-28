import XCTest

/// Drives a complete short time trial in the Simulator, where the egg is steered with a finger instead of tilting.
final class TimeTrialUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testFullShortTimeTrialWithFingerSteering() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing"]
        app.launch()

        let start = app.buttons["timeTrial.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()

        // Without motion sensors the calibration screen offers finger steering instead.
        let go = app.buttons["calibration.calibrate"]
        XCTAssertTrue(go.waitForExistence(timeout: 10))
        go.tap()

        // Wait for the countdown, then nudge the egg around with a finger and let go again.
        XCTAssertTrue(app.buttons["hud.pause"].waitForExistence(timeout: 10))
        let bowl = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.47))
        bowl.press(forDuration: 0.4, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.56, dy: 0.45)))
        bowl.press(forDuration: 0.4, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)))

        // 150 m at 3 m/s take a little over 50 seconds.
        let results = app.staticTexts["results.title"]
        XCTAssertTrue(results.waitForExistence(timeout: 120))
        XCTAssertTrue(app.staticTexts["results.time"].exists, "a level egg must survive the short course")

        app.buttons["results.done"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 10))
    }
}
