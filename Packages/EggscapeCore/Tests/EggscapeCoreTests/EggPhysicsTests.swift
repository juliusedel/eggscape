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

    @Test(arguments: [2.0, 5.0, 8.0])
    func smallTiltKeepsEgg(degrees: Double) {
        #expect(!hold(SIMD2(radians(degrees), 0), for: 20).fell)
        #expect(!hold(SIMD2(0, radians(degrees)), for: 20).fell)
    }

    @Test func diagonalTiltAddsUp() {
        // Both axes count towards the elliptical rim distance: 5° diagonally is fine, 8° is not, though 8° on either
        // axis alone is.
        #expect(!hold(SIMD2(radians(-5), radians(-5)), for: 20).fell)
        #expect(hold(SIMD2(radians(8), radians(8)), for: 20).fell)
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
        // Tilted slowly, the egg tolerates about 11° sideways.
        #expect(!hold(SIMD2(radians(10), 0), for: 40, rampSeconds: 20).fell)
        #expect(hold(SIMD2(radians(12), 0), for: 40, rampSeconds: 20).fell)
    }

    @Test func staticThresholdAlongHandle() {
        // ... and about 15° forward or backward, because the bowl is longer along the handle.
        #expect(!hold(SIMD2(0, radians(13.5)), for: 40, rampSeconds: 20).fell)
        #expect(hold(SIMD2(0, radians(15.5)), for: 40, rampSeconds: 20).fell)
        #expect(hold(SIMD2(0, radians(-15.5)), for: 40, rampSeconds: 20).fell)
    }

    @Test func abruptTiltDropsEarlier() {
        // The underdamped bowl overshoots, so a sudden tilt drops the egg from about 9° / 12°.
        #expect(!hold(SIMD2(radians(8), 0), for: 10).fell)
        #expect(hold(SIMD2(radians(9.5), 0), for: 10).fell)
        #expect(!hold(SIMD2(0, radians(11)), for: 10).fell)
        #expect(hold(SIMD2(0, radians(13)), for: 10).fell)
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
        // A strong footstep moves the egg visibly but not even half way to the tipping point, and the bowl brings it
        // back.
        #expect(peak > 0.1 && peak < 0.2)
        #expect(egg.rimDistance < 0.01)
    }

    @Test func rimDistanceIsElliptical() {
        var egg = EggPhysics()
        egg.kick(SIMD2(0.5, 0))
        egg.step(dt: 1, tilt: .zero, dampingScale: 0)
        // After one second at 0.5 units/s the egg sits short of the sideways tipping point.
        #expect(egg.rimDistance == abs(egg.position.x) / 0.57)
        #expect(egg.rimDistance < 1)
    }
}
