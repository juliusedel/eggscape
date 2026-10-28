import EggscapeCore
import Foundation

/// A raindrop hitting a puddle, seen from above: the crown (a ragged ring of water thrown up around the impact) and a
/// spray of droplets flying outwards, smaller and more stretched the further they got.
///
/// Units: the image is 1 wide, centered on the impact.
enum SplashRenderer {
    struct Crown: Sendable {
        var radius: Double
        var width: Double
        let noise: Noise

        /// Signed distance to the ring's band and the position across it (−1 inner edge ... 1 outer edge).
        func band(_ p: Vec2) -> (Double, Double) {
            let length = p.length
            let angle = atan2(p.y, p.x)
            let wander = 1 + 0.12 * noise.value(cos(angle) * 2.2, sin(angle) * 2.2)
            let center = radius * wander
            // The crown is thicker where jets were thrown up.
            let jets = 0.65 + 0.55 * Num.smoothstep(0.1, 0.7, noise.value(cos(angle) * 4 + 9, sin(angle) * 4))
            let half = width * jets
            return (abs(length - center) - half, (length - center) / max(half, 1e-9))
        }
    }

    static func render(diameter: Int, seed: UInt64) -> PixelImage {
        let size = max(diameter, 1)
        var random = SplitMix64(seed: Hash.seed(seed, 0x5A01))
        let crown = Crown(
            radius: random.uniform(0.12 ... 0.15),
            width: random.uniform(0.017 ... 0.023),
            noise: Noise(seed: Hash.seed(seed, 0x5A02))
        )
        var drops: [Droplet] = []
        let count = 16 + random.index(below: 9)
        for _ in 0 ..< count {
            let angle = random.uniform(0 ... 2 * .pi)
            let reach = random.uniform(0 ... 1)
            let distance = 0.19 + 0.26 * reach.squareRoot()
            let radius = (0.026 - 0.016 * reach) * random.uniform(0.6 ... 1.2)
            let direction = Vec2(cos(angle), sin(angle))
            drops.append(Droplet(
                center: direction * distance,
                radius: radius,
                stretch: 1 + 1.6 * reach * random.uniform(0.5 ... 1),
                axis: direction,
                contactAngle: 1.1,
                wobble: (random.uniform(0 ... 0.05), random.uniform(0 ... 6.3), 0, 0)
            ))
        }
        // Fine mist close to the crown.
        for _ in 0 ..< 14 {
            let angle = random.uniform(0 ... 2 * .pi)
            let direction = Vec2(cos(angle), sin(angle))
            drops.append(Droplet(
                center: direction * random.uniform(0.17 ... 0.3),
                radius: random.uniform(0.004 ... 0.007),
                axis: direction,
                contactAngle: 1.1
            ))
        }
        let droplets = drops
        let pixel = 1 / Double(size)
        return Supersampler.render(width: size, height: size, samples: 3) { x, y, filter in
            let p = Vec2(x * pixel - 0.5, 0.5 - y * pixel)
            var color = Premultiplied.clear
            var edge = Double.infinity
            // The disturbed water inside the crown: a shallow crater with a ripple.
            let length = p.length
            if length < crown.radius {
                let ripple = sin(length / crown.radius * 2.6 * .pi)
                color.over(Water.refractionTint, alpha: 0.03 + 0.04 * max(ripple, 0))
                color.over(Water.causticTint, alpha: 0.12 * max(-ripple, 0) * (1 - length / crown.radius))
            }
            let (distance, across) = crown.band(p)
            edge = min(edge, abs(distance) / pixel)
            let coverage = Shape2D.coverage(distance, width: filter * pixel)
            if coverage > 0 {
                // A tube of water: the normal tilts outwards on the outer half and inwards on the inner half.
                let radial = length > 1e-9 ? Vec2(p.x / length, p.y / length) : Vec2(1, 0)
                let s = Num.clamp(abs(across))
                let outward = across >= 0 ? radial : radial * -1
                let tilt = 0.9 * s
                let normal = Vec3(outward.x * tilt, outward.y * tilt, max(1 - tilt * tilt, 1e-4).squareRoot())
                let lit = Studio.towardsKey(outward.x, outward.y, low: -0.85, high: 0.85)
                let ring = Water.layer(
                    normal: normal,
                    rim: s,
                    lit: lit,
                    line: 0.22,
                    crescent: 0.6,
                    caustic: 0.6,
                    outline: 0.2
                )
                color.over(ring * coverage)
            }
            for drop in droplets {
                let reach = drop.radius * drop.stretch + 3 * pixel
                guard abs(p.x - drop.center.x) < reach, abs(p.y - drop.center.y) < reach else { continue }
                color.over(EffectRenderer.shadowTint, alpha: drop.shadow(p))
                let (layer, distance) = drop.layer(p, filter: filter * pixel, pixel: pixel)
                edge = min(edge, abs(distance) / pixel)
                color.over(layer)
            }
            return Sample(color: color, edge: edge)
        }
    }
}
