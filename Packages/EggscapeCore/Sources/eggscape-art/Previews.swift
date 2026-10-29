import EggscapeArt
import EggscapeCore
import Foundation

/// The preview sheets: each composes artwork the way the game (or a product photo) shows it.
enum Previews {
    static let sheets = ["frame-white", "frame-rim", "spoon", "egg-studio", "skins", "broken", "effects"]

    static func render(_ name: String) -> PixelImage? {
        switch name {
        case "frame-white": frameWhite()
        case "frame-rim": frameRim()
        case "spoon": spoon()
        case "egg-studio": eggStudio()
        case "skins": skins()
        case "broken": broken()
        case "effects": effects()
        default: nil
        }
    }

    /// Offset of the egg's shadow relative to the egg, as a fraction of the egg width (away from the key light).
    static let shadowOffset = (x: -0.12, y: 0.025)

    /// The game screen on an iPhone (402 × 874 pt at 3x) with the white background, the egg just off the middle of the
    /// bowl, as after a small tilt to the right.
    static func frameWhite() -> PixelImage {
        frame(climb: (x: 0.17, y: 0.05))
    }

    /// The same screen with the egg at the sideways tipping point: it has ridden up onto the rim on the right and hangs
    /// over the bowl's edge.
    static func frameRim() -> PixelImage {
        frame(climb: (x: 1, y: 0))
    }

    /// The game screen composed like `SceneLayout` and `GameScene`: one bowl unit is `min(0.3 · width, 0.145 · height)`
    /// points, the bowl's center is at 53 % of the height, and the egg is 1.44 units wide. `climb` is the egg's
    /// physics position as a share of the tipping point on each axis.
    private static func frame(climb: (x: Double, y: Double)) -> PixelImage {
        let width = 1206, height = 2622
        let unit = min(402 * 0.3, 874 * 0.145) * 3
        let layout = SpoonArt.layout(unit: unit)
        var canvas = whiteBackground(width: width, height: height)
        let bowlX = Double(width) / 2
        let bowlY = Double(height) * (1 - 0.53)
        let left = bowlX - layout.bowlCenterX
        let top = bowlY - layout.bowlCenterY
        canvas.draw(SpoonArt.shadow(unit: unit), left: left, top: top)
        canvas.draw(SpoonArt.spoon(unit: unit), left: left, top: top)
        canvas.draw(SpoonArt.highlight(unit: unit), left: left, top: top, blend: .additive)

        // At the tipping point the egg hangs over the bowl's edge (0.805 × 1.055) by a third of its half-width.
        let eggWidth = 1.44
        let halfEgg = (x: eggWidth / 2, y: eggWidth * EggArt.aspect / 2)
        let travel = (x: 0.805 + halfEgg.x / 3 - halfEgg.x, y: 1.055 + halfEgg.x / 3 - halfEgg.y)
        let rimDistance = (climb.x * climb.x + climb.y * climb.y).squareRoot()
        let offset = (x: climb.x * travel.x, y: climb.y * travel.y)
        let eggX = bowlX + offset.x * unit
        let eggY = bowlY - offset.y * unit
        // The shadow image is 1.5 times the egg (see `EggArt.shadow`); `SceneLayout.eggShadowOffset` moves it to the
        // bottom left, and it stretches, moves out and fades a little as the egg climbs.
        let shadow = EggArt.shadow(width: Int((eggWidth * 1.5 * unit).rounded()))
        let stretched = resized(
            shadow,
            width: Int((Double(shadow.width) * (1 + 0.3 * abs(climb.x))).rounded()),
            height: Int((Double(shadow.height) * (1 + 0.25 * abs(climb.y))).rounded())
        )
        canvas.draw(
            stretched,
            left: eggX + (-0.19 * eggWidth + 0.08 * offset.x) * unit - Double(stretched.width) / 2,
            top: eggY - (-0.09 * eggWidth + 0.08 * offset.y) * unit - Double(stretched.height) / 2,
            opacity: 1 - 0.25 * rimDistance
        )
        // Closer to the eye as it rides up the rim.
        let grown = Int((eggWidth * (1 + 0.05 * rimDistance * rimDistance) * unit).rounded())
        canvas.draw(EggArt.egg(Samples.farmBrown, width: grown), centerX: eggX, centerY: eggY)
        return canvas.image
    }

    /// `image` scaled to `width × height` with bilinear filtering, like a stretched sprite.
    private static func resized(_ image: PixelImage, width: Int, height: Int) -> PixelImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let scaleX = Double(image.width) / Double(width), scaleY = Double(image.height) / Double(height)
        for row in 0 ..< height {
            let y = min(max((Double(row) + 0.5) * scaleY - 0.5, 0), Double(image.height - 1))
            let y0 = Int(y), y1 = min(y0 + 1, image.height - 1), wy = y - Double(y0)
            for column in 0 ..< width {
                let x = min(max((Double(column) + 0.5) * scaleX - 0.5, 0), Double(image.width - 1))
                let x0 = Int(x), x1 = min(x0 + 1, image.width - 1), wx = x - Double(x0)
                for channel in 0 ..< 4 {
                    func value(_ column: Int, _ row: Int) -> Double {
                        Double(image.rgba[(row * image.width + column) * 4 + channel])
                    }
                    let top = value(x0, y0) * (1 - wx) + value(x1, y0) * wx
                    let bottom = value(x0, y1) * (1 - wx) + value(x1, y1) * wx
                    bytes[(row * width + column) * 4 + channel] = UInt8((top * (1 - wy) + bottom * wy).rounded())
                }
            }
        }
        return PixelImage(width: width, height: height, rgba: bytes)
    }

    /// The spoon alone at game size (`u = 498`): with its shadow on the white background (left) and on a mid-gray,
    /// camera-like ground without a shadow (right), to judge the metal against both.
    static func spoon() -> PixelImage {
        let unit = 498.0
        let layout = SpoonArt.layout(unit: unit)
        let spoon = SpoonArt.spoon(unit: unit)
        let highlight = SpoonArt.highlight(unit: unit)
        var canvas = whiteBackground(width: 2 * layout.width, height: layout.height)
        canvas.fill(x: layout.width, y: 0, width: layout.width, height: layout.height, gray: 0.45)
        canvas.draw(SpoonArt.shadow(unit: unit), left: 0, top: 0)
        for side in 0 ..< 2 {
            let left = Double(side * layout.width)
            canvas.draw(spoon, left: left, top: 0)
            canvas.draw(highlight, left: left, top: 0, blend: .additive)
        }
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
            let falloff = 1 - 0.035 * min(dx * dx * 0.6 + dy * dy * 0.4, 1)
            return (base.0 * falloff, base.1 * falloff, base.2 * falloff)
        }
    }
}
