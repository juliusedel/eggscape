/// Turns variable frame durations into a whole number of fixed simulation steps (the classic accumulator loop),
/// so the physics behave the same at 60 fps, 120 fps or after a dropped frame.
public struct FixedTimestep: Sendable, Equatable {
    /// Duration of one simulation step in seconds.
    public let step: Double
    /// Longer frames are cut to this, so a hitch never makes the simulation spiral.
    public let maxFrameDuration: Double
    public private(set) var accumulator = 0.0

    public init(rate: Double, maxFrameDuration: Double = 0.25) {
        precondition(rate > 0, "rate must be positive")
        step = 1 / rate
        self.maxFrameDuration = maxFrameDuration
    }

    /// Adds a frame's duration and returns how many steps to simulate now.
    public mutating func consume(_ frameDuration: Double) -> Int {
        accumulator += min(max(frameDuration, 0), maxFrameDuration)
        // The small epsilon keeps 1/120 + 1/120 from rounding down to a single step.
        let steps = Int((accumulator + 1e-9) / step)
        accumulator = max(accumulator - Double(steps) * step, 0)
        return steps
    }

    /// Fraction of a step left in the accumulator, for interpolating the rendered state.
    public var remainder: Double {
        accumulator / step
    }

    public mutating func reset() {
        accumulator = 0
    }
}
