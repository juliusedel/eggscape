import CoreGraphics
import EggscapeCore

/// Screen geometry of the game scene (scene coordinates, origin bottom left): a spoon seen from directly above fills
/// the screen, with the bowl's center at 53 % of the height and the handle running off the bottom edge.
struct SceneLayout: Equatable {
    let size: CGSize
    /// Points per bowl unit; the bowl's inner rim is `1.5 × 2` units.
    let unit: CGFloat
    let bowlCenter: CGPoint

    init(size: CGSize) {
        self.size = size
        unit = min(size.width * 0.4133, size.height * 0.2)
        bowlCenter = CGPoint(x: size.width / 2, y: size.height * 0.53)
    }

    /// Screen position of a point in bowl units.
    func point(inBowl position: SIMD2<Double>) -> CGPoint {
        CGPoint(x: bowlCenter.x + CGFloat(position.x) * unit, y: bowlCenter.y + CGFloat(position.y) * unit)
    }

    /// Bowl units of a screen position.
    func bowlPosition(of point: CGPoint) -> SIMD2<Double> {
        SIMD2(Double((point.x - bowlCenter.x) / unit), Double((point.y - bowlCenter.y) / unit))
    }
}
