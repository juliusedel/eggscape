import CoreGraphics
import EggscapeArt
import EggscapeCore

/// Screen geometry of the game scene (scene coordinates, origin bottom left): a spoon seen from directly above, with
/// the bowl's center at 53 % of the height and the handle running off the bottom edge, and an egg that nearly fills the
/// bowl.
///
/// The egg is too big to roll as far as the physics lets it, so its position is drawn scaled down per axis: at the
/// tipping point (`GameConfig.bowlRadiusX` × `bowlRadiusY`) it has ridden up onto the steel and hangs over the bowl's
/// edge by a third of its half-width, with its center still well inside the bowl.
struct SceneLayout: Equatable {
    /// Width of the egg in bowl units. The bowl's inner rim is `1.5 × 2` units, so only a thin edge of steel stays
    /// visible around the egg: the rolled lip and a few hundredths of a unit of the bowl.
    static let eggWidth = 1.44
    /// Half the egg's width and height, in bowl units.
    static let halfEgg = SIMD2(eggWidth, eggWidth * EggArt.aspect) / 2
    /// The outer edge of the bowl's rolled lip, in bowl units: the inner rim's half-axes plus the 0.055-unit lip
    /// (`SpoonGeometry`).
    static let bowlEdge = SIMD2(0.805, 1.055)
    /// How far the egg hangs over the bowl's edge at the tipping point, as a share of its half-width.
    static let overhang = 1.0 / 3
    /// The egg falling off the spoon shrinks to this share of its size as it falls away from the eye.
    static let fallenEggScale = 0.6
    /// Offset of the egg's shadow from the egg, in bowl units. The key light is at the top right, 58° high
    /// (`Studio.shadowDirection`), so the shadow falls to the bottom left, about as far as a point a third of the way
    /// up the egg casts it: a bigger egg casts it further.
    static let eggShadowOffset = SIMD2(-0.19, -0.09) * eggWidth

    let size: CGSize
    /// Points per bowl unit. The spoon takes about half the screen's width, so the egg and the rim stay clear of the
    /// HUD at the top and the sprint button at the bottom right.
    let unit: CGFloat
    let bowlCenter: CGPoint
    /// Where the egg's center is drawn when the egg reaches the tipping point straight sideways (`x`) or along the
    /// handle (`y`), in bowl units from the bowl's center.
    let eggTravel: SIMD2<Double>
    /// The physics position of the tipping point on each axis.
    let tippingPoint: SIMD2<Double>

    init(size: CGSize, config: GameConfig = .standard) {
        self.size = size
        unit = min(size.width * 0.3, size.height * 0.145)
        bowlCenter = CGPoint(x: size.width / 2, y: size.height * 0.53)
        eggTravel = Self.bowlEdge + Self.overhang * Self.halfEgg.x - Self.halfEgg
        tippingPoint = SIMD2(config.bowlRadiusX, config.bowlRadiusY)
    }

    /// Screen position of a point in bowl units.
    func point(inBowl position: SIMD2<Double>) -> CGPoint {
        CGPoint(x: bowlCenter.x + CGFloat(position.x) * unit, y: bowlCenter.y + CGFloat(position.y) * unit)
    }

    /// Bowl units of a screen position.
    func bowlPosition(of point: CGPoint) -> SIMD2<Double> {
        SIMD2(Double((point.x - bowlCenter.x) / unit), Double((point.y - bowlCenter.y) / unit))
    }

    /// A distance in bowl units, in points.
    func vector(inBowl distance: SIMD2<Double>) -> CGVector {
        CGVector(dx: CGFloat(distance.x) * unit, dy: CGFloat(distance.y) * unit)
    }

    /// Where the egg's center is drawn for its physics position, in bowl units from the bowl's center.
    func eggOffset(for position: SIMD2<Double>) -> SIMD2<Double> {
        position / tippingPoint * eggTravel
    }

    /// The physics position at which the egg is drawn at `offset`, e.g. under a finger: the inverse of
    /// `eggOffset(for:)`.
    func eggPosition(forOffset offset: SIMD2<Double>) -> SIMD2<Double> {
        offset / eggTravel * tippingPoint
    }

    /// Where the egg that falls off the spoon from `offset` (where it was drawn, in bowl units from the bowl's center)
    /// lands: straight on outwards until the egg, shrunk as it falls away from the eye, clears the bowl's edge. The
    /// broken egg lies there too, beside the spoon instead of under it.
    static func landing(ofEggFallingFrom offset: SIMD2<Double>) -> SIMD2<Double> {
        // Ellipses of almost the same shape, like the bowl's edge and the egg, touch where their centers are as far
        // apart as the ellipse whose half-axes are the sums of theirs.
        let clearance = bowlEdge + halfEgg * fallenEggScale
        let reach = offset / clearance
        let distance = (reach * reach).sum().squareRoot()
        return distance > 0 ? offset / distance : offset
    }
}
