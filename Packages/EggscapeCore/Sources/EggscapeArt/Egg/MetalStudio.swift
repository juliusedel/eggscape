import Foundation

/// The studio as a polished metal shell sees it.
///
/// A mirror shows the room, not the light. Photographers therefore surround chrome and gold with white (a white sweep
/// under the object, white cards around it, a diffusion scrim above) and keep their soft boxes: the reflections are
/// then mostly bright, with smooth gradients into one darker band where the sweep curves up into the cards near the
/// horizon. That band is what draws the shape of polished metal; without it a mirror egg reads as a flat disc, and
/// with the dark flag of the main `Studio` (which the matte shells need for their deep shadow side) it reads as black
/// chrome.
///
/// The soft boxes are `Studio.key` and `Studio.fill` themselves, so the metal highlights sit exactly where the shells'
/// highlights sit, and the room is a little darker on the far side, so metal eggs shade towards the bottom left like
/// every other piece of artwork. Seen from above, the sweep fills the outer half of the egg, the band lies at about
/// 70 % of the way to the outline, and the scrim and the soft boxes fill the middle.
enum MetalStudio {
    /// The lit white sweep right around the object, on the key side and on the far side.
    static let sweep = (key: 2.5, far: 1.25)
    /// The white cards around the object, lit by the spill of the soft boxes.
    static let cards = (key: 1.6, far: 0.75)
    /// The diffusion scrim overhead, and how much brighter it is towards the key.
    static let scrim = 1.2
    static let scrimGradient = 0.35
    /// Radiance where the sweep curves into the cards (the darker band), on the key side and on the far side.
    static let band = (key: 1.15, far: 0.3)

    /// Radiance of the tent (without the soft boxes) in `direction`, pre-blurred by `blur` radians.
    static func ambient(_ direction: Vec3, blur: Double) -> Double {
        let z = direction.z
        let side = Studio.towardsKey(direction.x, direction.y)
        let valley = Num.mix(band.far, band.key, side)
        // Below the horizon: the sweep, brightest close to the object and falling off as it recedes and curves up;
        // softly darker straight below the outline on the far side, where the object casts its shadow.
        let shade = (1 - Studio.towardsKey(direction.x, direction.y, low: -0.9, high: 0.4))
            * Num.smoothstep(0.5, 1.0 + blur, -z)
        let near = Num.mix(sweep.far, sweep.key, side) * (1 - 0.45 * shade)
        let floor = Num.mix(valley, near, Num.smoothstep(0, 0.5 + blur, -z))
        // Above: out of the band into the cards, then the scrim overhead. The scrim's gradient uses the plain dot
        // product with the key side, which stays smooth straight overhead where an azimuth would not.
        let towardsKey = direction.x * Studio.keySide.x + direction.y * Studio.keySide.y
        let overhead = scrim * (1 + scrimGradient * towardsKey)
        var sky = Num.mix(valley, Num.mix(cards.far, cards.key, side), Num.smoothstep(0, 0.32 + blur, z))
        sky = Num.mix(sky, overhead, Num.smoothstep(0.3, 0.85 + blur, z))
        let horizon = 0.02 + blur
        return Num.mix(floor, sky, Num.smoothstep(-horizon, horizon, z))
    }

    /// Radiance arriving from `direction` (tent plus soft boxes), pre-blurred by `blur` radians.
    static func radiance(_ direction: Vec3, blur: Double) -> Double {
        ambient(direction, blur: blur) + Studio.key.radiance(direction, blur: blur)
            + Studio.fill.radiance(direction, blur: blur)
    }
}
