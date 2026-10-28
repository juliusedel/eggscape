import Foundation

/// The exact shape of the spoon, in bowl units: `x` to the right, `y` up the screen with the origin at the bowl
/// center, and heights `z` above the table the spoon lies on.
///
/// Everything is an explicit function of the position, so the outline can be anti-aliased by supersampling and the
/// shading reads its normals from the analytic surface instead of a mesh:
///
/// - The bowl's inner rim is the physics rim, the ellipse `(x / 0.75)² + y² = 1`. Inside it the bowl is a pressed
///   dish `depth` deep, flat in the middle and steepening towards the rim.
/// - A rolled lip `lip` wide runs around the rim. Seen from above it is a thin bead whose normals sweep from the bowl
///   over the crest down to the table, which is what draws the crisp bright line along a real spoon's rim.
/// - The neck leaves the bowl at the bottom 0.28 units wide and widens into a 0.42-unit handle with a rounded end at
///   `handleEnd`. Its top is gently domed with rounded edges; it rises a little from the bowl and then runs down
///   towards the table, the way a spoon lying face up rests on the bottom of its bowl and the tip of its handle.
enum SpoonGeometry {
    /// Half-axes of the bowl's inner rim (the physics rim).
    static let rimHalfWidth = 0.75
    static let rimHalfHeight = 1.0
    /// Width of the rolled lip outside the inner rim.
    static let lip = 0.055
    /// How far the lip's crest rises above the rim.
    static let lipCrest = 0.02
    /// Depth of the bowl below its rim; the bottom of the bowl touches the table, so the rim is this high.
    static let depth = 0.3
    /// Half-width of the neck where it leaves the bowl, and of the handle at its widest.
    static let neckHalfWidth = 0.14
    static let handleHalfWidth = 0.21
    /// The tip of the handle, 3.37 units below the bowl's outer edge, and the length of its rounded end.
    static let handleEnd = -4.42
    static let endLength = 0.24
    /// Radius of the fillet where the neck flares into the bowl.
    static let neckFillet = 0.16

    /// Margin around the spoon for its shadow, in units.
    static let margin = 0.44
    static let topMargin = 0.2
    /// How far the image reaches below the bowl center.
    static let bottom = 4.6

    static var outerHalfWidth: Double {
        rimHalfWidth + lip
    }

    static var outerHalfHeight: Double {
        rimHalfHeight + lip
    }

    static func layout(unit: Double) -> SpoonArt.Layout {
        let width = Int((2 * (outerHalfWidth + margin) * unit).rounded())
        let height = Int(((outerHalfHeight + topMargin + bottom) * unit).rounded())
        return SpoonArt.Layout(
            width: width,
            height: height,
            bowlCenterX: Double(width) / 2,
            bowlCenterY: (outerHalfHeight + topMargin) * unit,
            unit: unit
        )
    }

    // MARK: Outline

    /// Elliptical radius relative to the inner rim: 1 on the rim, less inside the bowl.
    static func rimRadius(_ x: Double, _ y: Double) -> Double {
        let u = x / rimHalfWidth, v = y / rimHalfHeight
        return (u * u + v * v).squareRoot()
    }

    /// Signed distance to the inner rim (negative inside the bowl) and the outward normal of the rim there.
    ///
    /// `(r − 1) / |∇r|` is exact on the rim and accurate to first order near it, which is all the lip and the
    /// anti-aliasing need; further away it stays smooth and monotonic, which is all the shadow needs.
    static func rim(_ x: Double, _ y: Double) -> (distance: Double, normal: Vec2) {
        let r = rimRadius(x, y)
        guard r > 1e-6 else { return (-rimHalfWidth, Vec2(0, 1)) }
        let gradient = Vec2(x / (rimHalfWidth * rimHalfWidth * r), y / (rimHalfHeight * rimHalfHeight * r))
        let length = max(gradient.length, 1e-9)
        return ((r - 1) / length, Vec2(gradient.x / length, gradient.y / length))
    }

    /// Half-width of the handle at height `y` on the screen, 0 beyond its tip.
    static func handleHalfWidth(_ y: Double) -> Double {
        let widening = Num.smoothstep(-1.25, -3.9, y)
        let width = neckHalfWidth + (handleHalfWidth - neckHalfWidth) * widening
        let capStart = handleEnd + endLength
        guard y < capStart else { return width }
        let t = (capStart - y) / endLength
        return width * max(0, 1 - t * t).squareRoot()
    }

    /// Signed distance to the handle's outline (negative inside); the handle starts inside the bowl's lip.
    static func handleDistance(_ x: Double, _ y: Double) -> Double {
        let top = -0.92
        if y < handleEnd {
            return ((y - handleEnd) * (y - handleEnd) + x * x).squareRoot()
        }
        let width = handleHalfWidth(y)
        let step = 1e-3
        let slope = (handleHalfWidth(y + step) - handleHalfWidth(y - step)) / (2 * step)
        let side = (abs(x) - width) / (1 + slope * slope).squareRoot()
        return max(side, y - top)
    }

    /// Signed distance to the whole outline (negative inside): bowl and handle, joined by a smooth fillet.
    static func outlineDistance(_ x: Double, _ y: Double) -> Double {
        let bowl = rim(x, y).distance - lip
        guard y < -0.6 else { return bowl }
        return Num.smoothMin(bowl, handleDistance(x, y), neckFillet)
    }

    // MARK: Surface

    /// Which part of the spoon a point belongs to; the parts differ in finish.
    enum Part: Sendable {
        case bowl, lip, handle
    }

    /// A visible point of the spoon's upper surface.
    struct Point: Sendable {
        var height: Double
        var normal: Vec3
        var part: Part
        /// Signed distance to the inner rim (negative in the bowl).
        var rimDistance: Double
    }

    /// The surface seen from above at `(x, y)`; the caller decides from `outlineDistance` whether it is on the spoon.
    static func surface(_ x: Double, _ y: Double) -> Point {
        let rim = rim(x, y)
        if rim.distance < 0 {
            return bowl(x, y, rimDistance: rim.distance)
        }
        // Outside the rim: the rolled lip, continued down the outside of the bowl, merged with the neck.
        let lip = lipHeight(rim.distance)
        let lipGradient = Vec2(rim.normal.x * lip.slope, rim.normal.y * lip.slope)
        let handle = handleHeight(x, y)
        let k = 0.025
        // Smooth maximum of both heights; its gradient is the same blend of both gradients.
        let h = Num.clamp(0.5 + 0.5 * (lip.height - handle.height) / k)
        let height = Num.mix(handle.height, lip.height, h) + k * h * (1 - h)
        let gradient = Vec2(
            Num.mix(handle.gradient.x, lipGradient.x, h),
            Num.mix(handle.gradient.y, lipGradient.y, h)
        )
        let normal = Vec3(-gradient.x, -gradient.y, 1).normalized
        let part: Part = h > 0.5 && rim.distance < Self.lip * 1.2 ? .lip : .handle
        return Point(height: height, normal: normal, part: part, rimDistance: rim.distance)
    }

    /// The inside of the bowl: `z = depth · (1 − (1 − r²)^0.75)`, a dish that is nearly flat where the egg rests and
    /// steepens towards the rim like a pressed spoon.
    private static func bowl(_ x: Double, _ y: Double, rimDistance: Double) -> Point {
        let a2 = rimHalfWidth * rimHalfWidth, b2 = rimHalfHeight * rimHalfHeight
        let q = max(1 - x * x / a2 - y * y / b2, 1e-6)
        let height = depth * (1 - pow(q, 0.75))
        // dz/dr² = 0.75 · depth · q^−0.25, and dr²/dx = 2x / a².
        let slope = 1.5 * depth * pow(q, -0.25)
        let normal = Vec3(-slope * x / a2, -slope * y / b2, 1).normalized
        return Point(height: height, normal: normal, part: .bowl, rimDistance: rimDistance)
    }

    /// Height and slope (along the outward rim normal) of the lip at distance `d` outside the inner rim.
    private static func lipHeight(_ d: Double) -> (height: Double, slope: Double) {
        let s = d / lip
        guard s < 1 else {
            return (depth - 2.5 * (d - lip), -2.5)
        }
        let t = 2 * s - 1
        let root = max(1 - t * t, 0).squareRoot()
        let height = depth + lipCrest * root
        let slope = -lipCrest * t / max(root, 0.03) * 2 / lip
        return (height, slope)
    }

    /// Height of the handle's ridge above the table: just below the rim where the neck leaves the bowl, a gentle
    /// rise over the neck, then a long, straight run down towards the tip.
    static func ridge(_ y: Double) -> Double {
        let rise = Num.smoothstep(-0.98, -1.6, y)
        let fall = Num.clamp((-1.6 - y) / (-1.6 - handleEnd))
        return depth - 0.012 + 0.07 * rise - 0.26 * fall
    }

    /// Height and gradient of the handle's domed top; beyond its edges it falls away steeply.
    private static func handleHeight(_ x: Double, _ y: Double) -> (height: Double, gradient: Vec2) {
        func top(_ x: Double, _ y: Double) -> Double {
            let width = max(handleHalfWidth(y), 1e-4)
            let thickness = 0.32 * width
            let u = abs(x) / width
            if u >= 1 {
                return ridge(y) - thickness - 2.5 * (abs(x) - width)
            }
            return ridge(y) - thickness * (1 - (1 - u * u).squareRoot())
        }
        let width = max(handleHalfWidth(y), 1e-4)
        let thickness = 0.32 * width
        let u = abs(x) / width
        let height = top(x, y)
        let slopeX: Double
        if u >= 1 {
            slopeX = -2.5
        } else {
            slopeX = -thickness * u / (width * max((1 - u * u).squareRoot(), 0.03))
        }
        let step = 1e-3
        let slopeY = (top(x, y + step) - top(x, y - step)) / (2 * step)
        return (height, Vec2(x < 0 ? -slopeX : slopeX, slopeY))
    }
}
