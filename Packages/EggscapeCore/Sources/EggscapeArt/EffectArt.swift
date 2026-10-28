/// Weather effects: water on the spoon, falling rain, blowing leaves and splashes. Transparent images lit by the same
/// studio as the egg and the spoon, deterministic for a given seed.
public enum EffectArt {
    /// A water drop lying on a surface, seen from above, in a `diameter × diameter` image.
    public static func raindrop(diameter: Int, seed: UInt64) -> PixelImage {
        EffectRenderer.raindrop(diameter: diameter, seed: seed)
    }

    /// A falling rain streak, `length` pixels tall and pointing down the screen.
    public static func streak(length: Int) -> PixelImage {
        EffectRenderer.streak(length: length)
    }

    /// A small leaf, tip up, `length` pixels tall; the seed picks the species shape, the season's color and the
    /// curl.
    public static func leaf(length: Int, seed: UInt64) -> PixelImage {
        EffectRenderer.leaf(length: length, seed: seed)
    }

    /// A spray of droplets flying outwards from the center, in a `diameter × diameter` image.
    public static func splash(diameter: Int, seed: UInt64) -> PixelImage {
        EffectRenderer.splash(diameter: diameter, seed: seed)
    }
}
