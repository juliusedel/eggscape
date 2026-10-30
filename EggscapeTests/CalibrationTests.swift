@testable import Eggscape
import EggscapeCore
import Foundation
import Testing

private func radians(_ degrees: Double) -> Double {
    degrees * .pi / 180
}

private func degrees(_ radians: Double) -> Double {
    radians * 180 / .pi
}

struct TiltMathTests {
    @Test func flatPhoneIsLevel() {
        #expect(TiltMath.tilt(gravity: SIMD3(0, 0, -1)) == .zero)
    }

    @Test func rightEdgeDownIsPositiveX() {
        let gravity = SIMD3(sin(radians(10)), 0, -cos(radians(10)))
        let tilt = TiltMath.tilt(gravity: gravity)
        #expect(abs(degrees(tilt.x) - 10) < 1e-9)
        #expect(tilt.y == 0)
    }

    @Test func topEdgeDownIsPositiveY() {
        let gravity = SIMD3(0, sin(radians(25)), -cos(radians(25)))
        #expect(abs(degrees(TiltMath.tilt(gravity: gravity).y) - 25) < 1e-9)
    }

    @Test func phoneHeldTowardsThePlayerTiltsBackwards() {
        // Top edge raised by 40°: the usual way to hold a phone while walking.
        let gravity = SIMD3(0, -sin(radians(40)), -cos(radians(40)))
        #expect(abs(degrees(TiltMath.tilt(gravity: gravity).y) + 40) < 1e-9)
    }
}

struct GravityLowPassTests {
    @Test func firstSamplePassesThrough() {
        var filter = GravityLowPass(timeConstant: 0.05)
        #expect(filter.add(SIMD3(0.1, 0.2, -0.9), at: 1) == SIMD3(0.1, 0.2, -0.9))
    }

    @Test func reachesAboutTwoThirdsAfterOneTimeConstant() {
        var filter = GravityLowPass(timeConstant: 0.05)
        _ = filter.add(SIMD3(0, 0, -1), at: 0)
        var value = SIMD3<Double>(0, 0, -1)
        // 100 Hz samples of a step input; after 50 ms a first-order filter is at 1 − 1/e ≈ 63 %.
        for index in 1 ... 5 {
            value = filter.add(SIMD3(1, 0, -1), at: Double(index) * 0.01)
        }
        #expect(value.x > 0.55 && value.x < 0.65)
    }

    @Test func ignoresStaleTimestamps() {
        var filter = GravityLowPass(timeConstant: 0.05)
        _ = filter.add(SIMD3(0, 0, -1), at: 2)
        #expect(filter.add(SIMD3(1, 0, -1), at: 1) == SIMD3(1, 0, -1))
    }
}

struct TiltCalibrationTests {
    @Test func calibratedPoseIsLevel() {
        var calibration = TiltCalibration()
        let pose = SIMD2(radians(4), radians(-38))
        calibration.calibrate(at: pose)
        #expect(calibration.apply(pose) == .zero)
    }

    @Test func tiltIsMeasuredFromTheCalibratedPose() {
        var calibration = TiltCalibration()
        calibration.calibrate(at: SIMD2(0, radians(-38)))
        let tilt = calibration.apply(SIMD2(radians(4), radians(-34)))
        // 4° each, minus the 0.5° dead zone, times the gain of 2.5.
        #expect(abs(degrees(tilt.x) - 8.75) < 1e-9)
        #expect(abs(degrees(tilt.y) - 8.75) < 1e-9)
    }

    @Test func defaultSteersTwoAndAHalfTimesAsStrongly() {
        let calibration = TiltCalibration()
        #expect(GameConfig.standard.tiltGain == 2.5)
        // 4.5° on the phone are 4° beyond the dead zone, which the egg feels as 10°.
        #expect(abs(degrees(calibration.apply(SIMD2(radians(4.5), 0)).x) - 10) < 1e-9)
        // The 30° limit is reached at 12.5° on the phone.
        #expect(abs(degrees(calibration.apply(SIMD2(radians(12), 0)).x) - 28.75) < 1e-9)
        #expect(abs(degrees(calibration.apply(SIMD2(radians(12.5), 0)).x) - 30) < 1e-9)
    }

    @Test func gainComesFromTheConfig() {
        var config = GameConfig.standard
        config.tiltGain = 1
        let calibration = TiltCalibration(config: config)
        #expect(abs(degrees(calibration.apply(SIMD2(radians(10.5), 0)).x) - 10) < 1e-9)
    }

    @Test func deadZoneSwallowsJitter() {
        let calibration = TiltCalibration()
        #expect(calibration.apply(SIMD2(radians(0.4), radians(-0.49))) == .zero)
        #expect(calibration.apply(SIMD2(radians(0.6), 0)).x > 0)
    }

    @Test func sensitivityScalesAndIsClamped() {
        var calibration = TiltCalibration(sensitivity: 1.3)
        // 4° beyond the dead zone × 2.5 × 1.3.
        #expect(abs(degrees(calibration.apply(SIMD2(radians(4.5), 0)).x) - 13) < 1e-9)
        calibration.setSensitivity(0.7)
        #expect(abs(degrees(calibration.apply(SIMD2(radians(4.5), 0)).x) - 7) < 1e-9)
        calibration.setSensitivity(5)
        #expect(calibration.sensitivity == 1.3)
        calibration.setSensitivity(0.1)
        #expect(calibration.sensitivity == 0.7)
    }

    @Test func tiltIsLimitedToThirtyDegrees() {
        let calibration = TiltCalibration()
        let tilt = calibration.apply(SIMD2(radians(75), radians(-60)))
        #expect(abs(degrees(tilt.x) - 30) < 1e-9)
        #expect(abs(degrees(tilt.y) + 30) < 1e-9)
    }

    @Test func wrapsAroundInsteadOfJumping() {
        var calibration = TiltCalibration()
        calibration.calibrate(at: SIMD2(radians(175), 0))
        // From 175° to -175° is a 10° turn, not 350°: (10° − 0.5°) × 2.5.
        #expect(abs(degrees(calibration.apply(SIMD2(radians(-175), 0)).x) - 23.75) < 1e-9)
    }
}

struct TouchSteeringTests {
    @Test func eggRestsUnderTheFinger() {
        var steering = TouchSteering()
        steering.target = SIMD2(0.3, -0.5)
        let egg = EggPhysics()
        let rest = egg.restingPosition(tilt: steering.tilt)
        #expect(abs(rest.x - 0.3) < 1e-9)
        #expect(abs(rest.y + 0.5) < 1e-9)
    }

    @Test func noFingerMeansLevel() {
        #expect(TouchSteering().tilt == .zero)
    }

    @Test func gainDoesNotStrengthenTheFinger() {
        var strong = GameConfig.standard
        strong.tiltGain = 10
        var steering = TouchSteering(config: strong)
        steering.target = SIMD2(0.3, -0.5)
        var standard = TouchSteering()
        standard.target = steering.target
        #expect(steering.tilt == standard.tilt)
    }

    @Test func farAwayFingerIsLimited() {
        var steering = TouchSteering()
        steering.target = SIMD2(10, -10)
        #expect(abs(degrees(steering.tilt.x) - 30) < 1e-9)
        #expect(abs(degrees(steering.tilt.y) + 30) < 1e-9)
    }
}
