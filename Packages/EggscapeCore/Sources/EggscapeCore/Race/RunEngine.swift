/// One player's run: progress along the course, footsteps, weather and the egg in the bowl.
///
/// The engine is a plain value advanced in fixed steps of `1 / config.simulationRate` seconds. It never reads a clock,
/// so a run is reproducible from its seeds and inputs, which keeps it testable.
public struct RunEngine: Sendable {
    public enum Phase: Sendable, Equatable {
        case running
        /// The egg broke; the runner stands still until a new egg lies in the bowl.
        case recovering(remaining: Double)
        case finished
        /// The last egg broke.
        case over
    }

    public struct Input: Sendable, Equatable {
        /// Calibrated tilt in radians (x: right edge down, y: top edge down).
        public var tilt: SIMD2<Double>
        public var sprint: Bool

        public init(tilt: SIMD2<Double> = .zero, sprint: Bool = false) {
            self.tilt = tilt
            self.sprint = sprint
        }

        public static let level = Input()
    }

    public let config: GameConfig
    public let course: Course
    public private(set) var egg: EggPhysics
    public private(set) var weather: WeatherSystem
    public private(set) var phase = Phase.running
    public private(set) var meters = 0.0
    /// Simulated seconds since the start signal.
    public private(set) var elapsed = 0.0
    public private(set) var speed = 0.0
    public private(set) var eggsLeft: Int
    public private(set) var isSprinting = false
    /// Position within the current footstep, `0 ..< 1`; drives camera bob and the runner animation.
    public private(set) var stepPhase = 0.0
    /// Randomness that only affects this phone (footsteps, raindrops), unlike the shared weather schedule.
    private var rng: SplitMix64

    /// - Parameters:
    ///   - weather: the race's weather, identical for every player of a race.
    ///   - localSeed: seed for this player's own randomness.
    public init(config: GameConfig = .standard, course: Course, weather: WeatherSchedule, localSeed: UInt64) {
        self.config = config
        self.course = course
        egg = EggPhysics(config: config)
        self.weather = WeatherSystem(schedule: weather, config: config)
        eggsLeft = config.eggsPerRun
        rng = SplitMix64(seed: localSeed)
    }

    public var dt: Double {
        1 / config.simulationRate
    }

    public var isOver: Bool {
        phase == .finished || phase == .over
    }

    /// Share of the course completed, `nil` in endless mode.
    public var progress: Double? {
        course.length.map { min(meters / $0, 1) }
    }

    public var eggsLost: Int {
        config.eggsPerRun - eggsLeft
    }

    /// Lets the egg roll with the player's tilt before the start, without footsteps and without falling out.
    public mutating func warmUp(_ input: Input) {
        egg.step(dt: dt, tilt: input.tilt)
        if egg.hasFallen {
            egg.reset()
        }
    }

    /// Advances the run by one fixed step and appends what happened to `events`.
    public mutating func step(_ input: Input, events: inout [RunEvent]) {
        switch phase {
        case .finished, .over:
            return
        case let .recovering(remaining):
            elapsed += dt
            if remaining > dt {
                phase = .recovering(remaining: remaining - dt)
            } else {
                egg.reset()
                phase = .running
                events.append(.newEgg)
            }
            return
        case .running:
            break
        }

        elapsed += dt
        isSprinting = input.sprint
        let targetSpeed = input.sprint ? config.sprintSpeed : config.runSpeed
        speed += (targetSpeed - speed) * min(dt / config.speedResponse, 1)
        let startMeters = meters
        meters += speed * dt

        let impact = weather.step(
            time: elapsed,
            from: startMeters,
            to: meters,
            dt: dt,
            rng: &rng,
            events: &events
        )

        stepPhase += config.stepFrequency * (speed / config.runSpeed) * dt
        if stepPhase >= 1 {
            stepPhase -= 1
            var magnitude = rng.uniform(config.stepKick) * impact.footstepScale
            if input.sprint {
                magnitude *= config.sprintDisturbance
            }
            let kick = Kick(rng.direction() * magnitude, .footstep)
            egg.kick(kick.velocity)
            events.append(.footstep(sprinting: input.sprint))
            events.append(.kick(kick))
        }
        for kick in impact.kicks {
            egg.kick(kick.velocity)
            events.append(.kick(kick))
        }

        egg.step(dt: dt, tilt: input.tilt, force: impact.force, dampingScale: impact.dampingScale)

        if egg.hasFallen {
            eggsLeft -= 1
            speed = 0
            events.append(.eggDropped(position: egg.position, eggsLeft: eggsLeft))
            if eggsLeft > 0 {
                phase = .recovering(remaining: config.dropPause)
            } else {
                phase = .over
                events.append(.runOver(meters: meters))
            }
            return
        }

        if let length = course.length, meters >= length {
            // Interpolate the moment the line was crossed inside this step for a fair finish time.
            let overshoot = speed > 0 ? (meters - length) / speed : 0
            elapsed -= min(overshoot, dt)
            meters = length
            phase = .finished
            events.append(.finished(time: elapsed))
        }
    }
}
