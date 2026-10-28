import Foundation

/// The exact shape of the spoon, in bowl units: `x` to the right, `y` up the screen with the origin at the bowl
/// center, and heights `z` above the table the spoon lies on.
///
/// Everything is an explicit function of the position, so the outline can be anti-aliased by supersampling and the
/// shading reads its normals from the surface itself instead of a mesh:
///
/// - The bowl's inner rim is the physics rim, the ellipse `(x / 0.75)² + y² = 1`. Inside it the bowl is a pressed
///   dish `depth` deep: a calm, almost flat floor where the egg rests, steepening towards the rim. Like a concave
///   mirror it then shows the key soft box as a window near the far rim instead of right beside the egg.
/// - A rolled lip `lip` wide runs around the rim and carries on as the rounded edge of the neck and the handle, so the
///   crisp line along a real spoon's rim flows into the handle without a seam.
/// - The neck leaves the bowl at the bottom 0.28 units wide and widens into a 0.42-unit handle with a rounded end at
///   `handleEnd`. Its top is gently domed; it rises a little from the bowl and then runs down towards the table, the
///   way a spoon lying face up rests on the bottom of its bowl and the tip of its handle.
enum SpoonGeometry {
    /// Half-axes of the bowl's inner rim (the physics rim).
    static let rimHalfWidth = 0.75
    static let rimHalfHeight = 1.0
    /// Width of the rolled lip outside the inner rim.
    static let lip = 0.055
    /// How far the lip's crest rises above the rim, and how far the rounded outer edge falls below the top.
    static let lipCrest = 0.012
    static let edgeDrop = 0.02
    /// Depth of the bowl below its rim; the bottom of the bowl touches the table, so the rim is this high.
    static let depth = 0.3
    /// The bowl's profile `z = depth · (1 − (1 − r^m)^p)` (`r` the elliptical radius): `m` above 2 flattens the
    /// floor, `p` below 1 steepens the wall towards the rim.
    static let floorExponent = 2.6
    static let wallExponent = 0.55
    /// Half-width of the neck where it leaves the bowl, and of the handle at its widest.
    static let neckHalfWidth = 0.14
    static let handleHalfWidth = 0.21
    /// How much the handle's top is domed, as a fraction of its half-width.
    static let domeRise = 0.22
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

    /// Signed distance to the inner rim (negative inside the bowl).
    ///
    /// `(r − 1) / |∇r|` is exact on the rim and accurate to first order near it, which is all the lip and the
    /// anti-aliasing need; further away it stays smooth and monotonic, which is all the shadow needs.
    static func rimDistance(_ x: Double, _ y: Double) -> Double {
        let r = rimRadius(x, y)
        guard r > 1e-6 else { return -rimHalfWidth }
        let gradient = Vec2(x / (rimHalfWidth * rimHalfWidth * r), y / (rimHalfHeight * rimHalfHeight * r))
        return (r - 1) / max(gradient.length, 1e-9)
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
        let bowl = rimDistance(x, y) - lip
        guard y < -0.6 else { return bowl }
        return Num.smoothMin(bowl, handleDistance(x, y), neckFillet)
    }

    // MARK: Surface

    /// A visible point of the spoon's upper surface.
    struct Point: Sendable {
        var height: Double
        var normal: Vec3
        /// Signed distance to the inner rim (negative in the bowl).
        var rimDistance: Double
        /// 0 on the mirror-polished bowl and lip, 1 on the brushed handle.
        var brushed: Double

        var inBowl: Bool {
            rimDistance < 0
        }
    }

    /// The surface seen from above at `(x, y)`; the caller decides from `outlineDistance` whether it is on the spoon.
    static func surface(_ x: Double, _ y: Double) -> Point {
        let rimDistance = rimDistance(x, y)
        if rimDistance < 0 {
            return bowl(x, y, rimDistance: rimDistance)
        }
        // The band around the bowl and the handle: normals from central differences of its height.
        let step = 3e-4
        let gradientX = (bandHeight(x + step, y) - bandHeight(x - step, y)) / (2 * step)
        let gradientY = (bandHeight(x, y + step) - bandHeight(x, y - step)) / (2 * step)
        return Point(
            height: bandHeight(x, y),
            normal: Vec3(-gradientX, -gradientY, 1).normalized,
            rimDistance: rimDistance,
            brushed: Num.smoothstep(-1.05, -1.45, y)
        )
    }

    /// The inside of the bowl, `z = depth · (1 − (1 − r^m)^p)`.
    private static func bowl(_ x: Double, _ y: Double, rimDistance: Double) -> Point {
        let a2 = rimHalfWidth * rimHalfWidth, b2 = rimHalfHeight * rimHalfHeight
        let r2 = x * x / a2 + y * y / b2
        let rm = pow(r2, floorExponent / 2)
        let q = max(1 - rm, 1e-6)
        let height = depth * (1 - pow(q, wallExponent))
        // dz/d(r²) = depth · p · q^(p − 1) · (m / 2) · r^(m − 2), and d(r²)/dx = 2x / a².
        let slope = depth * wallExponent * pow(q, wallExponent - 1) * floorExponent * pow(r2, floorExponent / 2 - 1)
        let normal = Vec3(-slope * x / a2, -slope * y / b2, 1).normalized
        return Point(height: height, normal: normal, rimDistance: rimDistance, brushed: 0)
    }

    /// Elliptical radius at which the bowl's dish reaches `height` above the table (the inverse of its profile).
    static func bowlRadius(atHeight height: Double) -> Double {
        let fall = max(1 - height / depth, 0)
        return pow(max(1 - pow(fall, 1 / wallExponent), 0), 1 / floorExponent)
    }

    /// Height of everything outside the inner rim: a band whose flat top is the lip's crest around the bowl and the
    /// domed handle below it, rounded off down to the rim on the inside and down to the outline on the outside.
    static func bandHeight(_ x: Double, _ y: Double) -> Double {
        let toHandle = Num.smoothstep(-0.98, -1.3, y)
        let width = max(handleHalfWidth(y), 1e-4)
        let u = min(abs(x) / width, 1)
        let dome = ridge(y) - domeRise * width * u * u
        var height = Num.mix(depth + lipCrest, dome, toHandle)
        let round = lip / 2
        let fromRim = rimDistance(x, y)
        if fromRim < round {
            height -= lipCrest * roundOff((round - fromRim) / round)
        }
        let fromOutline = -outlineDistance(x, y)
        if fromOutline < round {
            height -= edgeDrop * roundOff((round - fromOutline) / round)
        }
        return height
    }

    /// A quarter circle: 0 with a flat tangent at `t = 0`, 1 with a vertical tangent at `t = 1`.
    private static func roundOff(_ t: Double) -> Double {
        let t = Num.clamp(t)
        return 1 - (1 - t * t).squareRoot()
    }

    /// Height of the handle's ridge above the table: level with the lip's crest where the neck leaves the bowl, a
    /// gentle rise over the neck, then a long, smooth run down towards the tip.
    static func ridge(_ y: Double) -> Double {
        let rise = Num.smoothstep(-0.98, -1.7, y)
        let fall = Num.smoothstep(-1.3, handleEnd - 0.3, y)
        return depth + lipCrest + 0.06 * rise - 0.26 * fall
    }
}
