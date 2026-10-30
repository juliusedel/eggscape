import XCTest

/// The tutorial of a new install (`-first-launch`): "Überspringen" skips the steps but not the name, which the
/// settings then show.
final class TutorialUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testSkipLeadsToTheNameStep() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-first-launch"]
        app.launch()

        let skip = app.buttons["tutorial.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 15))
        XCTAssertGreaterThanOrEqual(skip.frame.height, 44, "the skip button must be easy to hit")
        skip.tap()

        // The name step has nothing left to skip.
        let field = app.textFields["tutorial.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tutorial.skip"].exists)
        field.tap()
        field.typeText("  Mia ")
        let done = app.buttons["tutorial.done"]
        XCTAssertTrue(done.isHittable, "the keyboard must not hide the button")
        done.tap()

        XCTAssertTrue(app.buttons["timeTrial.start"].waitForExistence(timeout: 10))
        app.buttons["toolbar.settings"].tap()
        let name = app.textFields["settings.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Mia")
    }
}
