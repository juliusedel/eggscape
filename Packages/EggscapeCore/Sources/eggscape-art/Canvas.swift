import EggscapeArt
import Foundation

/// A floating-point, premultiplied sRGB canvas for composing preview sheets the way SpriteKit draws sprites:
/// normal blending is `src + dst · (1 − src.alpha)`, additive blending is `src + dst`, both on encoded values.
struct Canvas {
    let width: Int
    let height: Int
    private(set) var pixels: [Float]

    /// An opaque canvas filled by `color(x, y)` (sRGB components 0 ... 1).
    init(width: Int, height: Int, color: (Int, Int) -> (Double, Double, Double)) {
        self.width = width
        self.height = height
        pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let (r, g, b) = color(x, y)
                let index = (y * width + x) * 4
                pixels[index] = Float(r)
                pixels[index + 1] = Float(g)
                pixels[index + 2] = Float(b)
            }
        }
    }

    /// A plain background.
    init(width: Int, height: Int, hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255, g = Double((hex >> 8) & 0xFF) / 255, b = Double(hex & 0xFF) / 255
        self.init(width: width, height: height) { _, _ in (r, g, b) }
    }

    enum Blend {
        case normal
        case additive
    }

    /// Draws `image` with its top-left corner at `(left, top)` (rounded to whole pixels).
    mutating func draw(_ image: PixelImage, left: Double, top: Double, blend: Blend = .normal, opacity: Double = 1) {
        let originX = Int(left.rounded()), originY = Int(top.rounded())
        let opacity = Float(opacity)
        for row in 0 ..< image.height {
            let y = originY + row
            guard y >= 0, y < height else { continue }
            for column in 0 ..< image.width {
                let x = originX + column
                guard x >= 0, x < width else { continue }
                let source = (row * image.width + column) * 4
                let alpha = Float(image.rgba[source + 3]) / 255 * opacity
                guard alpha > 0 || blend == .additive else { continue }
                let target = (y * width + x) * 4
                for channel in 0 ..< 3 {
                    let value = Float(image.rgba[source + channel]) / 255 * opacity
                    switch blend {
                    case .normal:
                        pixels[target + channel] = value + pixels[target + channel] * (1 - alpha)
                    case .additive:
                        pixels[target + channel] = min(pixels[target + channel] + value, 1)
                    }
                }
            }
        }
    }

    /// Draws `image` centered on `(x, y)`.
    mutating func draw(_ image: PixelImage, centerX: Double, centerY: Double, blend: Blend = .normal) {
        draw(image, left: centerX - Double(image.width) / 2, top: centerY - Double(image.height) / 2, blend: blend)
    }

    /// Fills a rectangle (used for the two-tone background of the effect sheet).
    mutating func fill(x: Int, y: Int, width w: Int, height h: Int, gray: Double) {
        for row in max(y, 0) ..< min(y + h, height) {
            for column in max(x, 0) ..< min(x + w, width) {
                let index = (row * width + column) * 4
                pixels[index] = Float(gray)
                pixels[index + 1] = Float(gray)
                pixels[index + 2] = Float(gray)
            }
        }
    }

    /// The finished, opaque image (with a tiny ordered dither so smooth gradients do not band).
    var image: PixelImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let index = (y * width + x) * 4
                let dither = (Float((x * 7 + y * 13) % 16) / 16 - 0.5) / 255
                for channel in 0 ..< 3 {
                    let value = (pixels[index + channel] + dither) * 255
                    bytes[index + channel] = UInt8(max(0, min(255, value.rounded())))
                }
            }
        }
        return PixelImage(width: width, height: height, rgba: bytes)
    }
}
