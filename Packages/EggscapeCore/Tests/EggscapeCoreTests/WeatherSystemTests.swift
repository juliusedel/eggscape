@testable import EggscapeCore
import Foundation
import Testing

/// Steps a weather system the way `RunEngine` does, for a runner at a steady pace.
private struct SteadyRunner {
    var weather: WeatherSystem
    var rng: SplitMix64
    let speed: Double
    let dt: Double
    private(set) var time = 0.0
    private(set) var meters = 0.0
    /// Everything that happened so far.
    private(set) var events: [RunEvent] = []

    init(_ schedule: WeatherSchedule, config: GameConfig = .standard, localSeed: UInt64 = 7, speed: Double = 3) {
        weather = WeatherSystem(schedule: schedule, config: config)
        rng = SplitMix64(seed: localSeed)
        self.speed = speed
        dt = 1 / config.simulationRate
    }

    /// One fixed step: what the weather does to the egg and what happened in this step.
    mutating func step() -> (impact: WeatherImpact, events: [RunEvent]) {
        let from = meters
        time += dt
        meters += speed * dt
        var stepEvents: [RunEvent] = []
        let impact = weather.step(time: time, from: from, to: meters, dt: dt, rng: &rng, events: &stepEvents)
        events += stepEvents
        return (impact, stepEvents)
    }
}

/// An event together with the step it happened in.
private struct Stamped: Equatable {
    var step: Int
    var event: RunEvent
}

private func magnitude(_ vector: SIMD2<Double>) -> Double {
    (vector * vector).sum().squareRoot()
}

/// A bowl so large the egg never falls out, so runners stay side by side however the weather pushes them.
private var bottomlessBowl: GameConfig {
    var config = GameConfig()
    config.bowlRadiusX = 1000
    config.bowlRadiusY = 1000
    return config
}

/// One stretch of the given weather along the whole track.
private func steady(_ kind: WeatherKind, intensity: Double = 1, seed: UInt64 = 11) -> WeatherSchedule {
    let conditions = WeatherConditions(kind: kind, intensity: intensity)
    return WeatherSchedule(
        seed: seed,
        stretches: [WeatherSchedule.Stretch(meters: 0 ..< .infinity, conditions: conditions)]
    )
}

struct WeatherSystemTests {
    // MARK: No weather

    @Test(arguments: [WeatherOption.off, .fixed(.clear)])
    func clearWeatherHasNoEffectAtAll(option: WeatherOption) {
        let schedules = [WeatherSchedule.clear] + [Course.timeTrial(.long), .endless].map {
            WeatherSchedule(seed: 42, option: option, course: $0)
        }
        for schedule in schedules {
            var runner = SteadyRunner(schedule)
            let untouched = runner.rng
            var neutral = true
            for _ in 0 ..< 120 * 240 {
                let impact = runner.step().impact
                neutral = neutral && impact == WeatherImpact() && runner.weather.wind == 0
                    && runner.weather.gustStrength == 0 && !runner.weather.isRaining
                    && !runner.weather.isLightningWarningActive
            }
            #expect(neutral)
            #expect(runner.events.isEmpty)
            // Not a single local draw, so the footsteps stay exactly as without weather.
            #expect(runner.rng == untouched)
            #expect(runner.weather.conditions == .clear)
        }
    }

    @Test func clearRunsAreIdenticalToRunsWithoutWeather() {
        let course = Course.timeTrial(.medium)
        // Tilted and sprinting, so eggs drop and the weather also ticks while the next egg is placed.
        let input = RunEngine.Input(tilt: SIMD2(radians(9), radians(-3)), sprint: true)
        var reference = RunEngine(course: course, weather: .clear, localSeed: 3)
        var referenceEvents: [RunEvent] = []
        for _ in 0 ..< 120 * 40 {
            reference.step(input, events: &referenceEvents)
        }
        #expect(referenceEvents.contains {
            if case .eggDropped = $0 {
                true
            } else {
                false
            }
        })

        let schedules = [
            WeatherSchedule(seed: 99, option: .off, course: course),
            WeatherSchedule(seed: 5, option: .fixed(.clear), course: course),
        ]
        for schedule in schedules {
            var engine = RunEngine(course: course, weather: schedule, localSeed: 3)
            var events: [RunEvent] = []
            for _ in 0 ..< 120 * 40 {
                engine.step(input, events: &events)
            }
            #expect(engine.egg == reference.egg)
            #expect(engine.meters == reference.meters)
            #expect(events == referenceEvents)
        }
    }

    // MARK: Wind

    @Test func windFollowsTheSharedGustTimeline() {
        let schedule = WeatherSchedule(seed: 17, option: .fixed(.wind), course: .timeTrial(.long))
        var runner = SteadyRunner(schedule)
        var matches = true
        var strongest = 0.0
        var sides = Set<Double>()
        for _ in 0 ..< 120 * 90 {
            let impact = runner.step().impact
            let expected = schedule.gust(at: runner.time)?.force(at: runner.time) ?? 0
            matches = matches && runner.weather.wind == expected && impact.force == SIMD2(expected, 0)
                && runner.weather.gustStrength == abs(expected) / GameConfig.standard.windForce.upperBound
            strongest = max(strongest, runner.weather.gustStrength)
            if expected != 0 {
                sides.insert(expected > 0 ? 1 : -1)
            }
        }
        #expect(matches)
        #expect(strongest > 0.3 && strongest <= 1)
        #expect(sides == [1, -1])
    }

    @Test func windPushesALevelEggToARestingOffset() throws {
        var config = GameConfig()
        // One long, steady gust.
        config.gustGap = 0.5 ... 0.5
        config.gustHold = 30 ... 30
        config.windForce = 0.8 ... 0.8
        let schedule = WeatherSchedule(seed: 3, option: .fixed(.wind), course: .timeTrial(.long), config: config)
        let gust = try #require(schedule.gusts(until: 1).first)
        var runner = SteadyRunner(schedule, config: config)
        var egg = EggPhysics(config: config)
        for _ in 0 ..< 120 * 20 {
            let impact = runner.step().impact
            egg.step(dt: runner.dt, tilt: .zero, force: impact.force, dampingScale: impact.dampingScale)
        }

        // Mid-gust the wind holds its peak and the bowl's slope balances it F / k = 0.4 units off center.
        let wind = runner.weather.wind
        #expect(wind == 0.8 * gust.direction)
        #expect(egg.restingPosition(tilt: .zero, force: SIMD2(wind, 0)).x == 0.4 * gust.direction)
        #expect(abs(egg.position.x - 0.4 * gust.direction) < 1e-3)
        #expect(egg.position.y == 0)
        // Tilting against the wind by asin(F / G) keeps the egg centered.
        let counterTilt = SIMD2(-asin(wind / config.gravity), 0)
        #expect(abs(egg.restingPosition(tilt: counterTilt, force: SIMD2(wind, 0)).x) < 1e-12)
    }

    @Test func windFadesInAndOutAlongTheTrack() {
        var config = GameConfig()
        config.gustGap = 0.5 ... 0.5
        config.gustHold = 60 ... 60
        config.windForce = 1 ... 1
        let wind = WeatherConditions(kind: .wind, intensity: 1)
        // Calm until 30 m (10 s at 3 m/s), wind until 60 m, calm again.
        let schedule = WeatherSchedule(seed: 1, stretches: [
            WeatherSchedule.Stretch(meters: 0 ..< 30, conditions: .clear),
            WeatherSchedule.Stretch(meters: 30 ..< 60, conditions: wind),
            WeatherSchedule.Stretch(meters: 60 ..< .infinity, conditions: .clear),
        ], config: config)
        var runner = SteadyRunner(schedule, config: config)
        var forces: [Double] = []
        while runner.meters < 75 {
            _ = runner.step()
            forces.append(abs(runner.weather.wind))
        }
        // Mid-gust, the wind neither jumps on nor off: it changes by at most dt / windFade per step and is
        // at full strength within a second of entering the windy stretch.
        let jumps = zip(forces, forces.dropFirst()).map { abs($1 - $0) }
        #expect(jumps.allSatisfy { $0 <= runner.dt / config.windFade + 1e-12 })
        let entered = forces.firstIndex { $0 > 0 } ?? 0
        #expect(forces[entered + 120] == 1)
        #expect(forces.last == 0)
    }

    // MARK: Intensity

    @Test func intensityScalesEveryEffect() {
        var full = SteadyRunner(steady(.storm), localSeed: 1)
        var half = SteadyRunner(steady(.storm, intensity: 0.5), localSeed: 1)
        var windHalves = true
        var dampingMatches = true
        var drops = (full: 0, half: 0)
        var kicks: (full: [Kick], half: [Kick]) = ([], [])
        for _ in 0 ..< 120 * 600 {
            let strong = full.step().impact
            let weak = half.step().impact
            windHalves = windHalves && weak.force.x == strong.force.x * 0.5
            dampingMatches = dampingMatches && abs(strong.dampingScale - 0.4) < 1e-12
                && abs(weak.dampingScale - 0.7) < 1e-12
            drops.full += strong.impulse == .zero ? 0 : 1
            drops.half += weak.impulse == .zero ? 0 : 1
            kicks.full += strong.kicks
            kicks.half += weak.kicks
        }
        // Wind at half the force, damping halfway to the wet value.
        #expect(windHalves)
        #expect(dampingMatches)
        // The same strikes at half the jolt.
        let strikes = (
            full: kicks.full.filter { $0.source == .lightning },
            half: kicks.half.filter { $0.source == .lightning }
        )
        #expect(strikes.full.count == strikes.half.count && strikes.full.count > 30)
        #expect(zip(strikes.full, strikes.half).allSatisfy { $0.velocity * 0.5 == $1.velocity })
        #expect(strikes.full.allSatisfy { abs(magnitude($0.velocity) - 0.8) < 1e-12 })
        // Half as many raindrops.
        let ratio = Double(drops.half) / Double(drops.full)
        #expect(ratio > 0.45 && ratio < 0.55)
        // Puddles splash half as hard.
        let splashes = (
            full: kicks.full.filter { $0.source == .puddle },
            half: kicks.half.filter { $0.source == .puddle }
        )
        #expect(splashes.full.count == splashes.half.count && splashes.full.count > 30)
        #expect(splashes.full.allSatisfy { (0.35 - 1e-12 ... 0.5 + 1e-12).contains(magnitude($0.velocity)) })
        #expect(splashes.half.allSatisfy { (0.175 - 1e-12 ... 0.25 + 1e-12).contains(magnitude($0.velocity)) })
    }

    // MARK: Rain

    @Test func rainLowersDampingSoAKickedEggWobblesLonger() {
        var runner = SteadyRunner(WeatherSchedule(seed: 5, option: .fixed(.rain), course: .timeTrial(.short)))
        let wet = runner.step().impact.dampingScale
        #expect(abs(wet - 0.4) < 1e-12)
        #expect(runner.weather.isRaining)

        // Seconds until a kicked egg stays within 1 % of the rim distance from the center for good.
        func settlingTime(dampingScale: Double) -> Double {
            var egg = EggPhysics()
            egg.kick(SIMD2(0.35, 0))
            var settled = 0.0
            for index in 1 ... 120 * 40 {
                egg.step(dt: 1.0 / 120, tilt: .zero, dampingScale: dampingScale)
                if egg.rimDistance >= 0.01 {
                    settled = Double(index) / 120
                }
            }
            return settled
        }
        #expect(settlingTime(dampingScale: wet) > 2 * settlingTime(dampingScale: 1))
    }

    @Test func raindropsAreSilentPushes() {
        let schedule = WeatherSchedule(seed: 6, option: .fixed(.rain), course: .timeTrial(.long))
        var runner = SteadyRunner(schedule)
        var drops = 0
        var sizesInRange = true
        for _ in 0 ..< 120 * 60 {
            let impact = runner.step().impact
            if impact.impulse != .zero {
                drops += 1
                let size = magnitude(impact.impulse)
                sizesInRange = sizesInRange && size >= 0.02 - 1e-12 && size <= 0.07 + 1e-12
            }
            sizesInRange = sizesInRange && impact.kicks.allSatisfy { $0.source == .puddle }
        }
        // About 8 drops per second in full rain.
        #expect(drops > 400 && drops < 560)
        #expect(sizesInRange)
        // Apart from the rainy start, only puddles show up as events.
        #expect(runner.events.first == .weatherChanged(WeatherConditions(kind: .rain, intensity: 1)))
        #expect(runner.events.dropFirst().allSatisfy { $0 == .puddle })
        #expect(runner.events.count - 1 == schedule.puddles(in: 0 ... runner.meters).count)
    }

    @Test func puddlesOnlySplashWhereItRains() {
        let schedule = WeatherSchedule(seed: 23, stretches: [
            WeatherSchedule.Stretch(meters: 0 ..< 100, conditions: .clear),
            WeatherSchedule.Stretch(meters: 100 ..< 200, conditions: WeatherConditions(kind: .rain, intensity: 1)),
            WeatherSchedule.Stretch(meters: 200 ..< 300, conditions: WeatherConditions(kind: .wind, intensity: 1)),
            WeatherSchedule.Stretch(
                meters: 300 ..< .infinity,
                conditions: WeatherConditions(kind: .storm, intensity: 0.5)
            ),
        ])
        var runner = SteadyRunner(schedule)
        var splashes: [ClosedRange<Double>] = []
        var kicks: [Kick] = []
        while runner.meters < 450 {
            let from = runner.meters
            let step = runner.step()
            if step.events.contains(.puddle) {
                splashes.append(from ... runner.meters)
            }
            kicks += step.impact.kicks.filter { $0.source == .puddle }
        }

        let spots = schedule.puddleSpots(in: 0 ... runner.meters)
        let wet = spots.filter { (100 ..< 200).contains($0) || $0 >= 300 }
        // Dry spots in the sun and in the wind, or the test would prove nothing.
        #expect(spots.count > wet.count && !wet.isEmpty)
        #expect(schedule.puddles(in: 0 ... runner.meters) == wet)
        // Exactly one splash per wet puddle, in the step that passes it.
        #expect(splashes.count == wet.count)
        #expect(zip(splashes, wet).allSatisfy { $0.lowerBound < $1 && $1 <= $0.upperBound })
        #expect(kicks.count == wet.count)
        // The storm here blows at half strength, so its puddles splash half as hard.
        let sizes = zip(wet, kicks).map { (meters: $0, size: magnitude($1.velocity)) }
        let rain = 0.35 - 1e-12 ... 0.5 + 1e-12
        let halfStorm = 0.175 - 1e-12 ... 0.25 + 1e-12
        #expect(sizes.allSatisfy { ($0.meters < 300 ? rain : halfStorm).contains($0.size) })
    }

    // MARK: Thunderstorm

    @Test func stormCombinesWindRainAndLightning() {
        let schedule = WeatherSchedule(seed: 29, option: .fixed(.storm), course: .timeTrial(.long))
        var runner = SteadyRunner(schedule)
        var warnings: [Double] = []
        var strikes: [Double] = []
        var jolts: [Kick] = []
        var wet = true
        var windy = false
        var drizzly = false
        var warningShown = true
        var strikeComing = false
        for _ in 0 ..< 120 * 200 {
            let step = runner.step()
            wet = wet && abs(step.impact.dampingScale - 0.4) < 1e-12 && runner.weather.isRaining
            windy = windy || step.impact.force.x != 0
            drizzly = drizzly || step.impact.impulse != .zero
            if step.events.contains(.lightningWarning) {
                warnings.append(runner.time)
                strikeComing = true
            }
            if step.events.contains(.lightningStrike) {
                strikes.append(runner.time)
                strikeComing = false
            }
            warningShown = warningShown && runner.weather.isLightningWarningActive == strikeComing
            jolts += step.impact.kicks.filter { $0.source == .lightning }
        }
        #expect(wet && windy && drizzly)

        let timeline = schedule.lightningStrikes(until: runner.time)
        let dt = runner.dt
        #expect(strikes.count == timeline.count && strikes.count >= 13)
        // Each strike lands in the step that reaches its time, 0.6 s after its warning started ...
        #expect(zip(strikes, timeline).allSatisfy { $0 >= $1.time && $0 < $1.time + dt + 1e-9 })
        #expect(zip(warnings, timeline).allSatisfy { $0 >= $1.warningTime && $0 < $1.warningTime + dt + 1e-9 })
        #expect(zip(warnings, strikes).allSatisfy { abs($1 - $0 - 0.6) < dt + 1e-9 })
        // ... 8 to 15 s after the previous one, while the HUD shows the warning in between.
        let spacing = zip(strikes, strikes.dropFirst()).map { $1 - $0 }
        #expect(spacing.allSatisfy { $0 > 8 - dt - 1e-9 && $0 < 15 + dt + 1e-9 })
        #expect(warningShown)
        // A strong jolt of 0.8 in the direction every phone agrees on.
        #expect(jolts.count == strikes.count)
        #expect(zip(jolts, timeline).allSatisfy { $0.velocity == $1.direction * 0.8 })
    }

    @Test func lightningNeedsAStormWhenItsWarningStarts() throws {
        let schedule = WeatherSchedule(seed: 29, option: .fixed(.storm), course: .timeTrial(.long))
        let strike = try #require(schedule.lightningStrikes(until: 20).first)
        // The storm begins between the warning and the strike: no warning, so no strike either.
        let lateStorm = WeatherSchedule(seed: 29, stretches: [
            WeatherSchedule.Stretch(meters: 0 ..< 3 * (strike.warningTime + 0.3), conditions: .clear),
            WeatherSchedule.Stretch(
                meters: 3 * (strike.warningTime + 0.3) ..< .infinity,
                conditions: WeatherConditions(kind: .storm, intensity: 1)
            ),
        ])
        var late = SteadyRunner(lateStorm)
        while late.time < strike.time + 1 {
            _ = late.step()
        }
        #expect(!late.events.contains(.lightningWarning) && !late.events.contains(.lightningStrike))

        // The storm ends between the warning and the strike: the strike still follows its warning.
        let earlyEnd = WeatherSchedule(seed: 29, stretches: [
            WeatherSchedule.Stretch(
                meters: 0 ..< 3 * (strike.warningTime + 0.3),
                conditions: WeatherConditions(kind: .storm, intensity: 1)
            ),
            WeatherSchedule.Stretch(meters: 3 * (strike.warningTime + 0.3) ..< .infinity, conditions: .clear),
        ])
        var early = SteadyRunner(earlyEnd)
        var landed: Kick?
        while early.time < strike.time + 1 {
            landed = early.step().impact.kicks.first { $0.source == .lightning } ?? landed
        }
        #expect(early.events.contains(.lightningWarning) && early.events.contains(.lightningStrike))
        #expect(landed?.velocity == strike.direction * 0.8)
    }

    // MARK: Announcements

    @Test func weatherChangesAreAnnouncedWhereTheyHappen() {
        // A start in bad weather is announced once, at the first step.
        var rainy = SteadyRunner(WeatherSchedule(seed: 2, option: .fixed(.rain), course: .timeTrial(.short)))
        #expect(rainy.step().events.first == .weatherChanged(WeatherConditions(kind: .rain, intensity: 1)))
        for _ in 0 ..< 120 * 10 {
            _ = rainy.step()
        }
        #expect(rainy.events.count(where: {
            if case .weatherChanged = $0 {
                true
            } else {
                false
            }
        }) == 1)

        // Zufall starts calm and announces every stretch in the step that enters it.
        let schedule = WeatherSchedule(seed: 4, option: .random, course: .timeTrial(.long))
        var runner = SteadyRunner(schedule)
        var announced: [(meters: ClosedRange<Double>, conditions: WeatherConditions)] = []
        while runner.meters < 600 {
            let from = runner.meters
            for case let .weatherChanged(conditions) in runner.step().events {
                announced.append((from ... runner.meters, conditions))
            }
        }
        let stretches = schedule.stretches(in: 0 ..< 600).dropFirst()
        #expect(announced.map(\.conditions) == stretches.map(\.conditions))
        #expect(zip(announced, stretches).allSatisfy {
            $0.meters.lowerBound < $1.meters.lowerBound && $1.meters.lowerBound <= $0.meters.upperBound
        })
    }

    // MARK: Inside RunEngine

    @Test func endlessRunAnnouncesEveryStage() {
        let schedule = WeatherSchedule(seed: 77, option: .random, course: .endless)
        var engine = RunEngine(config: bottomlessBowl, course: .endless, weather: schedule, localSeed: 1)
        var events: [RunEvent] = []
        for _ in 0 ..< 120 * 125 {
            engine.step(.level, events: &events)
        }
        let changes = events.compactMap { event -> WeatherConditions? in
            if case let .weatherChanged(conditions) = event {
                conditions
            } else {
                nil
            }
        }
        // Calm for the first 100 m, then a stronger stage at 100, 200 and 300 m.
        #expect(engine.meters > 300 && engine.meters < 400)
        #expect(changes.count == 3)
        #expect(changes.allSatisfy { $0.kind != .clear })
        #expect(zip(changes.map(\.intensity), [0.3, 0.4, 0.5]).allSatisfy { abs($0 - $1) < 1e-12 })
        #expect(engine.weather.conditions == schedule.conditions(atMeters: engine.meters))
    }

    @Test(arguments: [WeatherOption.random, .fixed(.storm)])
    func playersOfARaceShareTheWeather(option: WeatherOption) throws {
        let course = Course.timeTrial(.long)
        // For Zufall, a seed that ends in a thunderstorm, so lightning is part of the comparison.
        let seed = try #require((UInt64(1) ... 100).first { seed in
            WeatherSchedule(seed: seed, option: option, course: course).stretches(in: 0 ..< 600)
                .contains { $0.conditions.kind == .storm }
        })
        let schedule = WeatherSchedule(seed: seed, option: option, course: course)
        var first = RunEngine(config: bottomlessBowl, course: course, weather: schedule, localSeed: 1)
        var second = RunEngine(config: bottomlessBowl, course: course, weather: schedule, localSeed: 2)

        // What every phone of the race must agree on (puddle splashes and raindrops push in local directions).
        func shared(_ events: [RunEvent], step: Int) -> [Stamped] {
            events.filter { event in
                switch event {
                case .weatherChanged, .puddle, .lightningWarning, .lightningStrike: true
                case let .kick(kick): kick.source == .lightning
                default: false
                }
            }.map { Stamped(step: step, event: $0) }
        }

        var firstShared: [Stamped] = []
        var secondShared: [Stamped] = []
        var sameSky = true
        for step in 0 ..< 120 * 210 {
            var firstEvents: [RunEvent] = []
            var secondEvents: [RunEvent] = []
            first.step(.level, events: &firstEvents)
            second.step(.level, events: &secondEvents)
            firstShared += shared(firstEvents, step: step)
            secondShared += shared(secondEvents, step: step)
            sameSky = sameSky && first.weather.conditions == second.weather.conditions
                && first.weather.wind == second.weather.wind
                && first.weather.isLightningWarningActive == second.weather.isLightningWarningActive
                && first.weather.isRaining == second.weather.isRaining
        }
        #expect(first.phase == .finished && second.phase == .finished)
        #expect(sameSky)
        #expect(firstShared == secondShared)
        #expect(firstShared.contains { $0.event == .lightningStrike })
        #expect(firstShared.contains { $0.event == .puddle })
        // Footsteps, raindrops and splashes are each phone's own.
        #expect(first.egg != second.egg)
    }

    @Test func raindropsReachTheEggWithoutEvents() {
        var config = GameConfig()
        // Footsteps without force and no puddles nearby leave raindrops as the only push.
        config.stepKick = 0 ... 0
        config.puddleSpacing = 1000 ... 1000
        let course = Course.timeTrial(.short)
        let rain = WeatherSchedule(seed: 4, option: .fixed(.rain), course: course, config: config)
        var wet = RunEngine(config: config, course: course, weather: rain, localSeed: 9)
        var dry = RunEngine(config: config, course: course, weather: .clear, localSeed: 9)
        var wetEvents: [RunEvent] = []
        var dryEvents: [RunEvent] = []
        for _ in 0 ..< 120 * 5 {
            wet.step(.level, events: &wetEvents)
            dry.step(.level, events: &dryEvents)
        }
        #expect(dry.egg.position == .zero)
        #expect(wet.egg.position != .zero)
        #expect(wetEvents.allSatisfy { event in
            if case let .kick(kick) = event {
                kick.source == .footstep
            } else {
                true
            }
        })
    }

    @Test func weatherGoesOnWhileTheNextEggIsPlaced() {
        var config = GameConfig()
        // A strike every second, so some land while the runner waits for a new egg.
        config.lightningInterval = 1 ... 1
        let course = Course.timeTrial(.long)
        let schedule = WeatherSchedule(seed: 8, option: .fixed(.storm), course: course, config: config)
        var engine = RunEngine(config: config, course: course, weather: schedule, localSeed: 3)
        var events: [RunEvent] = []
        let steep = RunEngine.Input(tilt: SIMD2(radians(30), 0))
        while engine.phase == .running {
            engine.step(steep, events: &events)
        }
        guard case .recovering = engine.phase else {
            Issue.record("expected the egg to break, phase is \(engine.phase)")
            return
        }

        var recovery: [RunEvent] = []
        var followsTimeline = true
        while case .recovering = engine.phase {
            engine.step(steep, events: &recovery)
            let expected = schedule.gust(at: engine.elapsed)?.force(at: engine.elapsed) ?? 0
            followsTimeline = followsTimeline && engine.weather.wind == expected
        }
        #expect(followsTimeline)
        // The storm flashes on schedule, but there is no egg to jolt.
        #expect(recovery.contains(.lightningStrike))
        #expect(!recovery.contains {
            if case .kick = $0 {
                true
            } else {
                false
            }
        })
        #expect(recovery.last == .newEgg)
    }
}
