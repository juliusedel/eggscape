import XCTest

/// Captures the App Store screenshots from the staged scenes (`--screenshot-mode`). Run through `make screenshots`
/// (fastlane snapshot); run directly, the images are attached to the test result.
final class ScreenshotTests: XCTestCase {
    private let scenes: [(name: String, scene: String, ready: String)] = [
        ("01-start", "start", "timeTrial.start"),
        ("02-calibration", "calibration", "calibration.calibrate"),
        ("03-sunny", "run-sunny", "hud.pause"),
        ("04-rain", "run-rain", "hud.pause"),
        ("05-storm", "run-storm", "hud.pause"),
        ("06-lobby", "lobby", "nearby.start"),
        ("07-results", "results", "results.title"),
        ("08-shop", "shop", "shop.balance"),
    ]

    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testCaptureScreenshots() {
        for entry in scenes {
            let app = XCUIApplication()
            Snapshot.setUp(app)
            app.launchArguments += ["--screenshot-mode", entry.scene]
            app.launch()
            let ready = app.descendants(matching: .any)[entry.ready]
            XCTAssertTrue(ready.waitForExistence(timeout: 20), "\(entry.scene) did not appear")
            // Let animations, particles and the countdown settle.
            Thread.sleep(forTimeInterval: entry.scene.hasPrefix("run") ? 2.5 : 1.2)
            Snapshot.take(entry.name, in: self)
            app.terminate()
        }
    }
}
