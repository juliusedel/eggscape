/// The three time-trial distances.
public enum RaceDistance: String, CaseIterable, Codable, Hashable, Sendable {
    case short
    case medium
    case long

    /// The lengths of a real egg-and-spoon race. At the running speed of 3 m/s they take about 5, 17 and 34 seconds.
    ///
    /// Personal bests, leaderboards and the multiplayer wire format know a distance by its name, so a new length
    /// needs a new `EggscapeCore.protocolVersion`, and the app must not count best times run over the old one.
    public var meters: Double {
        switch self {
        case .short: 15
        case .medium: 50
        case .long: 100
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
