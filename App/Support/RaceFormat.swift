import Foundation

/// Formatting of race numbers for the HUD and results.
enum RaceFormat {
    /// Minutes, seconds and tenths (rounded down) with the region's separators, e.g. "0:42,3" in Germany and "0:42.3"
    /// in the US.
    static func time(_ seconds: Double) -> String {
        time(seconds, locale: .autoupdatingCurrent)
    }

    /// `time(_:)` with a fixed locale, for tests.
    static func time(_ seconds: Double, locale: Locale) -> String {
        // Whole tenths first: `Duration.seconds(42.3)` lies just below 42.3 and would be cut down to "0:42,2".
        let tenths = Int((max(seconds, 0) * 10).rounded(.down))
        return Duration.milliseconds(tenths * 100).formatted(
            .time(pattern: .minuteSecond(padMinuteToLength: 1, fractionalSecondsLength: 1)).locale(locale)
        )
    }

    /// Whole meters, e.g. "128".
    static func meters(_ value: Double) -> Int {
        Int(max(value, 0).rounded(.down))
    }
}

extension Duration {
    /// The duration in seconds as a floating-point number.
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) * 1e-18
    }
}
