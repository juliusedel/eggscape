/// What an effect needs to know about one simulation step.
struct WeatherStep {
    /// Race time at the end of the step, in seconds since the start.
    var time: Double
    /// The runner's position before and after the step, in meters from the start line.
    var from: Double
    var to: Double
    var dt: Double
}

/// One ingredient of the weather, such as wind or rain. Kinds of weather are mixes of effects (`WeatherMix`), and
/// `WeatherSystem` runs every effect each step with its share of the weather where the runner is.
protocol WeatherEffect: Sendable {
    /// Adds this effect's share of one simulation step to `impact`.
    /// - Parameters:
    ///   - strength: 0 ... 1, how strongly the effect acts where the runner is.
    ///   - rng: the runner's own stream, for pushes that may differ from phone to phone (raindrops, puddles). Shared
    ///     randomness comes from the schedule's timelines instead.
    mutating func apply(
        _ step: WeatherStep,
        strength: Double,
        to impact: inout WeatherImpact,
        rng: inout SplitMix64,
        events: inout [RunEvent]
    )
}

/// Gusts from the shared timeline, pushing the egg sideways.
struct WindEffect: WeatherEffect {
    private var timeline: GustTimeline
    /// The gust blowing now, or the next one during a calm gap.
    private var gust: WeatherSchedule.Gust
    /// How strongly the runner feels the wind, 0 ... 1. It follows the weather along the track within `windFade`
    /// seconds, so running into or out of a windy stretch mid-gust never yanks the egg.
    private var strength: Double
    private let fade: Double
    /// Signed lateral force on the egg in the last step; positive pushes to the right.
    private(set) var force = 0.0

    /// - Parameter strength: the wind where the runner starts, so fixed wind blows at full strength from the start.
    init(schedule: WeatherSchedule, strength: Double, config: GameConfig) {
        var timeline = schedule.gustTimeline
        gust = timeline.next()
        self.timeline = timeline
        self.strength = strength
        fade = config.windFade
    }

    mutating func apply(
        _ step: WeatherStep,
        strength target: Double,
        to impact: inout WeatherImpact,
        rng _: inout SplitMix64,
        events _: inout [RunEvent]
    ) {
        while step.time >= gust.end {
            gust = timeline.next()
        }
        let maxChange = fade > 0 ? step.dt / fade : .infinity
        if abs(target - strength) <= maxChange {
            // Lands exactly on the target, so steady weather scales the gusts by exactly its intensity.
            strength = target
        } else {
            strength += target > strength ? maxChange : -maxChange
        }
        force = strength > 0 ? gust.force(at: step.time) * strength : 0
        if force != 0 {
            impact.force.x += force
        }
    }
}

/// A wet, slippery bowl, raindrops and puddles. Drops and splashes come from the runner's own stream: they are many,
/// small and never compared between players, unlike gusts and lightning.
struct RainEffect: WeatherEffect {
    /// To check whether a puddle holds water where it lies, not just where the runner is now.
    private let schedule: WeatherSchedule
    private var track: PuddleTrack
    /// The next puddle spot ahead of the runner.
    private var nextPuddle: Double
    private let dampingFactor: Double
    private let dropRate: Double
    private let dropKick: ClosedRange<Double>
    private let puddleKick: ClosedRange<Double>

    init(schedule: WeatherSchedule, config: GameConfig) {
        self.schedule = schedule
        var track = schedule.puddleTrack
        nextPuddle = track.next()
        self.track = track
        dampingFactor = config.rainDampingFactor
        dropRate = config.rainDropRate
        dropKick = config.rainDropKick
        puddleKick = config.puddleKick
    }

    mutating func apply(
        _ step: WeatherStep,
        strength: Double,
        to impact: inout WeatherImpact,
        rng: inout SplitMix64,
        events: inout [RunEvent]
    ) {
        if strength > 0 {
            impact.dampingScale *= 1 - (1 - dampingFactor) * strength
            addRaindrops(strength: strength, dt: step.dt, to: &impact, rng: &rng)
        }
        splash(from: step.from, to: step.to, impact: &impact, rng: &rng, events: &events)
    }

    /// Drops land at random, `rainDropRate` per second in full rain. One trial per step (and per further expected
    /// drop) is a close enough stand-in for a Poisson stream at 120 Hz. Their pushes are summed into `impulse`
    /// because a kick event per drop would flood the event stream.
    private func addRaindrops(strength: Double, dt: Double, to impact: inout WeatherImpact, rng: inout SplitMix64) {
        var expected = dropRate * strength * dt
        while expected > 0 {
            if rng.chance(expected) {
                impact.impulse += rng.direction() * rng.uniform(dropKick)
            }
            expected -= 1
        }
    }

    /// Every puddle passed in this step splashes once if it holds water, that is if it rains where it lies, and the
    /// harder it rains there, the harder the splash.
    private mutating func splash(
        from: Double,
        to: Double,
        impact: inout WeatherImpact,
        rng: inout SplitMix64,
        events: inout [RunEvent]
    ) {
        while nextPuddle <= to {
            if nextPuddle > from {
                let wetness = schedule.conditions(atMeters: nextPuddle).mix.rain
                if wetness > 0 {
                    let velocity = rng.direction() * (rng.uniform(puddleKick) * wetness)
                    impact.kicks.append(Kick(velocity, .puddle))
                    events.append(.puddle)
                }
            }
            nextPuddle = track.next()
        }
    }
}

/// Strikes from the shared timeline, announced `lightningWarning` seconds ahead.
///
/// Whether a strike reaches the runner is decided once, when its warning starts: in a thunderstorm the warning
/// flickers and the strike follows for sure, even if the runner leaves the storm in between; outside of one the
/// strike passes by. So no runner is ever hit without a warning.
struct LightningEffect: WeatherEffect {
    private var timeline: LightningTimeline
    /// The next strike on the timeline.
    private var strike: WeatherSchedule.LightningStrike
    /// The storm's strength when the warning for `strike` started; `nil` while no strike is coming for this runner.
    private var pending: Double?
    private let kick: Double

    init(schedule: WeatherSchedule, config: GameConfig) {
        var timeline = schedule.lightningTimeline
        strike = timeline.next()
        self.timeline = timeline
        kick = config.lightningKick
    }

    /// The warning flickers: a strike follows within `lightningWarning` seconds.
    var isWarningActive: Bool {
        pending != nil
    }

    mutating func apply(
        _ step: WeatherStep,
        strength: Double,
        to impact: inout WeatherImpact,
        rng _: inout SplitMix64,
        events: inout [RunEvent]
    ) {
        // Each pass either stops or moves on (arms the next strike, lands it, or lets it pass by).
        while true {
            if let pending {
                guard strike.time <= step.time else {
                    return
                }
                impact.kicks.append(Kick(strike.direction * (kick * pending), .lightning))
                events.append(.lightningStrike)
                self.pending = nil
                strike = timeline.next()
            } else {
                guard strike.warningTime <= step.time else {
                    return
                }
                if strength > 0 {
                    pending = strength
                    events.append(.lightningWarning)
                } else {
                    strike = timeline.next()
                }
            }
        }
    }
}
