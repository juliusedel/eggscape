/// How an egg looks. Pure data: `EggscapeArt` turns it into pixels, the shop sells it as a skin.
public struct EggAppearance: Codable, Hashable, Sendable {
    /// An sRGB color with components in 0 ... 1.
    public struct Color: Codable, Hashable, Sendable {
        public var red: Double
        public var green: Double
        public var blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// From a hex value such as `0xC67B4A`.
        public init(hex: UInt32) {
            red = Double((hex >> 16) & 0xFF) / 255
            green = Double((hex >> 8) & 0xFF) / 255
            blue = Double(hex & 0xFF) / 255
        }
    }

    /// The surface of the shell.
    public enum Finish: String, Codable, Hashable, Sendable {
        /// A natural, slightly chalky eggshell.
        case matte
        /// Dyed egg with a soft sheen.
        case satin
        /// Lacquered, with crisp highlights.
        case glossy
        /// Iridescent mother-of-pearl shimmer.
        case pearl
        /// Polished metal such as gold or silver leaf.
        case metallic
    }

    /// Decoration on top of the base color. Patterns follow the curvature of the shell.
    public enum Pattern: Codable, Hashable, Sendable {
        case plain
        /// Natural speckles like on a brown hen's egg or a quail egg; `density` and `size` are 0 ... 1.
        case speckles(color: Color, density: Double, size: Double)
        /// Painted polka dots; `size` is 0 ... 1.
        case dots(color: Color, size: Double)
        /// Bands around the egg, repeating `colors` from the pointy end to the round end.
        case stripes(colors: [Color])
        case zigzag(color: Color)
        /// Swirled veins like marble.
        case marble(color: Color)
        /// Two-tone dip dye with `color` on the round half.
        case dipDye(color: Color)
        /// Many small flecks in `colors`.
        case confetti(colors: [Color])
        /// Small stars, e.g. on a dark blue night-sky egg.
        case stars(color: Color)
    }

    public var base: Color
    public var pattern: Pattern
    public var finish: Finish
    /// Seeds the natural irregularities, so every egg of a skin looks exactly the same.
    public var seed: UInt64

    public init(base: Color, pattern: Pattern = .plain, finish: Finish = .matte, seed: UInt64 = 1) {
        self.base = base
        self.pattern = pattern
        self.finish = finish
        self.seed = seed
    }
}
