@testable import EggscapeArt
import Foundation
import Testing

/// Checks every pixel of `image` for the premultiplied-alpha invariant: no color channel exceeds alpha.
private func allPremultiplied(_ image: PixelImage) -> Bool {
    stride(from: 0, to: image.rgba.count, by: 4).allSatisfy { index in
        let alpha = image.rgba[index + 3]
        return image.rgba[index] <= alpha && image.rgba[index + 1] <= alpha && image.rgba[index + 2] <= alpha
    }
}

struct SpoonArtTests {
    /// Small enough to render quickly in a debug build, large enough to resolve the 0.055-unit lip (3.3 px).
    static let unit = 60.0
    static let layout = SpoonArt.layout(unit: unit)
    static let spoon = SpoonArt.spoon(unit: unit)
    static let shadow = SpoonArt.shadow(unit: unit)
    static let highlight = SpoonArt.highlight(unit: unit)

    /// The pixel containing the point `(x, y)` in bowl units (`y` up).
    private static func pixel(_ image: PixelImage, x: Double, y: Double)
        -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)
    {
        let column = Int((layout.bowlCenterX + x * unit).rounded(.down))
        let row = Int((layout.bowlCenterY - y * unit).rounded(.down))
        return image.pixel(x: column, y: row)
    }

    @Test func layersShareSizeAndRegistration() {
        for image in [Self.spoon, Self.shadow, Self.highlight] {
            #expect(image.width == Self.layout.width)
            #expect(image.height == Self.layout.height)
            #expect(image.rgba.count == image.width * image.height * 4)
        }
        // Registration: the bowl is centered horizontally and its lip ends 0.2 units below the top edge.
        #expect(Self.layout.bowlCenterX == Double(Self.layout.width) / 2)
        #expect(abs(Self.layout.bowlCenterY - 1.255 * Self.unit) < 1e-9)
    }

    @Test func layoutScalesWithTheUnit() {
        let small = SpoonArt.layout(unit: 100)
        let large = SpoonArt.layout(unit: 498)
        #expect(large.width == 1240)
        #expect(abs(Double(large.width) / Double(small.width) - 4.98) < 0.01)
        #expect(abs(large.bowlCenterY / small.bowlCenterY - 4.98) < 1e-9)
        #expect(large.unit == 498)
    }

    @Test func innerRimIsTheExactPhysicsEllipse() {
        for step in 0 ..< 32 {
            let angle = Double(step) / 32 * 2 * .pi
            let x = 0.75 * cos(angle), y = sin(angle)
            #expect(abs(SpoonGeometry.rimDistance(x, y)) < 1e-12)
            #expect(SpoonGeometry.surface(x * 0.999, y * 0.999).inBowl)
            #expect(!SpoonGeometry.surface(x * 1.001, y * 1.001).inBowl)
        }
    }

    @Test func pixelsJustInsideTheRimAreOpaqueSteel() {
        for step in 0 ..< 24 {
            let angle = Double(step) / 24 * 2 * .pi
            let inside = Self.pixel(Self.spoon, x: 0.75 * 0.96 * cos(angle), y: 0.96 * sin(angle))
            #expect(inside.alpha == 255, "rim pixel at \(step) is not opaque")
            // Steel is a neutral to slightly cool gray: no channel strays far from the others.
            #expect(abs(Int(inside.red) - Int(inside.blue)) < 24, "rim pixel at \(step) is not gray")
        }
        #expect(Self.pixel(Self.spoon, x: 0, y: 0).alpha == 255)
    }

    @Test func outsideTheLipBesideTheHandleIsTransparent() {
        for image in [Self.spoon, Self.highlight] {
            #expect(Self.pixel(image, x: 0.6, y: -1.6).alpha == 0)
            #expect(Self.pixel(image, x: -0.6, y: -1.6).alpha == 0)
            #expect(Self.pixel(image, x: 0.9, y: 0).alpha == 0)
            #expect(Self.pixel(image, x: -0.9, y: 0).alpha == 0)
            #expect(Self.pixel(image, x: 0, y: 1.12).alpha == 0)
        }
    }

    @Test func handleRunsOffTheBottomOfThePhone() {
        // At least 3.2 units below the bowl's outer edge (1.055 below its center) the handle is still there.
        let depth = -(1.055 + 3.2)
        #expect(Self.pixel(Self.spoon, x: 0, y: depth).alpha == 255)
        #expect(Self.pixel(Self.spoon, x: 0, y: -2.0).alpha == 255)
        // The neck is about 0.28 units wide and the handle widens to about 0.42.
        #expect(Self.pixel(Self.spoon, x: 0.1, y: -1.3).alpha == 255)
        #expect(Self.pixel(Self.spoon, x: 0.18, y: -1.3).alpha == 0)
        #expect(Self.pixel(Self.spoon, x: 0.17, y: -3.9).alpha == 255)
        #expect(Self.pixel(Self.spoon, x: 0.25, y: -3.9).alpha == 0)
    }

    @Test func everyLayerIsPremultiplied() {
        #expect(allPremultiplied(Self.spoon))
        #expect(allPremultiplied(Self.shadow))
        #expect(allPremultiplied(Self.highlight))
    }

    @Test func renderingIsDeterministic() {
        #expect(SpoonArt.spoon(unit: Self.unit) == Self.spoon)
        #expect(SpoonArt.shadow(unit: Self.unit) == Self.shadow)
        #expect(SpoonArt.highlight(unit: Self.unit) == Self.highlight)
    }

    @Test func highlightAddsLightOnlyWellInsideTheOutline() {
        let image = Self.highlight
        var lit = 0
        for row in 0 ..< image.height {
            for column in 0 ..< image.width {
                let value = image.pixel(x: column, y: row)
                guard value.red > 0 || value.green > 0 || value.blue > 0 else { continue }
                lit += 1
                let x = (Double(column) + 0.5 - Self.layout.bowlCenterX) / Self.unit
                let y = (Self.layout.bowlCenterY - Double(row) - 0.5) / Self.unit
                // A shift of a few points must never carry light past the edge.
                #expect(SpoonGeometry.outlineDistance(x, y) < -0.035)
            }
        }
        #expect(lit > 100, "the key soft box should show in the bowl and along the handle")
    }

    @Test func shadowFallsTowardsTheBottomLeft() {
        func centroid(_ image: PixelImage) -> (x: Double, y: Double) {
            var sum = 0.0, sumX = 0.0, sumY = 0.0
            for row in 0 ..< image.height {
                for column in 0 ..< image.width {
                    let alpha = Double(image.pixel(x: column, y: row).alpha)
                    sum += alpha
                    sumX += alpha * Double(column)
                    sumY += alpha * Double(row)
                }
            }
            return (sumX / max(sum, 1), sumY / max(sum, 1))
        }
        let spoon = centroid(Self.spoon)
        let shadow = centroid(Self.shadow)
        #expect(shadow.x < spoon.x)
        #expect(shadow.y > spoon.y)
        // Soft and light, like the reference photo: never a solid black.
        let darkest = stride(from: 3, to: Self.shadow.rgba.count, by: 4).map { Self.shadow.rgba[$0] }.max() ?? 0
        #expect(darkest > 40)
        #expect(darkest < 160)
    }
}
