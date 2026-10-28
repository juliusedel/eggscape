import XCTest

// A minimal helper that speaks fastlane snapshot's file protocol, written for this project instead of copying
// fastlane's generated SnapshotHelper (no third-party code in the repository):
// - snapshot writes the language, locale and launch arguments into ~/Library/Caches/tools.fastlane/ before each run;
// - the test saves PNGs as "<simulator name>-<screenshot name>.png" into the "screenshots" folder next to them,
//   where snapshot collects them.
// Outside snapshot (plain `make test-ui`) the files are missing and screenshots are attached to the test result.

@MainActor
enum Snapshot {
    private static var cacheDirectory: URL? {
        guard let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] else { return nil }
        return URL(fileURLWithPath: home).appendingPathComponent("Library/Caches/tools.fastlane")
    }

    /// Applies snapshot's language, locale and extra launch arguments to `app`.
    static func setUp(_ app: XCUIApplication) {
        guard let cache = cacheDirectory else { return }
        if let language = read(cache.appendingPathComponent("language.txt")) {
            app.launchArguments += ["-AppleLanguages", "(\(language))"]
            let locale = read(cache.appendingPathComponent("locale.txt")) ?? language.replacingOccurrences(
                of: "-",
                with: "_"
            )
            app.launchArguments += ["-AppleLocale", "\"\(locale)\""]
        }
        if let extra = read(cache.appendingPathComponent("snapshot-launch_arguments.txt")) {
            app.launchArguments += extra.split(separator: " ").map(String.init)
        }
        app.launchArguments += ["-FASTLANE_SNAPSHOT", "YES"]
    }

    /// Saves a screenshot for snapshot, or attaches it to the test result when not running under snapshot.
    static func take(_ name: String, in testCase: XCTestCase) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        testCase.add(attachment)

        guard let cache = cacheDirectory,
              var device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]
        else { return }
        // Parallel test runs call the simulator "Clone 1 of iPhone ...".
        if let range = device.range(of: #"Clone \d+ of "#, options: .regularExpression) {
            device.removeSubrange(range)
        }
        let directory = cache.appendingPathComponent("screenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("\(device)-\(name).png"))
    }

    private static func read(_ url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
