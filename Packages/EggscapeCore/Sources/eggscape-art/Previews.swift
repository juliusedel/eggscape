import EggscapeArt
import EggscapeCore
import Foundation

/// The preview sheets: each composes artwork the way the game (or a product photo) shows it.
enum Previews {
    static let sheets = ["frame-white", "egg-studio", "skins", "broken", "effects"]

    static func render(_ name: String) -> PixelImage? {
        switch name {
        case "frame-white": frameWhite()
        case "egg-studio": eggStudio()
        case "skins": skins()
        case "broken": broken()
        case "effects": effects()
        default: nil
        }
    }

    /// Offset of the egg's shadow relative to the egg, as a fraction of the egg width (away from the key light).
    static let shadowOffset = (x: -0.12, y: 0.025)

    /// The game screen on an iPhone (402 × 874 pt at 3x) with the white background.
    static func frameWhite() -> PixelImage {
        let width = 1206, height = 2622
        let unit = 498.0
        let layout = SpoonArt.layout(unit: unit)
        var canvas = whiteBackground(width: width, height: height)
        let bowlX = Double(width) / 2
        let bowlY = Double(height) * (1 - 0.53)
        let left = bowlX - layout.bowlCenterX
        let top = bowlY - layout.bowlCenterY
        canvas.draw(SpoonArt.shadow(unit: unit), left: left, top: top)
        canvas.draw(SpoonArt.spoon(unit: unit), left: left, top: top)
        canvas.draw(SpoonArt.highlight(unit: unit), left: left, top: top, blend: .additive)

        let eggWidth = Int((0.62 * unit).rounded())
        let eggX = bowlX + 0.1 * unit
        let eggY = bowlY + 0.02 * unit
        let shadow = EggArt.shadow(width: Int((Double(eggWidth) * 1.5).rounded()))
        canvas.draw(
            shadow,
            centerX: eggX + shadowOffset.x * Double(eggWidth) * 0.8,
            centerY: eggY + shadowOffset.y * Double(eggWidth) * 0.8
        )
        canvas.draw(EggArt.egg(Samples.farmBrown, width: eggWidth), centerX: eggX, centerY: eggY)
        return canvas.image
    }

    /// The shop's brown egg ("farm-brown") alone on white, composed like the owner's reference photo (1333 × 2000,
    /// egg 320 px wide).
    static func eggStudio() -> PixelImage {
        var canvas = Canvas(width: 1333, height: 2000, hex: 0xFFFFFF)
        let eggWidth = 320
        let centerX = 668.0, centerY = 1048.0
        canvas.draw(
            EggArt.shadow(width: eggWidth * 3 / 2),
            centerX: centerX + shadowOffset.x * Double(eggWidth),
            centerY: centerY + shadowOffset.y * Double(eggWidth)
        )
        canvas.draw(EggArt.egg(SkinCatalog.farmBrown.appearance, width: eggWidth), centerX: centerX, centerY: centerY)
        return canvas.image
    }

    /// Every skin the shop sells, in catalog order, with its shadow on the game's white background.
    static func skins() -> PixelImage {
        let appearances = SkinCatalog.all.map(\.appearance)
        let columns = 5
        let eggWidth = 200
        let cellWidth = 270, cellHeight = 340
        let rows = (appearances.count + columns - 1) / columns
        var canvas = Canvas(width: columns * cellWidth, height: rows * cellHeight, hex: 0xF7F6F3)
        for (index, appearance) in appearances.enumerated() {
            let centerX = Double(index % columns * cellWidth + cellWidth / 2)
            let centerY = Double(index / columns * cellHeight + cellHeight / 2)
            canvas.draw(
                EggArt.shadow(width: eggWidth * 3 / 2),
                centerX: centerX + shadowOffset.x * Double(eggWidth),
                centerY: centerY + shadowOffset.y * Double(eggWidth)
            )
            canvas.draw(EggArt.egg(appearance, width: eggWidth), centerX: centerX, centerY: centerY)
        }
        return canvas.image
    }

    /// Broken eggs of a few skins (farm brown, classic white, gold metallic, polka dots) on white (top) and on a
    /// mid-gray, camera-like ground (bottom).
    static func broken() -> PixelImage {
        let appearances = [Samples.farmBrown, Samples.skins[1], Samples.skins[6], Samples.skins[7]]
        let size = 400
        let cellWidth = 440, cellHeight = 360
        var canvas = Canvas(width: appearances.count * cellWidth, height: 2 * cellHeight, hex: 0xF7F6F3)
        canvas.fill(x: 0, y: cellHeight, width: appearances.count * cellWidth, height: cellHeight, gray: 0.45)
        for row in 0 ..< 2 {
            for (index, appearance) in appearances.enumerated() {
                canvas.draw(
                    EggArt.broken(appearance, width: size),
                    centerX: Double(index * cellWidth + cellWidth / 2),
                    centerY: Double(row * cellHeight + cellHeight / 2)
                )
            }
        }
        return canvas.image
    }

    /// Raindrops of several sizes, streaks, six leaves and splashes on white (left) and mid-gray (right).
    static func effects() -> PixelImage {
        let half = 700, height = 760
        var canvas = Canvas(width: 2 * half, height: height, hex: 0xF7F6F3)
        canvas.fill(x: half, y: 0, width: half, height: height, gray: 0.45)
        for side in 0 ..< 2 {
            let originX = Double(side * half)
            for (index, diameter) in [34, 48, 62, 80, 110].enumerated() {
                canvas.draw(
                    EffectArt.raindrop(diameter: diameter, seed: UInt64(index + 1)),
                    centerX: originX + 70 + Double(index) * 125,
                    centerY: 100
                )
            }
            for index in 0 ..< 3 {
                canvas.draw(
                    EffectArt.streak(length: 160 + 60 * index),
                    centerX: originX + 50 + Double(index) * 45,
                    centerY: 370
                )
            }
            for index in 0 ..< 6 {
                canvas.draw(
                    EffectArt.leaf(length: 110, seed: UInt64(index * 7 + 3)),
                    centerX: originX + 240 + Double(index % 3) * 95,
                    centerY: 290 + Double(index / 3) * 140
                )
            }
            canvas.draw(EffectArt.splash(diameter: 220, seed: 9), centerX: originX + 590, centerY: 340)
            for index in 0 ..< 3 {
                canvas.draw(
                    EffectArt.splash(diameter: 110, seed: UInt64(20 + index)),
                    centerX: originX + 120 + Double(index) * 220,
                    centerY: 650
                )
            }
        }
        return canvas.image
    }

    /// `#F7F6F3` with a barely visible radial vignette.
    static func whiteBackground(width: Int, height: Int) -> Canvas {
        let base = (247.0 / 255, 246.0 / 255, 243.0 / 255)
        return Canvas(width: width, height: height) { x, y in
            let dx = (Double(x) + 0.5) / Double(width) * 2 - 1
            let dy = (Double(y) + 0.5) / Double(height) * 2 - 1
            let falloff = 1 - 0.035 * min((dx * dx * 0.6 + dy * dy * 0.4), 1)
            return (base.0 * falloff, base.1 * falloff, base.2 * falloff)
        }
    }
}
