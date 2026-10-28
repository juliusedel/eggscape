import Foundation

/// SplitMix64 (Steele, Lea & Flood, 2014): a tiny, fast generator whose output depends only on the seed.
///
/// Every phone in a race derives the weather from the same seed, so the numbers must be identical on every device and
/// iOS version. That is why the helpers below never call the standard library's `random(in:using:)`, whose algorithm
/// is an implementation detail of the OS-provided Swift runtime.
public struct SplitMix64: RandomNumberGenerator, Sendable, Hashable {
    public private(set) var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform value in `0 ..< 1` built from the top 53 bits.
    public mutating func nextUnit() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }

    /// Uniform value in `range`.
    public mutating func uniform(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * nextUnit()
    }

    /// Uniform integer in `0 ..< upperBound`.
    public mutating func index(below upperBound: Int) -> Int {
        precondition(upperBound > 0, "upperBound must be positive")
        return min(Int(nextUnit() * Double(upperBound)), upperBound - 1)
    }

    /// `true` with the given probability.
    public mutating func chance(_ probability: Double) -> Bool {
        nextUnit() < probability
    }

    /// Unit vector pointing in a uniformly random direction.
    public mutating func direction() -> SIMD2<Double> {
        let angle = nextUnit() * 2 * Double.pi
        return SIMD2(cos(angle), sin(angle))
    }

    /// An independent stream for one purpose (gusts, lightning, ...). Drawing from one stream never shifts another,
    /// so adding a new weather effect later does not change the existing ones for a given seed.
    public func stream(_ label: UInt64) -> SplitMix64 {
        var mixer = SplitMix64(seed: state ^ (label &* 0xD1B5_4A32_D192_ED03))
        return SplitMix64(seed: mixer.next())
    }
}
