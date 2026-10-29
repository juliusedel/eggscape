@testable import Eggscape
import EggscapeArt
import EggscapeCore
import Foundation
import Testing

/// The egg's half-width and half-height in bowl units.
private let halfEgg = SIMD2(SceneLayout.eggWidth, SceneLayout.eggWidth * EggArt.aspect) / 2

/// The physics positions on the tipping point, all around.
private func tippingPoints(_ layout: SceneLayout) -> [SIMD2<Double>] {
    (0 ..< 72).map { step in
        let angle = Double(step) * 5 * .pi / 180
        return layout.tippingPoint * SIMD2(cos(angle), sin(angle))
    }
}

struct SceneLayoutTests {
    /// A screen in points with the safe area the HUD keeps to (status bar hidden).
    struct Screen: CustomTestStringConvertible, Sendable {
        let size: CGSize
        let safeTop: CGFloat
        let safeBottom: CGFloat

        var testDescription: String {
            "\(Int(size.width)) × \(Int(size.height))"
        }

        static let iPhoneSE = Screen(size: CGSize(width: 375, height: 667), safeTop: 0, safeBottom: 0)
        static let iPhonePro = Screen(size: CGSize(width: 402, height: 874), safeTop: 62, safeBottom: 34)
        static let iPhoneProMax = Screen(size: CGSize(width: 440, height: 956), safeTop: 62, safeBottom: 34)
    }

    @Test func eggNearlyFillsTheBowl() {
        // The bowl's inner rim is 1.5 × 2 units: a few hundredths of a unit of it stay visible beside the egg, and the
        // 0.055-unit lip around it.
        let gap = SIMD2(0.75, 1.0) - halfEgg
        #expect(gap.x > 0.02 && gap.x < 0.05)
        #expect(gap.y > 0.02 && gap.y < 0.07)
    }

    @Test(arguments: [Screen.iPhoneSE, .iPhonePro, .iPhoneProMax])
    func spoonTakesAboutHalfTheWidth(screen: Screen) {
        let layout = SceneLayout(size: screen.size)
        let spoonWidth = 2 * SceneLayout.bowlEdge.x * Double(layout.unit) / Double(screen.size.width)
        #expect(spoonWidth > 0.4 && spoonWidth < 0.5)
        // The handle still runs off the bottom edge (its tip is 4.42 units below the bowl's center).
        #expect(layout.bowlCenter.y < 4.42 * layout.unit)
    }

    @Test func eggSitsInTheMiddleAtRest() {
        let layout = SceneLayout(size: Screen.iPhonePro.size)
        #expect(layout.eggOffset(for: .zero) == .zero)
    }

    @Test func atTheTippingPointTheEggRidesOverTheEdgeWithoutFloating() {
        let layout = SceneLayout(size: Screen.iPhonePro.size)
        let sideways = layout.eggOffset(for: SIMD2(layout.tippingPoint.x, 0))
        let forwards = layout.eggOffset(for: SIMD2(0, layout.tippingPoint.y))
        // A third of the egg's half-width hangs over the bowl's edge ...
        #expect(abs(sideways.x + halfEgg.x - SceneLayout.bowlEdge.x - halfEgg.x / 3) < 1e-12)
        #expect(abs(forwards.y + halfEgg.y - SceneLayout.bowlEdge.y - halfEgg.x / 3) < 1e-12)
        // ... while its center stays well inside the inner rim, all the way around.
        for position in tippingPoints(layout) {
            let center = layout.eggOffset(for: position) / SIMD2(0.75, 1.0)
            #expect((center * center).sum().squareRoot() < 0.5)
        }
    }

    @Test(arguments: [SIMD2(0.0, 0.0), SIMD2(0.2, -0.1), SIMD2(-0.3, 0.45), SIMD2(0.5, 0.2)])
    func fingerSteersTheEggUnderIt(position: SIMD2<Double>) {
        let layout = SceneLayout(size: Screen.iPhonePro.size)
        let finger = layout.point(inBowl: layout.eggOffset(for: position))
        let steering = TouchSteering(target: layout.eggPosition(forOffset: layout.bowlPosition(of: finger)))
        let rest = EggPhysics().restingPosition(tilt: steering.tilt)
        let drawn = layout.point(inBowl: layout.eggOffset(for: rest))
        #expect(abs(drawn.x - finger.x) < 1e-6)
        #expect(abs(drawn.y - finger.y) < 1e-6)
    }

    /// The HUD (`HUDView`) keeps to the safe area: its stats panel ends at most 90 pt below the top, 145 pt with the
    /// progress bar of a multiplayer race, at the largest text size it allows. The 92-pt sprint button sits 20 pt from
    /// the right and 24 pt from the bottom.
    @Test(arguments: [Screen.iPhoneSE, .iPhonePro, .iPhoneProMax])
    func eggAndBowlStayClearOfTheHUDAndTheSprintButton(screen: Screen) {
        let layout = SceneLayout(size: screen.size)
        let unit = Double(layout.unit)
        let hudBottom = Double(screen.size.height - screen.safeTop) - 145
        let sprint = CGRect(
            x: screen.size.width - 20 - 92,
            y: screen.safeBottom + 24,
            width: 92,
            height: 92
        )
        // The bowl's lip, and the egg wherever it may be drawn: at the tipping point it has grown by 5 %.
        var frames = [CGRect(
            x: Double(layout.bowlCenter.x) - SceneLayout.bowlEdge.x * unit,
            y: Double(layout.bowlCenter.y) - SceneLayout.bowlEdge.y * unit,
            width: 2 * SceneLayout.bowlEdge.x * unit,
            height: 2 * SceneLayout.bowlEdge.y * unit
        )]
        for position in tippingPoints(layout) {
            let center = layout.point(inBowl: layout.eggOffset(for: position))
            let half = halfEgg * 1.05 * unit
            frames.append(CGRect(
                x: Double(center.x) - half.x,
                y: Double(center.y) - half.y,
                width: 2 * half.x,
                height: 2 * half.y
            ))
        }
        #expect(frames.allSatisfy { Double($0.maxY) < hudBottom })
        #expect(frames.allSatisfy { !$0.intersects(sprint) })
    }
}
