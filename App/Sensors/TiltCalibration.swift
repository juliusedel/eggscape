import EggscapeCore
import Foundation

/// Turns the raw device tilt into the tilt the egg feels: relative to the pose the player calibrated, with a small
/// dead zone, strengthened by the base gain (`GameConfig.tiltGain`, 2.5) times the sensitivity setting and limited to
/// ±30°. Finger steering (`TouchSteering`) computes its tilt directly and never passes through here, so the gain does
/// not make it stronger.
struct TiltCalibration: Equatable, Sendable {
    /// Raw tilt captured when the player tapped "Kalibrieren"; it counts as level from then on.
    var zero: SIMD2<Double> = .zero
    private(set) var sensitivity: Double = 1
    let config: GameConfig

    init(config: GameConfig = .standard, zero: SIMD2<Double> = .zero, sensitivity: Double = 1) {
        self.config = config
        self.zero = zero
        setSensitivity(sensitivity)
    }

    mutating func setSensitivity(_ value: Double) {
        sensitivity = min(max(value, config.sensitivityRange.lowerBound), config.sensitivityRange.upperBound)
    }

    /// Makes the current pose the new level.
    mutating func calibrate(at raw: SIMD2<Double>) {
        zero = raw
    }

    /// The calibrated tilt for a raw sensor reading, in radians.
    func apply(_ raw: SIMD2<Double>) -> SIMD2<Double> {
        SIMD2(shape(raw.x - zero.x), shape(raw.y - zero.y))
    }

    private func shape(_ delta: Double) -> Double {
        let angle = TiltMath.wrapped(delta)
        let deadZone = config.deadZoneDegrees * .pi / 180
        let limit = config.maxTiltDegrees * .pi / 180
        let magnitude = abs(angle)
        guard magnitude > deadZone else { return 0 }
        // Subtracting the dead zone keeps the response continuous at its edge.
        let shaped = min((magnitude - deadZone) * config.tiltGain * sensitivity, limit)
        return angle < 0 ? -shaped : shaped
    }
}
