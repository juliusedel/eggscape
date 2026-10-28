import EggscapeCore
import Foundation

/// Integer hashing for lattice noise, built on the SplitMix64 finalizer.
///
/// Noise needs a random value per lattice point that depends only on the point and the seed. Hashing the coordinates
/// gives exactly that without storing permutation tables, and the seeds themselves come from `SplitMix64` streams, so
/// every texture is a pure function of its `EggAppearance` or effect seed.
enum Hash {
    /// The SplitMix64 output function: a bijective, well-avalanching 64-bit mix.
    static func mix(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    static func of(_ x: Int, seed: UInt64) -> UInt64 {
        mix(seed ^ UInt64(bitPattern: Int64(x)))
    }

    static func of(_ x: Int, _ y: Int, seed: UInt64) -> UInt64 {
        mix(of(x, seed: seed) ^ UInt64(bitPattern: Int64(y)) &* 0xD6E8_FEB8_6659_FD93)
    }

    static func of(_ x: Int, _ y: Int, _ z: Int, seed: UInt64) -> UInt64 {
        mix(of(x, y, seed: seed) ^ UInt64(bitPattern: Int64(z)) &* 0xA076_1D64_78BD_642F)
    }

    /// A uniform value in `0 ..< 1` from the top 53 bits, like `SplitMix64.nextUnit()`.
    static func unit(_ hash: UInt64) -> Double {
        Double(hash >> 11) * 0x1.0p-53
    }

    /// A second independent uniform value from the same hash.
    static func unit(_ hash: UInt64, _ index: UInt64) -> Double {
        unit(mix(hash ^ (index &* 0x9E37_79B9_7F4A_7C15)))
    }

    /// The seed for one purpose of one texture, derived through an independent `SplitMix64` stream so adding a new
    /// layer never changes the existing ones.
    static func seed(_ base: UInt64, _ label: UInt64) -> UInt64 {
        var stream = SplitMix64(seed: base).stream(label)
        return stream.next()
    }
}

/// Seeded gradient noise (improved Perlin noise with hashed gradients) and the usual sums of octaves.
struct Noise: Sendable {
    let seed: UInt64

    init(seed: UInt64) {
        self.seed = seed
    }

    private static func fade(_ t: Double) -> Double {
        t * t * t * (t * (t * 6 - 15) + 10)
    }

    private static func gradient(_ hash: UInt64, _ x: Double, _ y: Double, _ z: Double) -> Double {
        switch hash & 15 {
        case 0, 12: x + y
        case 1, 13: -x + y
        case 2: x - y
        case 3: -x - y
        case 4: x + z
        case 5: -x + z
        case 6: x - z
        case 7: -x - z
        case 8: y + z
        case 9, 14: -y + z
        case 10: y - z
        default: -y - z
        }
    }

    private static func gradient(_ hash: UInt64, _ x: Double, _ y: Double) -> Double {
        switch hash & 7 {
        case 0: x + y
        case 1: -x + y
        case 2: x - y
        case 3: -x - y
        case 4: x
        case 5: -x
        case 6: y
        default: -y
        }
    }

    /// 3D gradient noise in about -1 ... 1, smooth (C2) everywhere.
    func value(_ p: Vec3) -> Double {
        let fx = p.x.rounded(.down), fy = p.y.rounded(.down), fz = p.z.rounded(.down)
        let ix = Int(fx), iy = Int(fy), iz = Int(fz)
        let x = p.x - fx, y = p.y - fy, z = p.z - fz
        let u = Self.fade(x), v = Self.fade(y), w = Self.fade(z)
        func corner(_ i: Int, _ j: Int, _ k: Int) -> Double {
            Self.gradient(Hash.of(ix + i, iy + j, iz + k, seed: seed), x - Double(i), y - Double(j), z - Double(k))
        }
        let x00 = Num.mix(corner(0, 0, 0), corner(1, 0, 0), u)
        let x10 = Num.mix(corner(0, 1, 0), corner(1, 1, 0), u)
        let x01 = Num.mix(corner(0, 0, 1), corner(1, 0, 1), u)
        let x11 = Num.mix(corner(0, 1, 1), corner(1, 1, 1), u)
        return Num.mix(Num.mix(x00, x10, v), Num.mix(x01, x11, v), w)
    }

    /// 2D gradient noise in about -1 ... 1.
    func value(_ x: Double, _ y: Double) -> Double {
        let fx = x.rounded(.down), fy = y.rounded(.down)
        let ix = Int(fx), iy = Int(fy)
        let dx = x - fx, dy = y - fy
        let u = Self.fade(dx), v = Self.fade(dy)
        func corner(_ i: Int, _ j: Int) -> Double {
            Self.gradient(Hash.of(ix + i, iy + j, seed: seed), dx - Double(i), dy - Double(j))
        }
        return Num.mix(Num.mix(corner(0, 0), corner(1, 0), u), Num.mix(corner(0, 1), corner(1, 1), u), v)
    }

    /// Fractal sum of `octaves` octaves (each twice the frequency, half the amplitude), normalized to about -1 ... 1.
    ///
    /// `footprint` is the size of one pixel in the units of `p`. Octaves finer than a pixel fade out instead of
    /// aliasing into sparkle, so the same texture works for a 64-pixel shop icon and a 1000-pixel preview.
    func fractal(_ p: Vec3, octaves: Int, footprint: Double = 0) -> Double {
        var sum = 0.0, amplitude = 1.0, frequency = 1.0, norm = 0.0
        for octave in 0 ..< octaves {
            let weight = footprint > 0 ? Num.clamp(1.5 - 2 * frequency * footprint) : 1
            if weight <= 0 {
                break
            }
            let shifted = Vec3(p.x + Double(octave) * 17.31, p.y - Double(octave) * 9.17, p.z + Double(octave) * 5.71)
            sum += amplitude * weight * value(shifted * frequency)
            norm += amplitude
            amplitude *= 0.5
            frequency *= 2
        }
        return norm > 0 ? sum / norm : 0
    }

    func fractal(_ x: Double, _ y: Double, octaves: Int) -> Double {
        var sum = 0.0, amplitude = 1.0, frequency = 1.0, norm = 0.0
        for octave in 0 ..< octaves {
            let offset = Double(octave) * 13.37
            sum += amplitude * value(x * frequency + offset, y * frequency - offset)
            norm += amplitude
            amplitude *= 0.5
            frequency *= 2
        }
        return sum / norm
    }
}
