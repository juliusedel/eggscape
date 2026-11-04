import Foundation

/// Formatting of race numbers for the HUD and results.
enum RaceFormat {
    /// No real run gets anywhere near this, in seconds or meters; it only keeps corrupt input, such as a number from a
    /// modified phone, from trapping the conversion to `Int`.
    private static let largestShown = 1_000_000.0

    /// Minutes, seconds and tenths (rounded down) with the region's separators, e.g. "0:42,3" in Germany and "0:42.3"
    /// in the US.
    static func time(_ seconds: Double) -> String {
        time(seconds, locale: .autoupdatingCurrent)
    }

    /// `time(_:)` with a fixed locale, for tests.
    static func time(_ seconds: Double, locale: Locale) -> String {
        // Whole tenths first: `Duration.seconds(42.3)` lies just below 42.3 and would be cut down to "0:42,2".
        let tenths = Int((shown(seconds) * 10).rounded(.down))
        return Duration.milliseconds(tenths * 100).formatted(
            .time(pattern: .minuteSecond(padMinuteToLength: 1, fractionalSecondsLength: 1)).locale(locale)
        )
    }

    /// Whole meters, e.g. "128".
    static func meters(_ value: Double) -> Int {
        Int(shown(value).rounded(.down))
    }

    /// `value` as it can be shown: from 0 to `largestShown`, and 0 for NaN.
    private static func shown(_ value: Double) -> Double {
        value.isNaN ? 0 : min(max(value, 0), largestShown)
    }
}

extension Duration {
    /// The duration in seconds as a floating-point number.
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) * 1e-18
    }
}
