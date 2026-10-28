/// The race's weather plan. Every phone of a race builds it from the same seed, so all players get the same weather.
///
/// The plan uses two axes on purpose. *Where* the weather is belongs to the track: stretches in meters from the start
/// line, so a runner who falls behind meets the same storm a little later. *When* a gust blows or lightning strikes
/// belongs to the sky: timelines in race time (seconds since the start), so everyone sees the flash at the same
/// moment wherever they are. A gust or a strike reaches a runner only if the stretch they are in has wind or
/// lightning; puddles lie at fixed positions and hold water only where it rains.
///
/// The random draws depend on the seed and the tunables alone, never on a runner's position or on intensity, which is
/// applied when the plan is queried. Each part of the plan has its own random stream, so a new effect can be added
/// later without changing the existing ones for a given seed. Changing a weather tunable in `GameConfig` does change
/// every race's weather, so phones with different tunables must not race together.
public struct WeatherSchedule: Sendable, Equatable {
    /// A part of the track with the same weather.
    public struct Stretch: Hashable, Sendable {
        /// Where the stretch lies, in meters from the start line. The last stretch of a plan never ends; in a time
        /// trial it runs on past the finish line.
        public var meters: Range<Double>
        public var conditions: WeatherConditions
        /// Multiplier on footstep kicks: above 1 only deep into Endlos, once the weather is at full strength.
        public var footstepScale: Double

        init(meters: Range<Double>, conditions: WeatherConditions, footstepScale: Double = 1) {
            self.meters = meters
            self.conditions = conditions
            self.footstepScale = footstepScale
        }
    }

    public let seed: UInt64
    /// The tunables the plan was drawn with.
    public let config: GameConfig
    private let plan: Plan
    /// Starting states of the timelines; `WeatherSystem` walks copies of them as the race goes on.
    let gustTimeline: GustTimeline
    let lightningTimeline: LightningTimeline
    let puddleTrack: PuddleTrack

    /// - Parameters:
    ///   - seed: the race seed, shared by every player of the race.
    ///   - option: `random` escalates along a time trial. Endlos intensifies every `endlessStageLength` meters
    ///     with `random` or a fixed kind of weather; `off` and `fixed(.clear)` stay clear everywhere.
    ///   - config: the tunables; every player of a race must use the same.
    public init(seed: UInt64, option: WeatherOption, course: Course, config: GameConfig = .standard) {
        let root = SplitMix64(seed: seed)
        var stretches = root.stream(Stream.stretches)
        let plan: Plan = switch (option, course) {
        case (.off, _), (.fixed(.clear), _):
            .stretches([Self.calmForever])
        case let (.fixed(kind), .timeTrial):
            .stretches([Stretch(meters: 0 ..< .infinity, conditions: WeatherConditions(kind: kind, intensity: 1))])
        case let (.random, .timeTrial(distance)):
            .stretches(Self.escalatingStretches(length: distance.meters, rng: &stretches, config: config))
        case let (.fixed(kind), .endless):
            .stages(EndlessStages(stream: stretches, kind: kind, config: config))
        case (.random, .endless):
            .stages(EndlessStages(stream: stretches, kind: nil, config: config))
        }
        self.init(seed: seed, plan: plan, root: root, config: config)
    }

    /// A hand-made plan for tests and demos: contiguous stretches from the start line, the last one open-ended.
    init(seed: UInt64, stretches: [Stretch], config: GameConfig = .standard) {
        self.init(seed: seed, plan: .stretches(stretches), root: SplitMix64(seed: seed), config: config)
    }

    private init(seed: UInt64, plan: Plan, root: SplitMix64, config: GameConfig) {
        self.seed = seed
        self.config = config
        self.plan = plan
        gustTimeline = GustTimeline(rng: root.stream(Stream.gusts), config: config)
        lightningTimeline = LightningTimeline(rng: root.stream(Stream.lightning), config: config)
        puddleTrack = PuddleTrack(rng: root.stream(Stream.puddles), config: config)
    }

    /// No weather anywhere.
    public static let clear = WeatherSchedule(seed: 0, option: .off, course: .endless)

    // MARK: Along the track

    /// The stretch of the track at `meters` from the start line. O(1) in Endlos, however far the runner gets.
    public func stretch(atMeters meters: Double) -> Stretch {
        switch plan {
        case let .stretches(stretches):
            stretches.last { $0.meters.lowerBound <= meters } ?? stretches.first ?? Self.calmForever
        case let .stages(stages):
            stages.stage(stages.index(atMeters: meters))
        }
    }

    /// The weather at `meters` from the start line.
    public func conditions(atMeters meters: Double) -> WeatherConditions {
        stretch(atMeters: meters).conditions
    }

    /// The stretches that overlap `range`, in order, e.g. for a forecast of the course. `range` must be finite,
    /// because Endlos has no last stretch.
    public func stretches(in range: Range<Double>) -> [Stretch] {
        precondition(range.upperBound.isFinite, "stretches(in:) needs a finite range")
        var result: [Stretch] = []
        var position = range.lowerBound
        while position < range.upperBound {
            let stretch = stretch(atMeters: position)
            result.append(stretch)
            // A hand-made plan with gaps could otherwise stall here.
            guard stretch.meters.upperBound > position else {
                break
            }
            position = stretch.meters.upperBound
        }
        return result
    }

    /// The puddles in `range` that hold water, in meters from the start line, in order. Where it does not rain, the
    /// ground is dry and there is nothing to splash through.
    public func puddles(in range: ClosedRange<Double>) -> [Double] {
        puddleSpots(in: range).filter { conditions(atMeters: $0).mix.rain > 0 }
    }

    /// Every place in `range` where a puddle forms when it rains, wet or dry. They depend on the seed alone.
    func puddleSpots(in range: ClosedRange<Double>) -> [Double] {
        precondition(range.upperBound.isFinite, "puddles(in:) needs a finite range")
        var track = puddleTrack
        var result: [Double] = []
        while true {
            let position = track.next()
            guard position <= range.upperBound else {
                return result
            }
            if position >= range.lowerBound {
                result.append(position)
            }
        }
    }

    // MARK: In race time

    /// The gusts that start before `time` (seconds since the start), in order. Whether a gust reaches a runner
    /// depends on the weather where the runner is while it blows.
    public func gusts(until time: Double) -> [Gust] {
        precondition(time.isFinite, "gusts(until:) needs a finite time")
        var timeline = gustTimeline
        var result: [Gust] = []
        while true {
            let gust = timeline.next()
            guard gust.start < time else {
                return result
            }
            result.append(gust)
        }
    }

    /// The gust between its start and its end at `time`, `nil` during a calm gap.
    public func gust(at time: Double) -> Gust? {
        guard time.isFinite else {
            return nil
        }
        var timeline = gustTimeline
        while true {
            let gust = timeline.next()
            if gust.start > time {
                return nil
            }
            if time < gust.end {
                return gust
            }
        }
    }

    /// The lightning strikes up to `time` (seconds since the start), in order. A strike reaches a runner only if
    /// they are in a thunderstorm when its warning starts.
    public func lightningStrikes(until time: Double) -> [LightningStrike] {
        precondition(time.isFinite, "lightningStrikes(until:) needs a finite time")
        var timeline = lightningTimeline
        var result: [LightningStrike] = []
        while true {
            let strike = timeline.next()
            guard strike.time <= time else {
                return result
            }
            result.append(strike)
        }
    }

    // MARK: Plans

    private static let calmForever = Stretch(meters: 0 ..< .infinity, conditions: .clear)

    /// Labels of the independent random streams. Never renumber them: that would change the weather of every seed.
    private enum Stream {
        static let stretches: UInt64 = 1
        static let gusts: UInt64 = 2
        static let lightning: UInt64 = 3
        static let puddles: UInt64 = 4
    }

    private enum Plan: Sendable, Equatable {
        /// Contiguous stretches from the start line; the last one never ends.
        case stretches([Stretch])
        /// Endlos: a new stage every `endlessStageLength` meters.
        case stages(EndlessStages)
    }

    /// Zufall on a time trial: a calm start, then stretches of wind or rain that get evenly stronger up to full
    /// strength on the last one, so the hardest part is always the finish. With `randomStormChance` the last third of
    /// the stretches is a thunderstorm instead, so the kinds only ever get harder along the track too.
    private static func escalatingStretches(
        length: Double,
        rng: inout SplitMix64,
        config: GameConfig
    ) -> [Stretch] {
        let calm = min(max(rng.uniform(config.randomCalmStart), 0), length / 2)
        let startIntensity = min(max(rng.uniform(config.randomStartIntensity), 0), 1)
        let stormy = rng.chance(config.randomStormChance)

        let weatherLength = length - calm
        let rawCount = (weatherLength / config.randomStretchLength).rounded()
        // `>=` also sends NaN to the minimum of two stretches.
        let count = rawCount >= 2 ? Int(min(rawCount, 64)) : 2
        let stormCount = stormy ? (count + 2) / 3 : 0

        // Evenly spaced boundaries, each moved a little; less than half a segment keeps them in order.
        let segment = weatherLength / Double(count)
        let jitterShare = config.randomStretchJitter.isFinite ? min(abs(config.randomStretchJitter), 0.45) : 0
        let jitter = jitterShare * segment
        var bounds = [calm]
        for index in 1 ..< count {
            bounds.append(calm + Double(index) * segment + rng.uniform(-jitter ... jitter))
        }
        bounds.append(.infinity)

        var stretches = calm > 0 ? [Stretch(meters: 0 ..< calm, conditions: .clear)] : []
        for index in 0 ..< count {
            let kind: WeatherKind = if index >= count - stormCount {
                .storm
            } else {
                rng.chance(0.5) ? .wind : .rain
            }
            let progress = Double(index) / Double(count - 1)
            // Exactly full strength at the finish, whatever the rounding on the way.
            let intensity = index == count - 1 ? 1 : startIntensity + (1 - startIntensity) * progress
            stretches.append(Stretch(
                meters: bounds[index] ..< bounds[index + 1],
                conditions: WeatherConditions(kind: kind, intensity: intensity)
            ))
        }
        return stretches
    }
}

/// The stages of Endlos. Each stage is derived from its own stream, labelled with the stage number, so any stage is
/// computed in O(1) without generating the ones before it, however far the runner gets.
private struct EndlessStages: Sendable, Equatable {
    /// Stages beyond this (200 billion meters with the defaults) repeat the last one instead of overflowing `Int`.
    private static let lastIndex = Int(Int32.max)

    private let stream: SplitMix64
    /// The kind of every stage, or `nil` to pick one per stage.
    private let kind: WeatherKind?
    private let length: Double
    private let startIntensity: Double
    private let stagesToFull: Int
    private let stormStage: Int
    private let footstepGain: Double
    private let footstepScaleMax: Double

    init(stream: SplitMix64, kind: WeatherKind?, config: GameConfig) {
        self.stream = stream
        self.kind = kind
        length = config.endlessStageLength > 0 ? config.endlessStageLength : GameConfig.standard.endlessStageLength
        startIntensity = min(max(config.endlessStartIntensity, 0), 1)
        stagesToFull = max(config.endlessStagesToFull, 0)
        stormStage = config.endlessStormStage
        footstepGain = max(config.endlessFootstepGain, 0)
        footstepScaleMax = max(config.endlessFootstepScaleMax, 1)
    }

    /// The stage that contains `meters`: `floor(meters / endlessStageLength)`.
    func index(atMeters meters: Double) -> Int {
        // `>` also sends NaN to stage 0.
        guard meters > 0 else {
            return 0
        }
        let raw = (meters / length).rounded(.down)
        guard raw < Double(Self.lastIndex) else {
            return Self.lastIndex
        }
        // The division can round across a boundary; the stage's own range must contain `meters`.
        var index = Int(raw)
        if Double(index) * length > meters {
            index -= 1
        } else if Double(index + 1) * length <= meters {
            index += 1
        }
        return index
    }

    func stage(_ index: Int) -> WeatherSchedule.Stretch {
        let meters = Double(index) * length ..< Double(index + 1) * length
        // Stage 0 is clear, so every run gets going in calm weather.
        guard index > 0, kind != .clear else {
            return WeatherSchedule.Stretch(meters: meters, conditions: .clear)
        }
        var rng = stream.stream(UInt64(index))
        let stageKind = kind ?? randomKind(stage: index, rng: &rng)

        let climbed = index - 1
        let intensity = if climbed >= stagesToFull {
            1.0
        } else {
            startIntensity + (1 - startIntensity) * Double(climbed) / Double(stagesToFull)
        }
        // At full strength the weather cannot get worse, so the footsteps take over, mildly and only up to a cap.
        let footstepScale = if climbed > stagesToFull {
            min(1 + footstepGain * Double(climbed - stagesToFull), footstepScaleMax)
        } else {
            1.0
        }
        return WeatherSchedule.Stretch(
            meters: meters,
            conditions: WeatherConditions(kind: stageKind, intensity: intensity),
            footstepScale: footstepScale
        )
    }

    /// Wind or rain, and from `endlessStormStage` on also thunderstorms.
    private func randomKind(stage: Int, rng: inout SplitMix64) -> WeatherKind {
        let kinds: [WeatherKind] = stage >= stormStage ? [.wind, .rain, .storm] : [.wind, .rain]
        return kinds[rng.index(below: kinds.count)]
    }
}
