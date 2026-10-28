import EggscapeArt
import EggscapeCore
import Foundation

/// The 1024 × 1024 app icon: the game's stainless-steel spoon with the brown "farm-brown" egg in its bowl, rendered by
/// `EggscapeArt` exactly as in the game and laid diagonally (bowl at the top right, handle running out at the bottom
/// left) on a warm yolk-colored surface.
enum AppIcon {
    static let size = 1024

    /// Icon pixels per bowl unit.
    private static let iconUnit = 300.0
    /// The layers are rendered at this multiple of the icon's resolution and sampled `n × n` times per icon pixel.
    private static let supersampling = 2
    /// Angle between the handle and straight down; the handle points to the bottom left.
    private static let tilt = 40.0 * Double.pi / 180
    /// The bowl's center in the icon, in pixels from the top left.
    private static let bowlCenter = (x: 588.0, y: 436.0)
    /// The egg's shadow relative to the egg, in bowl units (as in `GameScene`: away from the light at the top right).
    private static let eggShadowOffset = (x: -0.11, y: 0.07)
    /// The egg's width in bowl units: larger than in the game (0.62) so it still reads at home-screen size.
    private static let eggWidth = 0.8

    private struct Layer {
        let image: PixelImage
        /// Top-left corner in layer pixels, relative to the bowl's center.
        let left: Double
        let top: Double
        let additive: Bool
    }

    static func render() -> PixelImage {
        let unit = iconUnit * Double(supersampling)
        let layout = SpoonArt.layout(unit: unit)
        let egg = EggArt.egg(SkinCatalog.farmBrown.appearance, width: Int((eggWidth * unit).rounded()))
        // The shadow image is 1.5 times the egg (see `EggArt.shadow`).
        let eggShadow = EggArt.shadow(width: Int((Double(egg.width) * 1.5).rounded()))
        let spoonLeft = -layout.bowlCenterX, spoonTop = -layout.bowlCenterY
        let layers = [
            Layer(image: SpoonArt.shadow(unit: unit), left: spoonLeft, top: spoonTop, additive: false),
            Layer(image: SpoonArt.spoon(unit: unit), left: spoonLeft, top: spoonTop, additive: false),
            Layer(image: SpoonArt.highlight(unit: unit), left: spoonLeft, top: spoonTop, additive: true),
            Layer(
                image: eggShadow,
                left: eggShadowOffset.x * unit - Double(eggShadow.width) / 2,
                top: eggShadowOffset.y * unit - Double(eggShadow.height) / 2,
                additive: false
            ),
            Layer(image: egg, left: -Double(egg.width) / 2, top: -Double(egg.height) / 2, additive: false),
        ]

        let cosine = cos(tilt), sine = sin(tilt)
        let samples = supersampling * supersampling
        var bytes = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0 ..< size {
            for x in 0 ..< size {
                var sum = (0.0, 0.0, 0.0)
                for subsample in 0 ..< samples {
                    let iconX = Double(x) + (Double(subsample % supersampling) + 0.5) / Double(supersampling)
                    let iconY = Double(y) + (Double(subsample / supersampling) + 0.5) / Double(supersampling)
                    // Undo the rotation that turns the upright spoon's handle (straight down) to the bottom left.
                    let dx = (iconX - bowlCenter.x) * Double(supersampling)
                    let dy = (iconY - bowlCenter.y) * Double(supersampling)
                    let sceneX = cosine * dx + sine * dy
                    let sceneY = -sine * dx + cosine * dy
                    var color = background(x: iconX, y: iconY)
                    for layer in layers {
                        let source = sample(layer.image, x: sceneX - layer.left, y: sceneY - layer.top)
                        if layer.additive {
                            color = (min(color.0 + source.0, 1), min(color.1 + source.1, 1), min(color.2 + source.2, 1))
                        } else {
                            let keep = 1 - source.3
                            color = (source.0 + color.0 * keep, source.1 + color.1 * keep, source.2 + color.2 * keep)
                        }
                    }
                    sum = (sum.0 + color.0, sum.1 + color.1, sum.2 + color.2)
                }
                let index = (y * size + x) * 4
                // A tiny ordered dither keeps the smooth background from banding.
                let dither = (Double((x * 7 + y * 13) % 16) / 16 - 0.5) / 255
                for (channel, value) in [sum.0, sum.1, sum.2].enumerated() {
                    let encoded = (value / Double(samples) + dither) * 255
                    bytes[index + channel] = UInt8(max(0, min(255, encoded.rounded())))
                }
            }
        }
        return PixelImage(width: size, height: size, rgba: bytes)
    }

    /// Writes `AppIcon.png` (opaque, as the App Store requires) and the icon set's `Contents.json`.
    static func write(to iconSet: URL) throws {
        try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
        try PNGFile.write(render(), to: iconSet.appendingPathComponent("AppIcon.png"), opaque: true)
        let contents = """
        {
          "images" : [
            {
              "filename" : "AppIcon.png",
              "idiom" : "universal",
              "platform" : "ios",
              "size" : "1024x1024"
            }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }

        """
        try Data(contents.utf8).write(to: iconSet.appendingPathComponent("Contents.json"))
    }

    /// The surface: a yolk-to-orange gradient from the top right to the bottom left, with a soft glow at the top right
    /// where the light comes from.
    private static func background(x: Double, y: Double) -> (Double, Double, Double) {
        let yolk = (1.0, 0.827, 0.431), orange = (0.941, 0.541, 0.141)
        let start = (x: 900.0, y: 0.0), end = (x: 80.0, y: 1024.0)
        let along = (end.x - start.x, end.y - start.y)
        let t = max(
            0,
            min(1, ((x - start.x) * along.0 + (y - start.y) * along.1) / (along.0 * along.0 + along.1 * along.1))
        )
        var color = (
            yolk.0 + (orange.0 - yolk.0) * t,
            yolk.1 + (orange.1 - yolk.1) * t,
            yolk.2 + (orange.2 - yolk.2) * t
        )
        let glow = 0.4 * max(0, 1 - ((x - 820) * (x - 820) + (y - 164) * (y - 164)).squareRoot() / 620)
        color = (color.0 + (1 - color.0) * glow, color.1 + (1 - color.1) * glow, color.2 + (1 - color.2) * glow)
        return color
    }

    /// Bilinear sample of premultiplied components at `(x, y)` in pixel units (pixel centers at `.5`); transparent
    /// outside the image.
    private static func sample(_ image: PixelImage, x: Double, y: Double) -> (Double, Double, Double, Double) {
        let fx = x - 0.5, fy = y - 0.5
        let x0 = Int(fx.rounded(.down)), y0 = Int(fy.rounded(.down))
        guard x0 >= -1, y0 >= -1, x0 < image.width, y0 < image.height else { return (0, 0, 0, 0) }
        let wx = fx - Double(x0), wy = fy - Double(y0)
        var result = (0.0, 0.0, 0.0, 0.0)
        for (column, row, weight) in [
            (x0, y0, (1 - wx) * (1 - wy)), (x0 + 1, y0, wx * (1 - wy)),
            (x0, y0 + 1, (1 - wx) * wy), (x0 + 1, y0 + 1, wx * wy),
        ] where column >= 0 && row >= 0 && column < image.width && row < image.height && weight > 0 {
            let index = (row * image.width + column) * 4
            result.0 += Double(image.rgba[index]) / 255 * weight
            result.1 += Double(image.rgba[index + 1]) / 255 * weight
            result.2 += Double(image.rgba[index + 2]) / 255 * weight
            result.3 += Double(image.rgba[index + 3]) / 255 * weight
        }
        return result
    }
}
