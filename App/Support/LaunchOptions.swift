import Foundation

/// Command-line switches for UI tests and App Store screenshots.
struct LaunchOptions: Sendable {
    /// `-ui-testing`: fresh data on every launch, tutorial already seen, fixed seeds.
    let isUITesting: Bool
    /// `--screenshot-mode <scene>`: renders a staged, deterministic scene for App Store screenshots.
    let screenshotScene: String?

    init(arguments: [String]) {
        isUITesting = arguments.contains("-ui-testing")
        if let index = arguments.firstIndex(of: "--screenshot-mode"), arguments.indices.contains(index + 1) {
            screenshotScene = arguments[index + 1]
        } else {
            screenshotScene = nil
        }
    }

    static let current = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)

    /// Tests and screenshots must not depend on what was played before.
    var usesEphemeralData: Bool {
        isUITesting || screenshotScene != nil
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
