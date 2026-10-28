public extension WeatherSchedule {
    /// One gust of wind in race time. It swells over `ramp` seconds, holds its peak, then dies down over `decay`.
    /// Both edges are eased, so a gust never jerks the egg; it just leans on it harder and harder.
    struct Gust: Hashable, Sendable {
        /// Race time when the gust starts to swell, in seconds since the start.
        public var start: Double
        public var ramp: Double
        public var hold: Double
        public var decay: Double
        /// Peak lateral force at full intensity in bowl units per second², always positive (see `direction`).
        public var peak: Double
        /// `1` when the gust blows to the right, `-1` when it blows to the left.
        public var direction: Double

        /// Race time when the gust has died down.
        public var end: Double {
            start + ramp + hold + decay
        }

        /// The gust's shape: 0 before and after it, easing up to 1 while it holds.
        public func envelope(at time: Double) -> Double {
            let elapsed = time - start
            guard elapsed > 0, elapsed < ramp + hold + decay else {
                return 0
            }
            if elapsed < ramp {
                return smoothstep(elapsed / ramp)
            }
            let fading = elapsed - ramp - hold
            return fading > 0 ? smoothstep(1 - fading / decay) : 1
        }

        /// Signed lateral force at `time` at full intensity: positive pushes the egg to the right.
        public func force(at time: Double) -> Double {
            direction * peak * envelope(at: time)
        }
    }

    /// One lightning strike in race time. Every phone of a race flashes at the same moment, and the jolt has the same
    /// direction everywhere.
    struct LightningStrike: Hashable, Sendable {
        /// Race time of the flash and the jolt, in seconds since the start.
        public var time: Double
        /// When the warning flicker starts, `GameConfig.lightningWarning` seconds before the strike.
        public var warningTime: Double
        /// Unit vector of the jolt the strike gives the egg.
        public var direction: SIMD2<Double>
    }
}

/// Eased 0 → 1 with zero slope at both ends, so forces built on it change without kinks.
private func smoothstep(_ value: Double) -> Double {
    let clamped = min(max(value, 0), 1)
    return clamped * clamped * (3 - 2 * clamped)
}

/// Every timeline moves forward by at least this much per item, even with degenerate tunables such as a `0 ... 0`
/// range, so loops that walk a timeline always terminate.
private let minimumAdvance = 0.001

/// Generates the gusts of a race one after another from the schedule's gust stream.
///
/// The direction of a gust depends on all flips before it, so the timeline cannot be sampled at random points; it is
/// walked from the start instead, which is cheap (one gust every few seconds). Every gust takes the same four draws,
/// so the timeline depends on the seed and the wind tunables only.
struct GustTimeline: Sendable, Equatable {
    private var rng: SplitMix64
    /// The end of the last gust, where the next calm gap begins.
    private var calmSince = 0.0
    /// The direction of the next gust.
    private var direction: Double
    private let ramp: Double
    private let hold: ClosedRange<Double>
    private let decay: Double
    private let gap: ClosedRange<Double>
    private let force: ClosedRange<Double>
    private let flipChance: Double

    init(rng: SplitMix64, config: GameConfig) {
        var rng = rng
        direction = rng.chance(0.5) ? 1 : -1
        self.rng = rng
        ramp = max(config.gustRamp, 0)
        hold = config.gustHold
        decay = max(config.gustDecay, 0)
        gap = config.gustGap
        force = config.windForce
        flipChance = config.windFlipChance
    }

    mutating func next() -> WeatherSchedule.Gust {
        let start = calmSince + max(rng.uniform(gap), minimumAdvance)
        let hold = max(rng.uniform(hold), 0)
        let peak = rng.uniform(force)
        let gust = WeatherSchedule.Gust(
            start: start,
            ramp: ramp,
            hold: hold,
            decay: decay,
            peak: peak,
            direction: direction
        )
        if rng.chance(flipChance) {
            direction = -direction
        }
        calmSince = gust.end
        return gust
    }
}

/// Generates the lightning strikes of a race one after another, `lightningInterval` apart, two draws per strike.
struct LightningTimeline: Sendable, Equatable {
    private var rng: SplitMix64
    private var time = 0.0
    private let interval: ClosedRange<Double>
    private let warning: Double

    init(rng: SplitMix64, config: GameConfig) {
        self.rng = rng
        interval = config.lightningInterval
        warning = max(config.lightningWarning, 0)
    }

    mutating func next() -> WeatherSchedule.LightningStrike {
        time += max(rng.uniform(interval), minimumAdvance)
        let direction = rng.direction()
        return WeatherSchedule.LightningStrike(time: time, warningTime: time - warning, direction: direction)
    }
}

/// Generates the puddle positions along the track one after another, `puddleSpacing` apart, one draw per puddle.
///
/// The positions are the same whatever the weather; the weather only decides which puddles hold water.
struct PuddleTrack: Sendable, Equatable {
    private var rng: SplitMix64
    private var meters = 0.0
    private let spacing: ClosedRange<Double>

    init(rng: SplitMix64, config: GameConfig) {
        self.rng = rng
        spacing = config.puddleSpacing
    }

    /// The position of the next puddle, in meters from the start line.
    mutating func next() -> Double {
        meters += max(rng.uniform(spacing), minimumAdvance)
        return meters
    }
}
