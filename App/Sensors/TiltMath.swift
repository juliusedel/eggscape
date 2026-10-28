import Foundation

/// Converts the sensor-fused gravity vector into the two tilt angles the game works with.
enum TiltMath {
    /// - Parameter gravity: `CMDeviceMotion.gravity` in device coordinates (x right, y towards the top edge,
    ///   z out of the screen), in g.
    /// - Returns: radians; x is positive with the right edge down, y is positive with the top edge down.
    static func tilt(gravity: SIMD3<Double>) -> SIMD2<Double> {
        SIMD2(atan2(gravity.x, -gravity.z), atan2(gravity.y, -gravity.z))
    }

    /// Wraps an angle into `-π ... π`.
    static func wrapped(_ angle: Double) -> Double {
        remainder(angle, 2 * .pi)
    }
}

/// First-order low-pass filter defined by a time constant instead of a fixed factor, so it behaves the same at any
/// sample rate. It smooths the gravity vector rather than the angles, which avoids jumps where an angle wraps around.
struct GravityLowPass: Sendable {
    let timeConstant: Double
    private(set) var value: SIMD3<Double>?
    private var lastTimestamp: Double?

    init(timeConstant: Double) {
        self.timeConstant = timeConstant
    }

    /// Adds a sample taken at `timestamp` (seconds) and returns the filtered value.
    mutating func add(_ sample: SIMD3<Double>, at timestamp: Double) -> SIMD3<Double> {
        defer { lastTimestamp = timestamp }
        guard let current = value, let lastTimestamp, timestamp > lastTimestamp else {
            value = sample
            return sample
        }
        let dt = timestamp - lastTimestamp
        let filtered = current + (sample - current) * (dt / (timeConstant + dt))
        value = filtered
        return filtered
    }
}
