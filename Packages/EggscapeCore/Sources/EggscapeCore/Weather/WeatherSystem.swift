/// What the weather does to the egg during one simulation step.
public struct WeatherImpact: Sendable, Equatable {
    /// Continuous acceleration, e.g. wind.
    public var force: SIMD2<Double> = .zero
    /// Multiplier on the bowl damping.
    public var dampingScale = 1.0
    /// Multiplier on footstep kicks.
    public var footstepScale = 1.0
    /// Sudden pushes during this step.
    public var kicks: [Kick] = []

    public init() {}
}

/// The weather a runner experiences: clear skies for now.
public struct WeatherSystem: Sendable {
    public let schedule: WeatherSchedule
    public let config: GameConfig

    public init(schedule: WeatherSchedule, config: GameConfig) {
        self.schedule = schedule
        self.config = config
    }

    public var conditions: WeatherConditions {
        .clear
    }

    mutating func step(
        time _: Double,
        from _: Double,
        to _: Double,
        dt _: Double,
        rng _: inout SplitMix64,
        events _: inout [RunEvent]
    ) -> WeatherImpact {
        WeatherImpact()
    }
}

/// The race's weather plan, derived from the race seed.
public struct WeatherSchedule: Sendable, Equatable {
    public let seed: UInt64

    public init(seed: UInt64) {
        self.seed = seed
    }

    public static let clear = WeatherSchedule(seed: 0)
}

/// The weather at one point of the track.
public struct WeatherConditions: Sendable, Equatable, Hashable {
    public static let clear = WeatherConditions()
}
