/// A polished stainless-steel serving spoon seen from directly above, bowl at the top, handle running straight down.
///
/// The bowl's inner rim is exactly the physics rim `(x / 0.75)² + y² = 1` (bowl units, `y` up), so the rendered bowl
/// and the simulated one agree. All three layers share one size and registration: draw the shadow on the white
/// background, the spoon on top, then the highlight with additive blending, shifted by a few points with the tilt.
public enum SpoonArt {
    /// Where the spoon sits in its images.
    public struct Layout: Sendable, Equatable {
        /// Image size in pixels.
        public let width: Int, height: Int
        /// Bowl center in pixels from the left.
        public let bowlCenterX: Double
        /// Bowl center in pixels from the top.
        public let bowlCenterY: Double
        /// Pixels per bowl unit.
        public let unit: Double
    }

    /// Image size and bowl position for `unit` pixels per bowl unit.
    ///
    /// The image is `2 · (0.805 + 0.44)` units wide with the bowl centered, reaches 0.2 units above the bowl's lip and
    /// 4.6 units below the bowl center, so the handle runs at least 3.2 units below the bowl and off the bottom of a
    /// phone screen. The transparent margins leave room for the shadow.
    public static func layout(unit: Double) -> Layout {
        SpoonGeometry.layout(unit: unit)
    }

    /// The spoon on a transparent background, lit by the studio (without the moving part of the key reflection,
    /// which is in `highlight(unit:)`).
    public static func spoon(unit: Double) -> PixelImage {
        SpoonRenderer.render(.spoon, unit: unit)
    }

    /// The spoon's soft shadow on a white surface, falling towards the bottom left; same size and registration as
    /// `spoon(unit:)`. Only for the white background.
    public static func shadow(unit: Double) -> PixelImage {
        SpoonRenderer.render(.shadow, unit: unit)
    }

    /// The reflection of the key soft box alone, for additive blending over `spoon(unit:)` (same size and
    /// registration). Unshifted, spoon plus highlight is the complete render; the game shifts this layer slightly
    /// with the tilt so the metal reacts to movement. It fades out towards the outline, so a small shift never
    /// spills past the spoon's edge.
    public static func highlight(unit: Double) -> PixelImage {
        SpoonRenderer.render(.highlight, unit: unit)
    }
}
