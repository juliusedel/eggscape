import Foundation

/// The egg as a point mass in a concave spoon bowl, simulated independently per axis:
///
///     a = G·sin(tilt) − k·p − c·v + disturbance
///
/// `x` points to the right of the screen, `y` towards the top (along the handle, away from the player).
/// A positive tilt rolls the egg towards positive coordinates: right edge down → right, top edge down → up.
public struct EggPhysics: Sendable, Equatable {
    public let config: GameConfig
    public private(set) var position: SIMD2<Double> = .zero
    public private(set) var velocity: SIMD2<Double> = .zero

    public init(config: GameConfig = .standard) {
        self.config = config
    }

    /// Elliptical distance from the bowl centre: 0 in the middle, 1 at the tipping point.
    public var rimDistance: Double {
        let scaled = position / SIMD2(config.bowlRadiusX, config.bowlRadiusY)
        return (scaled * scaled).sum().squareRoot()
    }

    /// The egg has tipped over the rim.
    public var hasFallen: Bool {
        rimDistance > 1
    }

    /// Advances one fixed timestep with semi-implicit Euler (stable and cheap for this damped oscillator).
    /// - Parameters:
    ///   - tilt: calibrated tilt in radians.
    ///   - force: external acceleration such as wind.
    ///   - dampingScale: multiplier on the damping, below 1 when the bowl is wet.
    public mutating func step(
        dt: Double,
        tilt: SIMD2<Double>,
        force: SIMD2<Double> = .zero,
        dampingScale: Double = 1
    ) {
        let slope = config.gravity * SIMD2(sin(tilt.x), sin(tilt.y))
        let acceleration = slope
            - config.bowlStiffness * position
            - config.damping * dampingScale * velocity
            + force
        velocity += acceleration * dt
        position += velocity * dt
    }

    /// Instant change of velocity, used for footsteps, puddles, raindrops and lightning.
    public mutating func kick(_ deltaVelocity: SIMD2<Double>) {
        velocity += deltaVelocity
    }

    /// A fresh egg resting in the middle of the bowl.
    public mutating func reset() {
        position = .zero
        velocity = .zero
    }

    /// Where the egg comes to rest for a constant tilt and force (handy for tests and tuning).
    public func restingPosition(tilt: SIMD2<Double>, force: SIMD2<Double> = .zero) -> SIMD2<Double> {
        (config.gravity * SIMD2(sin(tilt.x), sin(tilt.y)) + force) / config.bowlStiffness
    }
}
