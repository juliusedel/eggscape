import Foundation

/// A 3D vector with plain `Double` fields.
///
/// The renderers evaluate millions of samples; a concrete struct keeps that fast in debug builds too, where the
/// generic `SIMD3` operators are not specialized. Directions use the scene convention of all artwork: `x` to the
/// right of the screen, `y` to the top of the screen, `z` out of the screen towards the viewer (up from the table).
struct Vec3: Sendable, Equatable {
    var x: Double
    var y: Double
    var z: Double

    init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    static let zero = Vec3(0, 0, 0)
    /// Towards the viewer: every artwork is seen from directly above.
    static let up = Vec3(0, 0, 1)

    /// The unit vector with the given azimuth (counter-clockwise from the screen's right) and elevation above the
    /// table, both in degrees.
    static func direction(azimuth: Double, elevation: Double) -> Vec3 {
        let azimuth = azimuth * .pi / 180
        let elevation = elevation * .pi / 180
        return Vec3(cos(elevation) * cos(azimuth), cos(elevation) * sin(azimuth), sin(elevation))
    }

    static func + (a: Vec3, b: Vec3) -> Vec3 {
        Vec3(a.x + b.x, a.y + b.y, a.z + b.z)
    }

    static func - (a: Vec3, b: Vec3) -> Vec3 {
        Vec3(a.x - b.x, a.y - b.y, a.z - b.z)
    }

    static prefix func - (a: Vec3) -> Vec3 {
        Vec3(-a.x, -a.y, -a.z)
    }

    static func * (a: Vec3, s: Double) -> Vec3 {
        Vec3(a.x * s, a.y * s, a.z * s)
    }

    static func * (s: Double, a: Vec3) -> Vec3 {
        Vec3(a.x * s, a.y * s, a.z * s)
    }

    static func / (a: Vec3, s: Double) -> Vec3 {
        Vec3(a.x / s, a.y / s, a.z / s)
    }

    static func += (a: inout Vec3, b: Vec3) {
        a = a + b
    }

    func dot(_ b: Vec3) -> Double {
        x * b.x + y * b.y + z * b.z
    }

    func cross(_ b: Vec3) -> Vec3 {
        Vec3(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x)
    }

    var length: Double {
        (x * x + y * y + z * z).squareRoot()
    }

    /// The unit vector in the same direction, or `up` for a zero vector (a safe default for normals).
    var normalized: Vec3 {
        let length = length
        return length > 1e-300 ? self / length : .up
    }

    /// Mirrors the incoming direction `self` (pointing away from the surface) about `normal`.
    func reflected(about normal: Vec3) -> Vec3 {
        normal * (2 * dot(normal)) - self
    }

    /// Rotates about the x axis by `angle` radians (positive turns `y` towards `z`).
    func rotatedAboutX(_ angle: Double) -> Vec3 {
        let c = cos(angle), s = sin(angle)
        return Vec3(x, c * y - s * z, s * y + c * z)
    }
}

/// A 2D point or vector for outlines and decals.
struct Vec2: Sendable, Equatable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    static let zero = Vec2(0, 0)

    static func + (a: Vec2, b: Vec2) -> Vec2 {
        Vec2(a.x + b.x, a.y + b.y)
    }

    static func - (a: Vec2, b: Vec2) -> Vec2 {
        Vec2(a.x - b.x, a.y - b.y)
    }

    static func * (a: Vec2, s: Double) -> Vec2 {
        Vec2(a.x * s, a.y * s)
    }

    func dot(_ b: Vec2) -> Double {
        x * b.x + y * b.y
    }

    var length: Double {
        (x * x + y * y).squareRoot()
    }

    var normalized: Vec2 {
        let length = length
        return length > 1e-300 ? Vec2(x / length, y / length) : Vec2(1, 0)
    }

    /// Rotates counter-clockwise by `angle` radians.
    func rotated(_ angle: Double) -> Vec2 {
        let c = cos(angle), s = sin(angle)
        return Vec2(c * x - s * y, s * x + c * y)
    }
}

/// Small numeric helpers shared by all renderers.
enum Num {
    static func clamp(_ value: Double, _ low: Double = 0, _ high: Double = 1) -> Double {
        min(max(value, low), high)
    }

    static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    /// Hermite smoothstep from 0 at `edge0` to 1 at `edge1` (works for `edge0 > edge1` too).
    static func smoothstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
        let t = clamp((value - edge0) / (edge1 - edge0))
        return t * t * (3 - 2 * t)
    }

    /// Polynomial smooth minimum with blend radius `k`: like `min`, but rounds the corner where `a` and `b` meet.
    static func smoothMin(_ a: Double, _ b: Double, _ k: Double) -> Double {
        let h = clamp(0.5 + 0.5 * (b - a) / k)
        return mix(b, a, h) - k * h * (1 - h)
    }

    /// The error function, accurate to about 1e-7 (Abramowitz & Stegun 7.1.26 is not enough for smooth gradients,
    /// so this uses the Numerical Recipes `erfc` Chebyshev fit).
    static func erf(_ x: Double) -> Double {
        let z = abs(x)
        let t = 1 / (1 + 0.5 * z)
        let polynomial = -z * z - 1.26551223 + t * (1.00002368 + t * (0.37409196 + t * (0.09678418
                + t * (-0.18628806 + t * (0.27886807 + t * (-1.13520398 + t * (1.48851587
                    + t * (-0.82215223 + t * 0.17087277))))))))
        let result = 1 - t * exp(polynomial)
        return x >= 0 ? result : -result
    }

    /// Fraction of a Gaussian of standard deviation `sigma` centred at `x` that falls inside `-half ... half`:
    /// a box of half-width `half` blurred with that Gaussian.
    static func blurredBox(_ x: Double, half: Double, sigma: Double) -> Double {
        let scale = 1 / (sigma * 2.0.squareRoot())
        return 0.5 * (erf((x + half) * scale) - erf((x - half) * scale))
    }
}
