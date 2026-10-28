/// What the weather does to the egg during one simulation step.
public struct WeatherImpact: Sendable, Equatable {
    /// Continuous acceleration, e.g. wind.
    public var force: SIMD2<Double> = .zero
    /// Multiplier on the bowl damping.
    public var dampingScale = 1.0
    /// Multiplier on footstep kicks.
    public var footstepScale = 1.0
    /// Sudden pushes during this step that deserve an event each (puddles, lightning).
    public var kicks: [Kick] = []
    /// Summed velocity change of the many tiny pushes (raindrops) that would flood the event stream as kicks.
    public var impulse: SIMD2<Double> = .zero

    public init() {}
}

/// The weather one runner experiences: the race's shared schedule, applied at the runner's position and race time.
///
/// Each step looks up the stretch the runner is in, turns its conditions into a `WeatherMix` and lets every effect
/// (wind, rain, lightning) add its share. Everything shared comes from the schedule, so all phones of a race agree on
/// the weather; only raindrops and puddle splashes use the runner's own random stream.
public struct WeatherSystem: Sendable {
    public let schedule: WeatherSchedule
    public let config: GameConfig
    /// The stretch of the track the runner is in; before the start, the first one.
    public private(set) var stretch: WeatherSchedule.Stretch
    /// What `weatherChanged` last announced. It starts clear, so a start in bad weather is announced at the first step.
    private var announced = WeatherConditions.clear
    private var windEffect: WindEffect
    private var rainEffect: RainEffect
    private var lightningEffect: LightningEffect

    /// - Parameter config: per-runner tunables (rain, puddle and lightning kicks, wind fade). The gust and lightning
    ///   timelines follow the tunables the schedule was built with.
    public init(schedule: WeatherSchedule, config: GameConfig) {
        self.schedule = schedule
        self.config = config
        stretch = schedule.stretch(atMeters: 0)
        windEffect = WindEffect(schedule: schedule, strength: stretch.conditions.mix.wind, config: config)
        rainEffect = RainEffect(schedule: schedule, config: config)
        lightningEffect = LightningEffect(schedule: schedule, config: config)
    }

    /// The weather where the runner is, for the HUD's weather icon and intensity.
    public var conditions: WeatherConditions {
        stretch.conditions
    }

    /// The effects of the weather where the runner is, e.g. how hard it rains for the renderer.
    public var mix: WeatherMix {
        conditions.mix
    }

    /// Signed lateral wind force on the egg right now, in bowl units per second²; positive pushes to the right.
    public var wind: Double {
        windEffect.force
    }

    /// How hard the wind blows right now compared with the strongest possible gust, 0 ... 1, for the HUD's wind
    /// arrow. The direction is the sign of `wind`.
    public var gustStrength: Double {
        let strongest = config.windForce.upperBound
        return strongest > 0 ? min(abs(wind) / strongest, 1) : 0
    }

    /// Lightning strikes within `GameConfig.lightningWarning` seconds: time for the warning flicker.
    public var isLightningWarningActive: Bool {
        lightningEffect.isWarningActive
    }

    /// It rains where the runner is (also in a thunderstorm).
    public var isRaining: Bool {
        mix.rain > 0
    }

    /// Advances the weather by one fixed step and returns what it does to the egg.
    /// - Parameters:
    ///   - time: race time at the end of the step, in seconds since the start.
    ///   - from: the runner's position before the step, in meters.
    ///   - to: the runner's position after the step; equal to `from` while the runner stands still.
    ///   - rng: the runner's own random stream.
    mutating func step(
        time: Double,
        from: Double,
        to: Double,
        dt: Double,
        rng: inout SplitMix64,
        events: inout [RunEvent]
    ) -> WeatherImpact {
        if !stretch.meters.contains(to) {
            stretch = schedule.stretch(atMeters: to)
        }
        if stretch.conditions != announced {
            announced = stretch.conditions
            events.append(.weatherChanged(stretch.conditions))
        }

        let mix = stretch.conditions.mix
        let step = WeatherStep(time: time, from: from, to: to, dt: dt)
        var impact = WeatherImpact()
        impact.footstepScale = stretch.footstepScale
        windEffect.apply(step, strength: mix.wind, to: &impact, rng: &rng, events: &events)
        rainEffect.apply(step, strength: mix.rain, to: &impact, rng: &rng, events: &events)
        lightningEffect.apply(step, strength: mix.lightning, to: &impact, rng: &rng, events: &events)
        return impact
    }
}
