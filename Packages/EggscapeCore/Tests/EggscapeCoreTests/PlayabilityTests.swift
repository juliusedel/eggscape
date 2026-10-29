@testable import EggscapeCore
import Foundation
import Testing

/// Someone who watches the egg and tilts against it: a PD controller on the egg's position and velocity that reacts
/// `reaction` seconds late (eyes, hands and the tilt filter together) and never tilts the phone further than 12°.
private struct AttentivePlayer {
    /// Radians of tilt per bowl unit the egg is off center ...
    var positionGain = 0.6
    /// ... and per bowl unit per second it rolls.
    var velocityGain = 0.35
    var maxTilt = radians(12)
    /// What the player saw in the last `reaction` seconds, oldest first.
    private var seen: [(position: SIMD2<Double>, velocity: SIMD2<Double>)] = []
    private let delay: Int

    init(reaction: Double = 0.15) {
        delay = Int((reaction * GameConfig.standard.simulationRate).rounded())
    }

    /// The tilt for this step, in answer to the egg as it was `reaction` seconds ago; level until then.
    mutating func tilt(watching egg: EggPhysics) -> SIMD2<Double> {
        seen.append((egg.position, egg.velocity))
        guard seen.count > delay else { return .zero }
        let late = seen.removeFirst()
        let correction = -(positionGain * late.position + velocityGain * late.velocity)
        return SIMD2(min(max(correction.x, -maxTilt), maxTilt), min(max(correction.y, -maxTilt), maxTilt))
    }

    /// No egg in the bowl: nothing to remember once the next one lies there.
    mutating func forget() {
        seen.removeAll()
    }
}

/// Runs `course` until it is over or `seconds` have passed, steered by `player`, or with the phone held level without
/// one.
private func play(
    _ course: Course,
    weather: WeatherOption,
    raceSeed: UInt64 = 0xE665_CA9E,
    localSeed: UInt64 = 7,
    player: AttentivePlayer? = nil,
    sprint: Bool = false,
    seconds: Double = 400
) -> RunEngine {
    var engine = RunEngine(
        course: course,
        weather: WeatherSchedule(seed: raceSeed, option: weather, course: course),
        localSeed: localSeed
    )
    var player = player
    var events: [RunEvent] = []
    for _ in 0 ..< Int(seconds * engine.config.simulationRate) where !engine.isOver {
        var tilt = SIMD2<Double>.zero
        if engine.phase == .running {
            tilt = player?.tilt(watching: engine.egg) ?? .zero
        } else {
            player?.forget()
        }
        engine.step(RunEngine.Input(tilt: tilt, sprint: sprint), events: &events)
    }
    return engine
}

/// The tipping point is tight: the egg falls more easily than in a roomy bowl. These runs make sure the game stays
/// fair anyway, for a player who pays attention.
struct PlayabilityTests {
    @Test(arguments: [UInt64(1), 7, 42])
    func attentivePlayerFinishesTheShortTrialWithoutLosingAnEgg(localSeed: UInt64) {
        let engine = play(.timeTrial(.short), weather: .off, localSeed: localSeed, player: AttentivePlayer())
        #expect(engine.phase == .finished)
        #expect(engine.eggsLost == 0)
    }

    @Test func attentivePlayerCanSprintThroughCalmWeather() {
        // Sprinting shakes the egg hard, but it can be held.
        let engine = play(.timeTrial(.short), weather: .off, player: AttentivePlayer(), sprint: true)
        #expect(engine.phase == .finished)
        #expect(engine.eggsLost == 0)
        #expect(engine.elapsed < 31)
    }

    @Test func attentivePlayerKeepsAnEggThroughTheLongStorm() {
        // Wind, a slippery bowl, puddles and lightning at full strength for 600 m: the hardest race there is.
        let engine = play(.timeTrial(.long), weather: .fixed(.storm), player: AttentivePlayer())
        #expect(engine.phase == .finished)
        #expect(engine.eggsLeft >= 1)
    }

    @Test func carelessPlayerLosesAnEggSprintingInTheWind() {
        // Holding the phone level is no strategy: sprinting through gusts drops the egg within seconds.
        let engine = play(.timeTrial(.long), weather: .fixed(.wind), sprint: true, seconds: 20)
        #expect(engine.eggsLost >= 1)
    }

    @Test func strongestGustCanBeHeld() {
        let config = GameConfig.standard
        let egg = EggPhysics(config: config)
        let gust = SIMD2(config.windForce.upperBound, 0)
        // Left alone, the egg comes to rest two thirds of the way to the tipping point ...
        let drift = egg.restingPosition(tilt: .zero, force: gust).x / config.bowlRadiusX
        #expect(abs(drift - 2.0 / 3) < 0.01)
        // ... and leaning against the gust by about 7° keeps it in the middle, well short of the 11° that tip it.
        let counterTilt = asin(gust.x / config.gravity)
        #expect(counterTilt < radians(7.5))
        #expect(abs(egg.restingPosition(tilt: SIMD2(-counterTilt, 0), force: gust).x) < 1e-12)
    }

    @Test func strikeAloneNeverDropsACenteredEgg() {
        let config = GameConfig.standard
        var egg = EggPhysics(config: config)
        // Sideways, the narrow way, in the wet storm bowl, where the egg swings out furthest.
        egg.kick(SIMD2(config.lightningKick, 0))
        var peak = 0.0
        for _ in 0 ..< Int(5 * config.simulationRate) {
            egg.step(dt: 1 / config.simulationRate, tilt: .zero, dampingScale: config.rainDampingFactor)
            peak = max(peak, egg.rimDistance)
        }
        // Still a real jolt: a little more than half the way to the tipping point.
        #expect(peak > 0.5 && peak < 0.65)
    }
}
