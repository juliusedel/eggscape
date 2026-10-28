import EggscapeCore
import Foundation

/// A small leaf blowing across the screen, tip up, lit by the studio.
///
/// The seed picks the species outline (beech, birch, willow or linden), the season's color (summer green through
/// yellow and orange to brown, with blotches and edges that turn first), how the blade is folded along the midrib and
/// curled at the margin, and its veins: a midrib, curved secondary veins and a faint network between them. The veins
/// are slightly sunken, so the light picks them out the way it does on a real leaf.
///
/// Units: the leaf is 1 tall (petiole at the bottom, `y` = 0, tip at the top), `x` = 0 in the middle.
enum LeafRenderer {
    struct Species: Sendable {
        /// Half-width of the blade at its widest, and the exponents of `u^a · (1 − u)^b` along the blade.
        var width: Double
        var a: Double
        var b: Double
        /// Number of teeth along each margin and their depth (fraction of the half-width).
        var teeth: Double
        var toothDepth: Double
        /// Secondary veins per side.
        var veins: Double
    }

    static let species: [Species] = [
        Species(width: 0.27, a: 0.6, b: 0.85, teeth: 9, toothDepth: 0.035, veins: 8), // beech
        Species(width: 0.29, a: 0.42, b: 1.0, teeth: 15, toothDepth: 0.07, veins: 7), // birch
        Species(width: 0.16, a: 0.85, b: 0.9, teeth: 24, toothDepth: 0.03, veins: 11), // willow
        Species(width: 0.31, a: 0.32, b: 0.95, teeth: 13, toothDepth: 0.045, veins: 6), // linden
    ]

    /// Summer to late autumn.
    static let palette: [RGB] = [
        RGB(hex: 0x4A7A26), RGB(hex: 0x86A22E), RGB(hex: 0xD6A324),
        RGB(hex: 0xCF6A1D), RGB(hex: 0xA2441B), RGB(hex: 0x7A5531),
    ]

    struct Leaf: Sendable {
        let species: Species
        let base: Double
        let tip: Double
        let bend: Double
        let fold: Double
        let curl: Double
        let color: RGB
        let edgeColor: RGB
        let blotchColor: RGB
        let dryness: Double
        let noise: Noise
        let normalization: Double

        init(seed: UInt64) {
            var random = SplitMix64(seed: Hash.seed(seed, 0x1E_AF))
            species = LeafRenderer.species[random.index(below: LeafRenderer.species.count)]
            base = 0.17
            tip = 0.985
            bend = random.uniform(-0.05 ... 0.05)
            fold = random.uniform(0.03 ... 0.13)
            curl = random.uniform(0.03 ... 0.08)
            let season = random.uniform(0 ... Double(LeafRenderer.palette.count - 1))
            let index = min(Int(season), LeafRenderer.palette.count - 2)
            let main = LeafRenderer.palette[index].mixed(with: LeafRenderer.palette[index + 1], season - Double(index))
            // Real foliage is less saturated than a paint chip; the camera's `Film` adds back a little.
            color = main.saturated(0.82) * 0.9
            // Leaves turn from the margin inwards, and in blotches.
            let later = min(index + 1 + random.index(below: 2), LeafRenderer.palette.count - 1)
            edgeColor = main.mixed(with: LeafRenderer.palette[later], random.uniform(0.3 ... 0.8))
            blotchColor = main.mixed(with: LeafRenderer.palette[max(index - 1, 0)], random.uniform(0.2 ... 0.6))
            dryness = Num.smoothstep(1.5, 4.5, season)
            noise = Noise(seed: Hash.seed(seed, 0x1E_B0))
            let peak = species.a / (species.a + species.b)
            normalization = 1 / (pow(peak, species.a) * pow(1 - peak, species.b))
        }

        /// Position along the blade (0 at its base, 1 at the tip).
        func along(_ y: Double) -> Double {
            (y - base) / (tip - base)
        }

        func midrib(_ u: Double) -> Double {
            bend * sin(.pi * Num.clamp(u))
        }

        /// Half-width of the blade at `u` on one side, with its teeth.
        func halfWidth(_ u: Double, side: Double) -> Double {
            guard u > 0, u < 1 else { return 0 }
            let smooth = species.width * normalization * pow(u, species.a) * pow(1 - u, species.b)
            var phase = u * species.teeth + (side > 0 ? 0.0 : 0.5)
            phase -= phase.rounded(.down)
            // Teeth point towards the tip: a slow rise and a sharp notch.
            let tooth = pow(phase, 1.6) * Num.smoothstep(0.05, 0.25, u) * Num.smoothstep(1, 0.9, u)
            return smooth * (1 - species.toothDepth * 2 * tooth)
        }

        /// Signed distance to the leaf's outline, petiole included.
        func distance(_ p: Vec2) -> Double {
            let u = along(p.y)
            let dx = p.x - midrib(u)
            let side = dx >= 0 ? 1.0 : -1.0
            var blade: Double
            if u <= 0 || u >= 1 {
                let end = u <= 0 ? Vec2(midrib(0), base) : Vec2(midrib(1), tip)
                blade = (p - end).length
            } else {
                let w = halfWidth(u, side: side)
                let step = 0.004
                let slope = (halfWidth(min(u + step, 0.9999), side: side) - w) / (step * (tip - base))
                blade = (abs(dx) - w) / (1 + slope * slope).squareRoot()
            }
            // The petiole: a thin stalk, slightly curved, from the bottom of the image to the blade.
            let stalkY = Num.clamp(p.y, 0.015, base + 0.02)
            let stalkX = -bend * 0.8 * (base - stalkY) / base
            let thickness = 0.011 + 0.004 * Num.smoothstep(0.015, base, stalkY)
            let stalk = (p - Vec2(stalkX, stalkY)).length - thickness
            return min(blade, stalk)
        }

        /// How much of a vein is at `p` (0 ... 1): midrib, secondary veins and the fine network.
        func veins(_ p: Vec2) -> Double {
            let u = along(p.y)
            guard u > -0.05, u < 1.02 else { return 1 }
            let dx = p.x - midrib(u)
            let w = max(halfWidth(Num.clamp(u, 0.001, 0.999), side: dx >= 0 ? 1 : -1), 1e-3)
            let midribWidth = 0.011 * (1 - 0.75 * Num.clamp(u))
            var amount = Num.smoothstep(midribWidth, midribWidth * 0.4, abs(dx))
            // Secondary veins leave the midrib at a steep angle and bend towards the tip near the margin.
            let reach = abs(dx) / w
            let phase = (u - 0.55 * abs(dx) - 0.25 * reach * reach * w) * species.veins + (dx >= 0 ? 0 : 0.5)
            let offset = abs(phase - phase.rounded()) / species.veins * (tip - base)
            let veinWidth = 0.0055 * (1 - 0.6 * reach)
            let secondary = Num.smoothstep(veinWidth, veinWidth * 0.3, offset) * Num.smoothstep(0.98, 0.7, reach)
            amount = max(amount, 0.75 * secondary * Num.smoothstep(0.98, 0.85, u))
            // The network between them.
            let net = abs(noise.value(p.x * 32, p.y * 32))
            amount = max(amount, 0.16 * Num.smoothstep(0.06, 0.015, net))
            return amount
        }

        func height(_ p: Vec2) -> Double {
            let u = Num.clamp(along(p.y))
            let dx = p.x - midrib(u)
            let w = max(halfWidth(Num.clamp(u, 0.001, 0.999), side: dx >= 0 ? 1 : -1), 0.02)
            let reach = Num.clamp(abs(dx) / w, 0, 1.2)
            // Folded up along the midrib, curled down at the margin, arched along the length.
            var z = fold * abs(dx) - curl * reach * reach * reach * w + 0.03 * sin(.pi * u)
            z -= 0.0035 * veins(p)
            z += 0.0008 * noise.fractal(p.x * 14, p.y * 14, octaves: 2)
            return z
        }

        func radiance(_ p: Vec2) -> RGB {
            let step = 0.003
            let h = height(p)
            let normal = Vec3(-(height(p + Vec2(step, 0)) - h) / step, -(height(p + Vec2(0, step)) - h) / step, 1)
                .normalized
            let u = Num.clamp(along(p.y))
            let dx = p.x - midrib(u)
            let w = max(halfWidth(Num.clamp(u, 0.001, 0.999), side: dx >= 0 ? 1 : -1), 0.02)
            let margin = Num.smoothstep(0.55, 1, abs(dx) / w)
            let blotch = Num.smoothstep(0.1, 0.5, noise.fractal(p.x * 6 + 4, p.y * 6, octaves: 3))
            var albedo = color.mixed(with: blotchColor, blotch * 0.8)
            albedo = albedo.mixed(with: edgeColor, margin * 0.85)
            // Veins carry less pigment: paler and a little yellower.
            let vein = veins(p)
            let pale = albedo.power(0.75).mixed(with: RGB(hex: 0xE3D27A), 0.25)
            albedo = albedo.mixed(with: pale, 0.6 * vein)
            albedo = albedo * (1 + 0.04 * noise.fractal(p.x * 24, p.y * 24, octaves: 2))
            // Leaves are translucent: the shadow side gets deeper and more saturated.
            let direct = Num.smoothstep(-0.25, 0.85, normal.dot(Studio.mainDirection))
            var light = albedo.power(1 + 0.3 * (1 - direct)) * (Studio.irradiance(normal) / .pi)
            // The waxy cuticle: glossy on a fresh leaf, dull on a dry one.
            let roughness = Num.mix(0.38, 0.62, dryness)
            let fresnel = Shading.fresnel(0.04, cosine: max(normal.z, 1e-4), roughness: roughness)
            let mirror = Vec3.up.reflected(about: normal)
            light += RGB(gray: fresnel * Studio.radiance(mirror, blur: Studio.blur(roughness: roughness)))
            return light
        }
    }

    static func render(length: Int, seed: UInt64) -> PixelImage {
        let height = max(length, 1)
        let width = max(Int((Double(height) * 0.68).rounded()), 1)
        let leaf = Leaf(seed: seed)
        let pixel = 1 / Double(height)
        let halfWidth = Double(width) * pixel / 2
        return Supersampler.render(width: width, height: height, samples: 3) { x, y, filter in
            let p = Vec2(x * pixel - halfWidth, 1 - y * pixel)
            let distance = leaf.distance(p)
            let coverage = Shape2D.coverage(distance, width: filter * pixel)
            var color = Premultiplied.clear
            if coverage > 0 {
                color.over(Film.develop(leaf.radiance(p)), alpha: coverage)
            }
            return Sample(color: color, edge: abs(distance) / pixel)
        }
    }
}
