import CoreGraphics
import EggscapeCore

/// Screen geometry of the game scene (scene coordinates, origin bottom left): the landscape fills the screen, the
/// spoon fills the lower 40 % in a slightly top-down view.
struct SceneLayout: Equatable {
    /// Lengths along the handle look shorter because the spoon is seen slightly from above.
    static let foreshortening: CGFloat = 0.87

    let size: CGSize
    /// Points per bowl unit: sideways (`width`) and along the handle (`height`).
    let unit: CGSize
    let bowlCenter: CGPoint

    init(size: CGSize, config: GameConfig = .standard) {
        self.size = size
        let sideways = min(size.width * 0.4, size.height * 0.18)
        unit = CGSize(width: sideways, height: sideways * Self.foreshortening)
        let rimHeight = CGFloat(config.bowlRadiusY) * unit.height
        bowlCenter = CGPoint(x: size.width / 2, y: size.height * 0.4 - rimHeight - size.height * 0.012)
    }

    /// Height of the spoon area at the bottom of the screen.
    var spoonAreaHeight: CGFloat {
        size.height * 0.4
    }

    /// The landscape above the spoon.
    var worldRect: CGRect {
        CGRect(x: 0, y: spoonAreaHeight, width: size.width, height: size.height - spoonAreaHeight)
    }

    /// Height of the track surface the runner runs on.
    var trackY: CGFloat {
        worldRect.minY + worldRect.height * 0.16
    }

    /// Horizontal position of the runner.
    var runnerX: CGFloat {
        size.width * 0.28
    }

    /// How many points of track one meter takes on screen.
    var pointsPerMeter: CGFloat {
        size.width / 8
    }

    func point(inBowl position: SIMD2<Double>) -> CGPoint {
        CGPoint(
            x: bowlCenter.x + CGFloat(position.x) * unit.width,
            y: bowlCenter.y + CGFloat(position.y) * unit.height
        )
    }

    func bowlPosition(of point: CGPoint) -> SIMD2<Double> {
        SIMD2(
            Double((point.x - bowlCenter.x) / unit.width),
            Double((point.y - bowlCenter.y) / unit.height)
        )
    }
}
