import Foundation

/// Formatting of race numbers for the HUD and results.
enum RaceFormat {
    /// "0:42.3"
    static func time(_ seconds: Double) -> String {
        let tenths = Int((max(seconds, 0) * 10).rounded(.down))
        let minutes = tenths / 600
        let remainingTenths = tenths % 600
        return String(format: "%d:%02d.%d", minutes, remainingTenths / 10, remainingTenths % 10)
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
