import EggscapeCore

/// Photo-realistic eggs seen from directly above, lit like the owner's reference photo (key light from the top
/// right). Pure functions: the same appearance and size always give the same bytes.
public enum EggArt {
    /// Height divided by width of the egg seen from above (it lies on its side, pointy end up).
    public static let aspect: Double = 1.32

    /// How much larger than the egg the shadow image is (see `shadow(width:)`).
    static let shadowSpread = 1.5

    /// The egg alone on a transparent background, pointy end up, `width` pixels wide and `round(width · aspect)` tall.
    ///
    /// The outline touches all four image edges; the shading includes the shell's grain, the pattern and the finish,
    /// but no shadow. Typical cost: about 0.1 s for 320 pixels on an iPhone-class CPU, so cache the result per skin.
    public static func egg(_ appearance: EggAppearance, width: Int) -> PixelImage {
        EggRenderer.egg(appearance, width: width)
    }

    /// The egg's soft shadow, centered in an image of `width × round(width · aspect)` pixels.
    ///
    /// It holds a dark contact core and a soft cast shadow; the egg's own outline covers the central two thirds
    /// (`1 / 1.5`) of the image, so draw it 1.5 times as large as the egg, centered under it, and let the scene offset
    /// it towards the bottom left (away from the key light). Its color is a cool near-black with alpha, for normal
    /// blending.
    public static func shadow(width: Int) -> PixelImage {
        EggRenderer.shadow(width: width)
    }

    /// An egg smashed on the ground, seen from above: a puddle of egg white, a domed yolk and a few shell pieces that
    /// show the skin outside and the white membrane inside. `width` pixels wide and `round(width · 0.8)` tall, centered.
    public static func broken(_ appearance: EggAppearance, width: Int) -> PixelImage {
        BrokenEggRenderer.render(appearance, width: width)
    }
}
