import Foundation

/// The exact shape of the egg: a surface of revolution around its long axis, lying on its side.
///
/// Seen from directly above, the outline is the side profile `r(t) = R · (1 − t²)^e · (1 − k·t)` with `t` running
/// from −1 at the round end (bottom of the screen) to +1 at the pointy end (top). The exponent and asymmetry were
/// fitted
/// to the outline of the owner's reference photo (residual ≈ 1 px at 320 px width): `e` slightly below ½ makes the
/// ends a little blunter than an ellipse, `k` narrows the top half.
///
/// Units: the egg is 1 wide and `aspect` tall, centred on the origin, `y` up the screen and `z` towards the viewer.
struct EggShape: Sendable {
    static let exponent = 0.4706
    static let asymmetry = 0.0459

    let aspect: Double
    /// `R`, chosen so the widest point is exactly 0.5.
    let scale: Double
    /// Where along the axis the egg is widest (slightly towards the round end).
    let widestT: Double

    init(aspect: Double) {
        self.aspect = aspect
        // Maximize (1 - t²)^e (1 - k t) by golden-section search; the function is unimodal on (-1, 1).
        let ratio = (5.0.squareRoot() - 1) / 2
        var low = -0.5, high = 0.5
        func profile(_ t: Double) -> Double {
            pow(1 - t * t, Self.exponent) * (1 - Self.asymmetry * t)
        }
        for _ in 0 ..< 80 {
            let a = high - ratio * (high - low)
            let b = low + ratio * (high - low)
            if profile(a) < profile(b) {
                low = a
            } else {
                high = b
            }
        }
        widestT = (low + high) / 2
        scale = 0.5 / profile(widestT)
    }

    var halfHeight: Double {
        aspect / 2
    }

    /// Axis parameter `t` (−1 bottom ... +1 top) of the height `y`.
    func axis(_ y: Double) -> Double {
        y / halfHeight
    }

    /// Profile radius at axis parameter `t`, 0 outside the egg.
    func radius(_ t: Double) -> Double {
        guard abs(t) < 1 else { return 0 }
        return scale * pow(1 - t * t, Self.exponent) * (1 - Self.asymmetry * t)
    }

    /// `dr/dy`, the slope of the outline.
    func radiusSlope(_ t: Double) -> Double {
        let q = max(1 - t * t, 1e-12)
        let base = pow(q, Self.exponent)
        let dt = scale * (base / q * Self.exponent * (-2 * t) * (1 - Self.asymmetry * t) - base * Self.asymmetry)
        return dt / halfHeight
    }

    /// The visible surface point above `(x, y)`, or `nil` outside the outline.
    func surface(x: Double, y: Double) -> (position: Vec3, normal: Vec3)? {
        let t = axis(y)
        let r = radius(t)
        guard abs(x) < r else { return nil }
        let z = (r * r - x * x).squareRoot()
        // Gradient of x² + z² − r(y)²: (2x, −2 r r', 2z).
        let normal = Vec3(x, -r * radiusSlope(t), z).normalized
        return (Vec3(x, y, z), normal)
    }

    /// Approximate signed distance to the outline (negative inside), in egg units.
    func signedDistance(x: Double, y: Double) -> Double {
        let t = axis(y)
        if abs(t) >= 1 {
            // Beyond a tip: distance to the tip point.
            let tipY = t > 0 ? halfHeight : -halfHeight
            return ((y - tipY) * (y - tipY) + x * x).squareRoot()
        }
        let slope = radiusSlope(t)
        return (abs(x) - radius(t)) / (1 + slope * slope).squareRoot()
    }
}
