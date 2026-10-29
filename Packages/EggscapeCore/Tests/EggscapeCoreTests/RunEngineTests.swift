@testable import EggscapeCore
import Testing

private func run(
    _ engine: inout RunEngine,
    seconds: Double,
    input: RunEngine.Input = .level,
    events: inout [RunEvent]
) {
    for _ in 0 ..< Int(seconds * engine.config.simulationRate) {
        engine.step(input, events: &events)
    }
}

private func makeEngine(_ course: Course, localSeed: UInt64 = 7) -> RunEngine {
    RunEngine(course: course, weather: .clear, localSeed: localSeed)
}

struct RunEngineTests {
    @Test func finishesShortCourseAtRunningSpeed() throws {
        let length = RaceDistance.short.meters
        var engine = makeEngine(.timeTrial(.short))
        var events: [RunEvent] = []
        run(&engine, seconds: 60, events: &events)

        #expect(engine.phase == .finished)
        #expect(engine.meters == length)
        #expect(engine.eggsLeft == 3)
        let finish = try #require(events.compactMap { event -> Double? in
            if case let .finished(time) = event {
                time
            } else {
                nil
            }
        }.first)
        // The course at 3 m/s plus the quarter second it takes to get going.
        let cruising = length / engine.config.runSpeed
        #expect(finish > cruising && finish < cruising + 0.5)
    }

    @Test func footstepsFollowTheCadence() {
        var engine = makeEngine(.endless)
        var events: [RunEvent] = []
        run(&engine, seconds: 10, events: &events)
        let steps = events.filter {
            if case .footstep = $0 {
                true
            } else {
                false
            }
        }.count
        #expect((23 ... 25).contains(steps))
    }

    @Test func sprintingIsFasterAndShakier() {
        var engine = makeEngine(.endless)
        var events: [RunEvent] = []
        run(&engine, seconds: 2, input: RunEngine.Input(sprint: true), events: &events)
        #expect(abs(engine.speed - 5) < 0.01)
        let kicks = events.compactMap { event -> Double? in
            if case let .kick(kick) = event {
                (kick.velocity * kick.velocity).sum().squareRoot()
            } else {
                nil
            }
        }
        #expect(kicks.allSatisfy { $0 >= 0.15 * 1.8 - 1e-9 && $0 <= 0.35 * 1.8 + 1e-9 })
    }

    @Test func losingAllEggsEndsTheRun() {
        var engine = makeEngine(.timeTrial(.long))
        var events: [RunEvent] = []
        let steepTilt = RunEngine.Input(tilt: SIMD2(radians(25), 0))

        while engine.phase == .running, engine.elapsed < 5 {
            engine.step(steepTilt, events: &events)
        }
        guard case .recovering = engine.phase else {
            Issue.record("expected the first egg to break, phase is \(engine.phase)")
            return
        }
        #expect(engine.eggsLeft == 2)

        // The runner stands still while the next egg is placed.
        let metersAtDrop = engine.meters
        run(&engine, seconds: 1.9, input: steepTilt, events: &events)
        #expect(engine.meters == metersAtDrop)
        #expect(!events.contains(.newEgg))

        run(&engine, seconds: 10, input: steepTilt, events: &events)
        #expect(engine.phase == .over)
        #expect(engine.eggsLeft == 0)
        #expect(engine.eggsLost == 3)
        #expect(events.filter {
            if case .eggDropped = $0 {
                true
            } else {
                false
            }
        }.count == 3)
        #expect(events.filter { $0 == .newEgg }.count == 2)
        #expect(events.contains {
            if case .runOver = $0 {
                true
            } else {
                false
            }
        })
    }

    @Test func endlessRunsUntilTheLastEgg() {
        var engine = makeEngine(.endless)
        var events: [RunEvent] = []
        run(&engine, seconds: 120, events: &events)
        #expect(engine.phase == .running)
        #expect(engine.meters > 355 && engine.meters < 360)
        #expect(engine.progress == nil)
    }

    @Test func sameSeedsAndInputsGiveTheSameRun() {
        // Endless, so no finish line ends the comparison early.
        var first = makeEngine(.endless, localSeed: 99)
        var second = makeEngine(.endless, localSeed: 99)
        var events: [RunEvent] = []
        let input = RunEngine.Input(tilt: SIMD2(radians(3), radians(-2)), sprint: true)
        run(&first, seconds: 20, input: input, events: &events)
        run(&second, seconds: 20, input: input, events: &events)
        #expect(first.egg == second.egg)
        #expect(first.meters == second.meters)
    }

    @Test func warmUpNeverDropsTheEgg() {
        var engine = makeEngine(.timeTrial(.short))
        for _ in 0 ..< 600 {
            engine.warmUp(RunEngine.Input(tilt: SIMD2(radians(30), radians(30))))
        }
        #expect(!engine.egg.hasFallen)
        #expect(engine.meters == 0)
        #expect(engine.eggsLeft == 3)
    }
}
