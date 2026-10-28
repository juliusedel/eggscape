/// A premultiplied RGBA8 image in the sRGB color space, rows from top to bottom.
///
/// This is the hand-over format of every renderer in `EggscapeArt`: the app wraps the bytes in a `CGImage`
/// (`premultipliedLast`, sRGB) for SpriteKit, and the `eggscape-art` tool writes them as PNG. Premultiplied means each
/// color channel is already multiplied by the pixel's alpha, so no channel is ever larger than alpha; transparent
/// pixels are all zero.
public struct PixelImage: Sendable, Equatable {
    public let width: Int
    public let height: Int
    /// Premultiplied sRGB bytes, `width * height * 4`, row-major starting with the top-left pixel.
    public var rgba: [UInt8]

    /// Wraps existing premultiplied bytes; `rgba.count` must be `width * height * 4`.
    public init(width: Int, height: Int, rgba: [UInt8]) {
        precondition(width >= 0 && height >= 0, "image size must not be negative")
        precondition(rgba.count == width * height * 4, "rgba must hold width * height * 4 bytes")
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    /// A fully transparent image.
    public init(width: Int, height: Int) {
        self.init(width: width, height: height, rgba: [UInt8](repeating: 0, count: max(width, 0) * max(height, 0) * 4))
    }

    /// The premultiplied bytes of the pixel in column `x` and row `y` (0 is the top row).
    public func pixel(x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        precondition(x >= 0 && x < width && y >= 0 && y < height, "pixel outside the image")
        let index = (y * width + x) * 4
        return (rgba[index], rgba[index + 1], rgba[index + 2], rgba[index + 3])
    }
}
