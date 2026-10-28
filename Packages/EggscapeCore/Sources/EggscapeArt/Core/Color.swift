import EggscapeCore
import Foundation

/// A color in linear sRGB (Rec. 709 primaries). Shading happens in linear light, where adding and scaling colors is
/// physically meaningful; only the final pixel is encoded with the sRGB transfer curve.
struct RGB: Sendable, Equatable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(gray: Double) {
        self.init(gray, gray, gray)
    }

    /// Converts an sRGB-encoded hex value such as `0xC8804E` to linear light.
    init(hex: UInt32) {
        self.init(
            ColorCurve.linear(fromEncoded: Double((hex >> 16) & 0xFF) / 255),
            ColorCurve.linear(fromEncoded: Double((hex >> 8) & 0xFF) / 255),
            ColorCurve.linear(fromEncoded: Double(hex & 0xFF) / 255)
        )
    }

    /// Converts an appearance color (sRGB-encoded components) to linear light.
    init(_ color: EggAppearance.Color) {
        self.init(
            ColorCurve.linear(fromEncoded: Num.clamp(color.red)),
            ColorCurve.linear(fromEncoded: Num.clamp(color.green)),
            ColorCurve.linear(fromEncoded: Num.clamp(color.blue))
        )
    }

    static let black = RGB(gray: 0)
    static let white = RGB(gray: 1)

    static func + (a: RGB, b: RGB) -> RGB {
        RGB(a.r + b.r, a.g + b.g, a.b + b.b)
    }

    static func - (a: RGB, b: RGB) -> RGB {
        RGB(a.r - b.r, a.g - b.g, a.b - b.b)
    }

    static func * (a: RGB, b: RGB) -> RGB {
        RGB(a.r * b.r, a.g * b.g, a.b * b.b)
    }

    static func * (a: RGB, s: Double) -> RGB {
        RGB(a.r * s, a.g * s, a.b * s)
    }

    static func * (s: Double, a: RGB) -> RGB {
        RGB(a.r * s, a.g * s, a.b * s)
    }

    static func / (a: RGB, s: Double) -> RGB {
        RGB(a.r / s, a.g / s, a.b / s)
    }

    static func += (a: inout RGB, b: RGB) {
        a = a + b
    }

    /// Relative luminance (Rec. 709 weights).
    var luminance: Double {
        0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    var maxComponent: Double {
        max(r, max(g, b))
    }

    func mixed(with other: RGB, _ t: Double) -> RGB {
        self + (other - self) * t
    }

    /// Raises each channel to `exponent`. For a translucent pigment this is "more of the same pigment": light that
    /// travels further through a dyed shell or a dense dye gets filtered more and comes out deeper and more saturated.
    func power(_ exponent: Double) -> RGB {
        RGB(
            r > 0 ? Foundation.pow(r, exponent) : 0,
            g > 0 ? Foundation.pow(g, exponent) : 0,
            b > 0 ? Foundation.pow(b, exponent) : 0
        )
    }

    /// Scales the saturation around the luminance; 0 gives gray, 1 leaves the color unchanged.
    func saturated(_ amount: Double) -> RGB {
        let gray = luminance
        return RGB(gray + (r - gray) * amount, gray + (g - gray) * amount, gray + (b - gray) * amount)
    }

    func clamped(_ low: Double = 0, _ high: Double = 1) -> RGB {
        RGB(Num.clamp(r, low, high), Num.clamp(g, low, high), Num.clamp(b, low, high))
    }
}

/// The sRGB transfer curve, with a lookup table for the hot direction (linear to 8-bit).
enum ColorCurve {
    static func linear(fromEncoded value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    static func encoded(fromLinear value: Double) -> Double {
        let value = Num.clamp(value)
        return value <= 0.003_130_8 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
    }

    private static let tableSize = 4096
    /// `encoded(fromLinear:)` sampled at `tableSize + 1` points; interpolated linearly, the error stays far below
    /// one 8-bit step.
    private static let table: [Double] = (0 ... tableSize).map { encoded(fromLinear: Double($0) / Double(tableSize)) }

    /// Fast sRGB encoding of a linear value in 0 ... 1 (values outside are clamped).
    static func fastEncoded(_ value: Double) -> Double {
        let position = Num.clamp(value) * Double(tableSize)
        let index = min(Int(position), tableSize - 1)
        let fraction = position - Double(index)
        return table[index] + (table[index + 1] - table[index]) * fraction
    }
}

/// The "camera" of the studio: turns scene radiance into display values the way the owner's reference photo does.
///
/// The reference is a bright product shot: the white table is blown out, the lit side of the brown egg clips in the
/// red channel and turns peach, while the shadow side keeps a deep, saturated orange. Measured on the photo, that is
/// a camera that adds about 20 % saturation and develops each channel with the film-like curve `1 − exp(−x^1.6)`
/// (a toe that deepens shadows, a shoulder that rolls highlights off to white). All artwork goes through it, so the
/// spoon, the egg and the effects share one photographic look.
enum Film {
    static let saturation = 1.12
    static let contrast = 1.6

    /// Display-linear value (0 ..< 1) for one channel of scene radiance.
    static func curve(_ value: Double) -> Double {
        guard value > 0 else { return 0 }
        return 1 - exp(-pow(value, contrast))
    }

    static func develop(_ color: RGB) -> RGB {
        let gray = color.luminance
        let r = gray + (color.r - gray) * saturation
        let g = gray + (color.g - gray) * saturation
        let b = gray + (color.b - gray) * saturation
        return RGB(curve(r), curve(g), curve(b))
    }

    /// Scene radiance of a gray that develops to the given display value; used to match reference colors such as
    /// the game's white background.
    static func radiance(forDisplay display: Double) -> Double {
        let display = Num.clamp(display, 0, 0.999_999)
        return pow(-log(1 - display), 1 / contrast)
    }
}
