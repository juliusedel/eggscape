/// The three time-trial distances.
public enum RaceDistance: String, CaseIterable, Codable, Hashable, Sendable {
    case short
    case medium
    case long

    public var meters: Double {
        switch self {
        case .short: 150
        case .medium: 300
        case .long: 600
        }
    }
}

/// Where a run ends: at a finish line, or never (endless mode ends when the last egg breaks).
public enum Course: Codable, Hashable, Sendable {
    case timeTrial(RaceDistance)
    case endless

    /// Track length in meters, `nil` for endless.
    public var length: Double? {
        switch self {
        case let .timeTrial(distance): distance.meters
        case .endless: nil
        }
    }
}
