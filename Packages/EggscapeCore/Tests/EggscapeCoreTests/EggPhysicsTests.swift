@testable import EggscapeCore
import Foundation
import Testing

func radians(_ degrees: Double) -> Double {
    degrees * .pi / 180
}

/// Holds `tilt` (optionally ramped in linearly) without any disturbance.
private func hold(_ tilt: SIMD2<Double>, for seconds: Double, rampSeconds: Double = 0) -> (peak: Double, fell: Bool) {
    var egg = EggPhysics()
    let dt = 1 / egg.config.simulationRate
    var peak = 0.0
    for index in 0 ..< Int(seconds / dt) {
        let ramp = rampSeconds > 0 ? min(Double(index) * dt / rampSeconds, 1) : 1
        egg.step(dt: dt, tilt: tilt * ramp)
        peak = max(peak, egg.rimDistance)
        if egg.hasFallen {
            return (peak, true)
        }
    }
    return (peak, false)
}

struct EggPhysicsTests {
    @Test func levelSpoonKeepsEggCentered() {
        #expect(hold(.zero, for: 10).peak == 0)
    }

    @Test(arguments: [2.0, 6.0, 10.0])
    func smallTiltKeepsEgg(degrees: Double) {
        #expect(!hold(SIMD2(radians(degrees), 0), for: 20).fell)
        #expect(!hold(SIMD2(0, radians(degrees)), for: 20).fell)
    }

    @Test func diagonalTiltAddsUp() {
        // Both axes count towards the elliptical rim distance: 6° diagonally is fine, 10° is not.
        #expect(!hold(SIMD2(radians(-6), radians(-6)), for: 20).fell)
        #expect(hold(SIMD2(radians(10), radians(10)), for: 20).fell)
    }

    @Test func settlesAtRestingPosition() {
        var egg = EggPhysics()
        let tilt = SIMD2(radians(8), radians(-6))
        for _ in 0 ..< 120 * 30 {
            egg.step(dt: 1.0 / 120, tilt: tilt)
        }
        let rest = egg.restingPosition(tilt: tilt)
        #expect(abs(egg.position.x - rest.x) < 1e-6)
        #expect(abs(egg.position.y - rest.y) < 1e-6)
        #expect(abs(rest.x - 3 * sin(radians(8))) < 1e-12)
    }

    @Test func staticThresholdSideways() {
        // Tilted slowly, the egg tolerates about 14.5° sideways.
        #expect(!hold(SIMD2(radians(13.5), 0), for: 40, rampSeconds: 20).fell)
        #expect(hold(SIMD2(radians(15.5), 0), for: 40, rampSeconds: 20).fell)
    }

    @Test func staticThresholdAlongHandle() {
        // ... and about 19.5° forward or backward, because the bowl is longer along the handle.
        #expect(!hold(SIMD2(0, radians(18.5)), for: 40, rampSeconds: 20).fell)
        #expect(hold(SIMD2(0, radians(20.5)), for: 40, rampSeconds: 20).fell)
        #expect(hold(SIMD2(0, radians(-20.5)), for: 40, rampSeconds: 20).fell)
    }

    @Test func abruptTiltDropsEarlier() {
        // The underdamped bowl overshoots, so a sudden tilt drops the egg from about 12° / 16°.
        #expect(!hold(SIMD2(radians(11), 0), for: 10).fell)
        #expect(hold(SIMD2(radians(12.5), 0), for: 10).fell)
        #expect(!hold(SIMD2(0, radians(15)), for: 10).fell)
        #expect(hold(SIMD2(0, radians(17)), for: 10).fell)
    }

    @Test func overshootIsAboutTwentyThreePercent() {
        var egg = EggPhysics()
        let tilt = SIMD2(radians(5), 0)
        var peak = 0.0
        for _ in 0 ..< 120 * 5 {
            egg.step(dt: 1.0 / 120, tilt: tilt)
            peak = max(peak, egg.position.x)
        }
        let overshoot = peak / egg.restingPosition(tilt: tilt).x - 1
        #expect(overshoot > 0.21 && overshoot < 0.25)
    }

    @Test func kickWobblesAndSettles() {
        var egg = EggPhysics()
        egg.kick(SIMD2(0.35, 0))
        var peak = 0.0
        for _ in 0 ..< 120 * 10 {
            egg.step(dt: 1.0 / 120, tilt: .zero)
            peak = max(peak, egg.position.x)
        }
        // A strong footstep moves the egg visibly but nowhere near the rim, and the bowl brings it back.
        #expect(peak > 0.1 && peak < 0.2)
        #expect(egg.rimDistance < 0.01)
    }

    @Test func rimDistanceIsElliptical() {
        var egg = EggPhysics()
        egg.kick(SIMD2(0.75, 0))
        egg.step(dt: 1, tilt: .zero, dampingScale: 0)
        // After one second at 0.75 units/s, minus the bowl's pull, the egg sits short of the sideways rim.
        #expect(egg.rimDistance == abs(egg.position.x) / 0.75)
    }
}
