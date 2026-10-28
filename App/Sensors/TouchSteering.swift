import EggscapeCore
import Foundation

/// Finger fallback for the Simulator and devices without motion sensors (also used by UI tests and screenshots).
///
/// While a finger is down, the spoon is tilted exactly so far that the egg's resting position is under the finger:
/// the egg follows the finger but still wobbles and reacts to the weather like on a real device.
struct TouchSteering: Sendable {
    let config: GameConfig
    /// Finger position in bowl units, `nil` while no finger is down.
    var target: SIMD2<Double>?

    init(config: GameConfig = .standard, target: SIMD2<Double>? = nil) {
        self.config = config
        self.target = target
    }

    /// The equivalent tilt in radians.
    var tilt: SIMD2<Double> {
        guard let target else { return .zero }
        let limit = sin(config.maxTiltDegrees * .pi / 180)
        let slope = target * config.bowlStiffness / config.gravity
        return SIMD2(asin(min(max(slope.x, -limit), limit)), asin(min(max(slope.y, -limit), limit)))
    }
}
