@testable import EggscapeCore
import Testing

private let courses: [Course] = [.timeTrial(.short), .timeTrial(.medium), .timeTrial(.long), .endless]

/// How far along the track to look: the whole course, or the first kilometer of Endlos.
private func span(_ course: Course) -> Double {
    course.length ?? 1000
}

/// Difficulty ladder of the kinds; Zufall may only climb it along the track.
private func tier(_ kind: WeatherKind) -> Int {
    switch kind {
    case .clear: 0
    case .wind, .rain: 1
    case .storm: 2
    }
}

struct WeatherScheduleTests {
    // MARK: Determinism

    @Test(arguments: courses)
    func sameSeedGivesTheSamePlan(course: Course) {
        let first = WeatherSchedule(seed: 42, option: .random, course: course)
        let second = WeatherSchedule(seed: 42, option: .random, course: course)
        #expect(first == second)
        #expect(first.stretches(in: 0 ..< span(course)) == second.stretches(in: 0 ..< span(course)))
        #expect(first.gusts(until: 600) == second.gusts(until: 600))
        #expect(first.lightningStrikes(until: 600) == second.lightningStrikes(until: 600))
        #expect(first.puddles(in: 0 ... span(course)) == second.puddles(in: 0 ... span(course)))
    }

    @Test(arguments: courses)
    func differentSeedsGiveDifferentPlans(course: Course) {
        let first = WeatherSchedule(seed: 1, option: .random, course: course)
        let second = WeatherSchedule(seed: 2, option: .random, course: course)
        #expect(first != second)
        #expect(first.stretches(in: 0 ..< span(course)) != second.stretches(in: 0 ..< span(course)))
        #expect(first.gusts(until: 600) != second.gusts(until: 600))
        #expect(first.lightningStrikes(until: 600).map(\.time) != second.lightningStrikes(until: 600).map(\.time))
        #expect(first.puddleSpots(in: 0 ... 1000) != second.puddleSpots(in: 0 ... 1000))
    }

    @Test func timelinesDependOnTheSeedAlone() {
        // The sky and the puddle spots are the same whatever weather was picked; only their effect differs.
        let calm = WeatherSchedule(seed: 8, option: .off, course: .timeTrial(.short))
        let stormy = WeatherSchedule(seed: 8, option: .fixed(.storm), course: .endless)
        #expect(calm.gusts(until: 300) == stormy.gusts(until: 300))
        #expect(calm.lightningStrikes(until: 300) == stormy.lightningStrikes(until: 300))
        #expect(calm.puddleSpots(in: 0 ... 600) == stormy.puddleSpots(in: 0 ... 600))
    }

    // MARK: Options

    @Test(arguments: [WeatherOption.off, .fixed(.clear)])
    func offAndClearMeanNoWeatherAtAll(option: WeatherOption) {
        for course in courses {
            let schedule = WeatherSchedule(seed: 9, option: option, course: course)
            let stretches = schedule.stretches(in: 0 ..< 5000)
            #expect(stretches.count == 1)
            #expect(stretches.allSatisfy { $0.conditions == .clear && $0.footstepScale == 1 })
            #expect(schedule.puddles(in: 0 ... 5000).isEmpty)
        }
        #expect(WeatherSchedule.clear.stretches(in: 0 ..< 5000).map(\.conditions) == [.clear])
    }

    @Test(arguments: [WeatherKind.wind, .rain, .storm])
    func fixedWeatherIsAtFullStrengthAllTheWay(kind: WeatherKind) {
        for distance in RaceDistance.allCases {
            let schedule = WeatherSchedule(seed: 5, option: .fixed(kind), course: .timeTrial(distance))
            let stretches = schedule.stretches(in: 0 ..< distance.meters)
            #expect(stretches.map(\.conditions) == [WeatherConditions(kind: kind, intensity: 1)])
            #expect(stretches.allSatisfy { $0.footstepScale == 1 })
        }
    }

    @Test(arguments: RaceDistance.allCases)
    func randomWeatherEscalatesTowardsTheFinish(distance: RaceDistance) throws {
        var stormyFinishes = 0
        var kinds = Set<WeatherKind>()
        for seed in UInt64(1) ... 200 {
            let schedule = WeatherSchedule(seed: seed, option: .random, course: .timeTrial(distance))
            let stretches = schedule.stretches(in: 0 ..< distance.meters)
            let calm = try #require(stretches.first)
            let finale = try #require(stretches.last)

            // A calm start of 20 to 40 meters, but at most half the course ...
            let half = distance.meters / 2
            #expect(calm.conditions == .clear)
            #expect(calm.meters.lowerBound == 0 && (min(20, half) ... min(40, half)).contains(calm.meters.upperBound))
            // ... then at least two stretches of weather that tile the rest of the track ...
            let weather = stretches.dropFirst()
            #expect(weather.count >= 2)
            #expect(zip(stretches, weather).allSatisfy { $0.meters.upperBound == $1.meters.lowerBound })
            #expect(finale.meters.lowerBound < distance.meters && finale.meters.upperBound == .infinity)
            #expect(weather.allSatisfy { $0.conditions.kind != .clear && $0.footstepScale == 1 })
            // ... and only ever get harder: kinds climb the ladder, intensity rises to full strength at the finish.
            #expect(zip(weather, weather.dropFirst()).allSatisfy {
                tier($0.conditions.kind) <= tier($1.conditions.kind) && $0.conditions.intensity < $1.conditions
                    .intensity
            })
            #expect((0.3 ... 0.5).contains(weather.first?.conditions.intensity ?? 0))
            #expect(finale.conditions.intensity == 1)

            stormyFinishes += finale.conditions.kind == .storm ? 1 : 0
            kinds.formUnion(stretches.map(\.conditions.kind))
        }
        // The seed picks the kinds: every kind shows up, and about 60 % of the races end in a thunderstorm.
        #expect(kinds == Set(WeatherKind.allCases))
        #expect(stormyFinishes > 90 && stormyFinishes < 150)
    }

    // MARK: Endlos

    @Test func endlessIntensifiesEveryHundredMeters() {
        let schedule = WeatherSchedule(seed: 31, option: .random, course: .endless)
        let stages = schedule.stretches(in: 0 ..< 2000)
        #expect(stages.count == 20)
        for (index, stage) in stages.enumerated() {
            let start = Double(index) * 100
            #expect(stage.meters == start ..< start + 100)
            // Constant within a stage.
            #expect(schedule.stretch(atMeters: start) == stage)
            #expect(schedule.stretch(atMeters: (start + 100).nextDown) == stage)
        }

        // Stage 0 is clear, then 0.3, 0.4, ... up to full strength at stage 8, where it stays.
        #expect(stages[0].conditions == .clear)
        #expect(stages.dropFirst().allSatisfy { $0.conditions.kind != .clear })
        let intensities = stages.map(\.conditions.intensity)
        for stage in 1 ... 8 {
            #expect(abs(intensities[stage] - (0.3 + 0.1 * Double(stage - 1))) < 1e-12)
        }
        #expect(intensities[8...].allSatisfy { $0 == 1 })
        #expect(zip(intensities, intensities.dropFirst()).allSatisfy { $0 <= $1 })

        // Only then do footsteps get stronger, 5 % per stage up to the cap of 1.25 at stage 13.
        let footsteps = stages.map(\.footstepScale)
        #expect(footsteps[...8].allSatisfy { $0 == 1 })
        for stage in 9 ... 13 {
            #expect(abs(footsteps[stage] - (1 + 0.05 * Double(stage - 8))) < 1e-12)
        }
        #expect(footsteps[13...].allSatisfy { $0 == 1.25 })

        // No thunderstorm in the first 300 m.
        #expect(stages[1 ... 2].allSatisfy { $0.conditions.kind != .storm })
    }

    @Test func endlessStagesNeedNoHistory() {
        // Any stage comes straight from the seed and the stage number, however far the runner gets.
        let schedule = WeatherSchedule(seed: 31, option: .random, course: .endless)
        let far = schedule.stretch(atMeters: 1_234_567.8)
        #expect(far.meters == 1_234_500 ..< 1_234_600)
        #expect(far.conditions.intensity == 1)
        #expect(far.footstepScale == 1.25)
        #expect(far == WeatherSchedule(seed: 31, option: .random, course: .endless).stretch(atMeters: 1_234_501))

        // Every kind shows up along the way, thunderstorms included.
        let kinds = Set(schedule.stretches(in: 0 ..< 5000).map(\.conditions.kind))
        #expect(kinds == Set(WeatherKind.allCases))

        // A fixed kind keeps its kind but still starts calm and intensifies.
        let rainy = WeatherSchedule(seed: 31, option: .fixed(.rain), course: .endless)
        #expect(rainy.conditions(atMeters: 50) == .clear)
        #expect(rainy.stretches(in: 100 ..< 1000).allSatisfy { $0.conditions.kind == .rain })
        #expect(rainy.conditions(atMeters: 150).intensity == 0.3)
        #expect(rainy.conditions(atMeters: 950).intensity == 1)
    }

    @Test func stagesContainTheirBoundaries() {
        let schedule = WeatherSchedule(seed: 3, option: .random, course: .endless)
        for stage in 0 ... 300 {
            for meters in [Double(stage) * 100, (Double(stage) * 100).nextDown, Double(stage) * 100 + 0.1] {
                #expect(schedule.stretch(atMeters: meters).meters.contains(meters) || meters < 0)
            }
        }
        #expect(schedule.stretch(atMeters: -5).conditions == .clear)
    }

    // MARK: Timelines

    @Test func gustsSwellHoldAndDieDown() {
        let config = GameConfig.standard
        let gusts = WeatherSchedule(seed: 7, option: .fixed(.wind), course: .endless).gusts(until: 1200)
        #expect(gusts.count > 200)

        // Peak force, hold and calm gap stay within the tunables.
        #expect(gusts.allSatisfy { config.windForce.contains($0.peak) && config.gustHold.contains($0.hold) })
        #expect(gusts.allSatisfy { $0.ramp == config.gustRamp && $0.decay == config.gustDecay })
        #expect(gusts.allSatisfy { abs($0.direction) == 1 })
        let gaps = zip([0] + gusts.map(\.end), gusts).map { $1.start - $0 }
        #expect(gaps.allSatisfy { $0 >= config.gustGap.lowerBound - 1e-9 && $0 <= config.gustGap.upperBound + 1e-9 })

        // The envelope: calm at both ends, eased up over 0.5 s, flat while it holds, eased down over 1 s.
        for gust in gusts.prefix(20) {
            let holdEnd = gust.start + gust.ramp + gust.hold
            #expect(gust.envelope(at: gust.start) == 0)
            #expect(gust.envelope(at: gust.start - 0.1) == 0)
            #expect(abs(gust.envelope(at: gust.start + gust.ramp) - 1) < 1e-9)
            #expect(gust.envelope(at: gust.start + gust.ramp + gust.hold / 2) == 1)
            #expect(abs(gust.envelope(at: holdEnd) - 1) < 1e-9)
            #expect(gust.envelope(at: gust.end) < 1e-9)
            #expect(gust.envelope(at: gust.end + 0.1) == 0)
            #expect(abs(gust.envelope(at: gust.start + gust.ramp / 2) - 0.5) < 1e-9)
            let rise = (0 ... 50).map { gust.envelope(at: gust.start + gust.ramp * Double($0) / 50) }
            let fall = (0 ... 50).map { gust.envelope(at: holdEnd + gust.decay * Double($0) / 50) }
            #expect(zip(rise, rise.dropFirst()).allSatisfy { $0 <= $1 })
            #expect(zip(fall, fall.dropFirst()).allSatisfy { $0 >= $1 })
            let whole = (0 ... 400).map { gust.start - 0.5 + (gust.end - gust.start + 1) * Double($0) / 400 }
            #expect(whole.allSatisfy { (0 ... 1).contains(gust.envelope(at: $0)) })
            #expect(whole.allSatisfy { abs(gust.force(at: $0)) <= gust.peak })
        }

        // `gust(at:)` finds the gust that is blowing and nothing during a calm gap.
        let third = gusts[2]
        #expect(WeatherSchedule(seed: 7, option: .off, course: .endless).gust(at: third.start + 0.2) == third)
        #expect(WeatherSchedule(seed: 7, option: .off, course: .endless).gust(at: third.end + 1e-6) == nil)
    }

    @Test func windDirectionFlipsBetweenSomeGusts() {
        let gusts = WeatherSchedule(seed: 7, option: .fixed(.wind), course: .endless).gusts(until: 4000)
        let flips = zip(gusts, gusts.dropFirst()).count(where: { $0.direction != $1.direction })
        let share = Double(flips) / Double(gusts.count - 1)
        // `windFlipChance` is 0.35: the wind turns now and then, but mostly keeps blowing from one side.
        #expect(share > 0.28 && share < 0.42)
        #expect(Set(gusts.map(\.direction)) == [1, -1])
    }

    @Test func lightningStrikesEveryEightToFifteenSeconds() throws {
        let strikes = WeatherSchedule(seed: 12, option: .fixed(.storm), course: .timeTrial(.long))
            .lightningStrikes(until: 3000)
        #expect(strikes.count > 190 && strikes.count < 380)
        let first = try #require(strikes.first)
        #expect((8 ... 15).contains(first.time))
        let spacing = zip(strikes, strikes.dropFirst()).map { $1.time - $0.time }
        #expect(spacing.allSatisfy { $0 >= 8 - 1e-9 && $0 <= 15 + 1e-9 })
        #expect(strikes.allSatisfy { abs($0.time - $0.warningTime - 0.6) < 1e-9 })
        #expect(strikes.allSatisfy { abs(($0.direction * $0.direction).sum() - 1) < 1e-12 })
    }

    @Test func puddlesLieAlongTheTrackAndHoldWaterWhereItRains() {
        // Fixed rain runs on past the finish line, so 600 m of track hold enough puddles to check their spacing.
        let rainy = WeatherSchedule(seed: 21, option: .fixed(.rain), course: .timeTrial(.long))
        let positions = rainy.puddles(in: 0 ... 600)
        #expect(positions == rainy.puddleSpots(in: 0 ... 600))
        let spacing = zip([0] + positions, positions).map { $1 - $0 }
        #expect(spacing.allSatisfy { $0 >= 25 - 1e-9 && $0 <= 60 + 1e-9 })
        #expect(positions.count >= 9)
        #expect(rainy.puddles(in: 200 ... 300) == positions.filter { (200 ... 300).contains($0) })

        // The same seed lays out the same spots, but without rain they stay dry.
        let windy = WeatherSchedule(seed: 21, option: .fixed(.wind), course: .timeTrial(.long))
        #expect(windy.puddleSpots(in: 0 ... 600) == positions)
        #expect(windy.puddles(in: 0 ... 600).isEmpty)
    }
}
