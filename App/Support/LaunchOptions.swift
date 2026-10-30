import Foundation

/// Command-line switches for UI tests and App Store screenshots.
struct LaunchOptions: Sendable {
    /// `-ui-testing`: fresh data on every launch, tutorial already seen, white background, fixed seeds.
    let isUITesting: Bool
    /// `-first-launch`: fresh data on every launch with nothing set, like a new install: the tutorial with its name
    /// step appears and the background is the default (the camera). For the tutorial's UI test and for trying a first
    /// launch without deleting the app and its data; may be combined with `-ui-testing`, which then only fixes seeds.
    let simulatesFirstLaunch: Bool
    /// `--screenshot-mode <scene>`: renders a staged, deterministic scene for App Store screenshots.
    let screenshotScene: String?

    init(arguments: [String]) {
        isUITesting = arguments.contains("-ui-testing")
        simulatesFirstLaunch = arguments.contains("-first-launch")
        if let index = arguments.firstIndex(of: "--screenshot-mode"), arguments.indices.contains(index + 1) {
            screenshotScene = arguments[index + 1]
        } else {
            screenshotScene = nil
        }
    }

    static let current = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)

    /// Tests and screenshots must not depend on what was played before.
    var usesEphemeralData: Bool {
        isUITesting || simulatesFirstLaunch || screenshotScene != nil
    }

    /// Seed for new races: fixed under test so runs are reproducible.
    func raceSeed() -> UInt64 {
        usesEphemeralData ? 0xE665_CA9E : .random(in: .min ... .max)
    }

    /// A defaults domain that is wiped on every launch.
    static func ephemeralDefaults() -> UserDefaults {
        let name = "de.juliusedel.eggscape.ephemeral"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
