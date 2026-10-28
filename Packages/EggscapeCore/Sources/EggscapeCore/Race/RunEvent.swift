/// Something that happened during a simulation step. The app turns events into animation, sound and haptics;
/// the simulation itself never depends on them.
public enum RunEvent: Sendable, Equatable {
    /// A footstep of the runner.
    case footstep(sprinting: Bool)
    /// A sudden push on the egg.
    case kick(Kick)
    /// The runner splashed through a puddle.
    case puddle
    /// Lightning strikes in `lightningWarning` seconds.
    case lightningWarning
    case lightningStrike
    /// The runner entered a stretch of different weather.
    case weatherChanged(WeatherConditions)
    /// The egg rolled over the rim at `position`; `eggsLeft` already counts the loss.
    case eggDropped(position: SIMD2<Double>, eggsLeft: Int)
    /// A fresh egg lies in the bowl and the runner starts again.
    case newEgg
    /// The finish line was crossed after `time` seconds.
    case finished(time: Double)
    /// The last egg broke after `meters` meters.
    case runOver(meters: Double)
}

/// A sudden push on the egg: a velocity change in bowl units per second.
public struct Kick: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        case footstep
        case puddle
        case lightning
    }

    public var velocity: SIMD2<Double>
    public var source: Source

    public init(_ velocity: SIMD2<Double>, _ source: Source) {
        self.velocity = velocity
        self.source = source
    }
}
