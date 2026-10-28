import EggscapeCore
import Foundation

/// Weather effects: transparent images lit by `Studio`, so they sit naturally on the spoon, the white studio surface
/// and the camera image. Every random choice comes from the seed.
enum EffectRenderer {
    /// Edge pixels are supersampled on an `n × n` grid.
    static let edgeSamples = 3
    /// Shadows on a lit surface are slightly cool: they are lit only by the room.
    static let shadowTint = RGB(0.015, 0.02, 0.03)

    /// A water drop lying on a surface; units: the image is 1 wide, centered.
    static func raindrop(diameter: Int, seed: UInt64) -> PixelImage {
        let size = max(diameter, 1)
        var random = SplitMix64(seed: Hash.seed(seed, 0xD0_01))
        let axis = random.uniform(0 ... .pi)
        // Shifted towards the light so the shadow on the far side fits into the image.
        let drop = Droplet(
            center: Studio.keySide * 0.05,
            radius: 0.37,
            stretch: random.uniform(1.0 ... 1.1),
            axis: Vec2(cos(axis), sin(axis)),
            contactAngle: random.uniform(0.85 ... 1.15),
            wobble: (
                random.uniform(0 ... 0.035),
                random.uniform(0 ... 2 * .pi),
                random.uniform(0 ... 0.02),
                random.uniform(0 ... 2 * .pi)
            )
        )
        let pixel = 1 / Double(size)
        return Supersampler.render(width: size, height: size, samples: edgeSamples) { x, y, filter in
            let p = Vec2(x * pixel - 0.5, 0.5 - y * pixel)
            var color = Premultiplied.clear
            color.over(shadowTint, alpha: drop.shadow(p))
            let (layer, distance) = drop.layer(p, filter: filter * pixel, pixel: pixel)
            color.over(layer)
            return Sample(color: color, edge: abs(distance) / pixel)
        }
    }

    /// A falling rain streak: a thin thread of water, motion-blurred, `length` pixels tall.
    ///
    /// Like a drop, the thread shows the room through its sides (two faint dark edges, visible on white) and focuses
    /// light into a slightly brighter core (visible on a darker ground). The tail fades in from the top; the head,
    /// the drop itself, is a little fuller at the bottom. Alpha is zero away from the water.
    static func streak(length: Int) -> PixelImage {
        let height = max(length, 1)
        let thickness = max(Double(height) * 0.013, 1.4)
        let width = max(Int((thickness * 2.6).rounded(.up)) + 2, 4)
        let center = Double(width) / 2
        return Raster.render(width: width, height: height) { column, row in
            let t = (Double(row) + 0.5) / Double(height)
            let taper = 0.55 + 0.45 * Num.smoothstep(0, 0.9, t)
            let half = thickness / 2 * taper
            let x = abs(Double(column) + 0.5 - center) / max(half, 0.5)
            let along = Num.smoothstep(0, 0.5, t) * Num.smoothstep(1, 0.93, t)
            let head = Num.smoothstep(0.7, 0.95, t)
            let core = exp(-x * x * 1.8)
            let side = (x - 0.95) / 0.45
            var color = Premultiplied.clear
            color.over(Water.refractionTint, alpha: 0.26 * exp(-side * side) * along)
            color.over(RGB(0.9, 0.94, 1), alpha: (0.42 + 0.2 * head) * core * along)
            return color.pixel(x: column, y: row)
        }
    }

    static func leaf(length: Int, seed: UInt64) -> PixelImage {
        LeafRenderer.render(length: length, seed: seed)
    }

    static func splash(diameter: Int, seed: UInt64) -> PixelImage {
        SplashRenderer.render(diameter: diameter, seed: seed)
    }
}
