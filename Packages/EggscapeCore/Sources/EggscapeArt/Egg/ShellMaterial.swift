import EggscapeCore
import Foundation

/// What one point of the shell is made of, before any lighting.
struct ShellSurface: Sendable {
    /// Diffuse color in linear light.
    var albedo: RGB
    /// Perceptual roughness of the specular layer (0 mirror ... 1 chalk).
    var roughness: Double
    /// Reflectance at normal incidence of a dielectric surface.
    var reflectance: Double
    /// Colored reflectance of a metal; `nil` for shells, dyes and paints.
    var metal: RGB?
    /// Strength of a clear lacquer on top (glossy finish).
    var coat: Double
    /// How much deeper and more saturated the shadow side gets: light that reaches it has travelled further through
    /// the pigmented shell.
    var subsurface: Double
    /// Perturbation added to the normal before normalizing (pores, crinkled leaf).
    var bump: Vec3
    /// Thin-film shimmer of mother-of-pearl, 0 ... 1.
    var iridescence: Double
    /// Phase of the shimmer, so it is not uniform.
    var filmPhase: Double
    /// Pits and pores catch less highlight.
    var specularOcclusion: Double
}

/// Turns an `EggAppearance` into a `ShellSurface` at every point of the shell.
///
/// Everything is evaluated on the 3D surface, so patterns follow the curvature: they foreshorten towards the outline
/// and bands wrap around the egg. Pattern space is the egg tilted by a few degrees about the screen's x axis, as if
/// the pointy end lay a little higher; that is how an egg rests on a table, and it makes bands show their curvature
/// instead of projecting to straight lines.
struct ShellMaterial: Sendable {
    let appearance: EggAppearance
    let shape: EggShape
    private let base: RGB
    private let mottle: Noise
    private let grain: Noise
    private let pores: UInt64
    private let warp: Noise
    private let patternNoise: Noise
    private let patternSeed: UInt64

    /// Tilt of the pattern frame in radians.
    static let patternTilt = 8.0 * Double.pi / 180

    init(appearance: EggAppearance, shape: EggShape) {
        self.appearance = appearance
        self.shape = shape
        base = RGB(appearance.base).clamped(0.0005, 1)
        mottle = Noise(seed: Hash.seed(appearance.seed, 1))
        grain = Noise(seed: Hash.seed(appearance.seed, 2))
        pores = Hash.seed(appearance.seed, 3)
        warp = Noise(seed: Hash.seed(appearance.seed, 4))
        patternNoise = Noise(seed: Hash.seed(appearance.seed, 5))
        patternSeed = Hash.seed(appearance.seed, 6)
    }

    /// The material at `position` (egg units) with geometric normal `normal`; `footprint` is the size of one pixel on
    /// the surface, used to anti-alias painted edges and to fade texture finer than a pixel.
    func surface(at position: Vec3, normal: Vec3, footprint: Double) -> ShellSurface {
        let finish = appearance.finish
        var surface = ShellSurface(
            albedo: base,
            roughness: Self.roughness(finish),
            reflectance: Self.reflectance(finish),
            metal: nil,
            coat: finish == .glossy ? 1 : 0,
            subsurface: finish == .metallic ? 0 : (finish == .matte ? 0.3 : 0.25),
            bump: .zero,
            iridescence: finish == .pearl ? 1 : 0,
            filmPhase: 0,
            specularOcclusion: 1
        )

        // Natural irregularity: the shell's pigment (or a dye) is never perfectly even. A concentration change is an
        // exponent on the color, so dark eggs vary more than white ones, as real shells do. Polished metal has none
        // of it: its color is the metal's, and any blotch in it would read as tarnish.
        let large = mottle.fractal(position * 3.2, octaves: 3)
        if finish != .metallic {
            // Fine mottling: the dense, sandy pattern of slightly darker pigment that covers a real shell. Nacre is
            // laid down in smooth layers and hides most of it; pores under it would read as dust.
            let smooth = finish == .pearl ? 0.35 : 1
            let fine = grain.fractal(position * 95, octaves: 3, footprint: footprint * 95) * smooth
            let sand = grain.fractal(position * 210 + Vec3(7, 3, 11), octaves: 2, footprint: footprint * 210) * smooth
            let mottles = Num.smoothstep(0.04, 0.34, fine + 0.35 * sand)
            let pore = poreDepth(position, footprint: footprint) * smooth * smooth
            let concentration = 1 + 0.12 * large + 0.06 * fine + 0.22 * mottles + 0.1 * pore
            // Mottles and pores mostly darken; pigmented shells show them more than white ones.
            let pigmentation = 0.04 + 0.13 * (1 - base.luminance)
            let shade = 1 + 0.04 * fine + 0.03 * sand - pigmentation * mottles - 0.2 * pore
            surface.albedo = base.power(concentration) * shade
            surface.specularOcclusion = 1 - 0.4 * pore - 0.15 * mottles
            let bumpScale = footprint < 0.006 ? 0.035 : 0.035 * 0.006 / footprint
            surface.bump = Vec3(grain.value(position * 95), grain.value(position * 95 + Vec3(31, 7, 3)), 0) * bumpScale
        }

        let pattern = position.rotatedAboutX(-Self.patternTilt)
        applyPattern(&surface, at: pattern, normal: normal.rotatedAboutX(-Self.patternTilt), footprint: footprint)

        switch finish {
        case .pearl:
            // Nacre: a pale, slightly milky body under the film, whose thickness drifts slowly across the shell.
            surface.albedo = surface.albedo.mixed(with: RGB(gray: 0.76), 0.4)
            surface.filmPhase = 0.08 * mottle.value(position * 2.2) + 0.04 * large
        case .metallic:
            applyMetal(&surface, at: position, footprint: footprint)
        default:
            break
        }
        return surface
    }

    /// Polished gold or silver: the color becomes the reflectance. Real leaf is never perfectly flat, so a very faint
    /// crinkle tilts the normal by a degree or so; it shows as a fine ripple in the reflections, never as blotches,
    /// and fades out where a pixel would only average it into noise.
    private func applyMetal(_ surface: inout ShellSurface, at position: Vec3, footprint: Double) {
        surface.metal = metallicReflectance(surface.albedo)
        let frequency = 55.0
        let fade = Num.smoothstep(1.2, 0.4, footprint * frequency)
        let crinkle = warp.fractal(position * frequency, octaves: 2, footprint: footprint * frequency)
        surface.roughness = 0.22 + 0.012 * crinkle
        surface.bump = Vec3(
            warp.value(position * frequency),
            warp.value(position * frequency + Vec3(5, 11, 17)),
            0
        ) * (0.0045 * fade)
    }

    static func roughness(_ finish: EggAppearance.Finish) -> Double {
        switch finish {
        case .matte: 0.6
        case .satin: 0.36
        case .glossy: 0.4
        case .pearl: 0.3
        case .metallic: 0.24
        }
    }

    /// Specular reflectance at normal incidence. A natural shell's cuticle has a chalky bloom that reflects white
    /// light diffusely, measured on the reference as about twice the reflectance of a smooth dielectric.
    static func reflectance(_ finish: EggAppearance.Finish) -> Double {
        switch finish {
        case .matte: 0.1
        case .satin: 0.05
        case .glossy: 0.04
        case .pearl: 0.06
        case .metallic: 0.04
        }
    }

    /// Metals reflect their own color; a gentle lift keeps dark "metal" colors from turning black.
    private func metallicReflectance(_ color: RGB) -> RGB {
        RGB(0.04, 0.04, 0.04) + color * 0.96
    }

    /// Tiny pits of the shell surface, 0 (none) ... 1 (deep). They hold a little more pigment and catch less
    /// highlight, which gives the fine stippled look of the reference photo.
    private func poreDepth(_ position: Vec3, footprint: Double) -> Double {
        let cell = 1.0 / 115
        guard footprint < cell * 1.5 else { return 0 }
        let fade = Num.smoothstep(cell * 1.5, cell * 0.6, footprint)
        let p = position / cell
        let fx = p.x.rounded(.down), fy = p.y.rounded(.down), fz = p.z.rounded(.down)
        var depth = 0.0
        for k in -1 ... 1 {
            for j in -1 ... 1 {
                for i in -1 ... 1 {
                    let cx = Int(fx) + i, cy = Int(fy) + j, cz = Int(fz) + k
                    let hash = Hash.of(cx, cy, cz, seed: pores)
                    guard Hash.unit(hash) < 0.55 else { continue }
                    let feature = Vec3(
                        Double(cx) + Hash.unit(hash, 1),
                        Double(cy) + Hash.unit(hash, 2),
                        Double(cz) + Hash.unit(hash, 3)
                    )
                    let radius = 0.22 + 0.2 * Hash.unit(hash, 4)
                    let distance = (p - feature).length
                    if distance < radius {
                        let strength = 0.4 + 0.6 * Hash.unit(hash, 5)
                        depth = max(depth, strength * (1 - Num.smoothstep(radius * 0.35, radius, distance)))
                    }
                }
            }
        }
        return depth * fade
    }

    // MARK: Patterns

    private func applyPattern(_ surface: inout ShellSurface, at p: Vec3, normal: Vec3, footprint: Double) {
        switch appearance.pattern {
        case .plain:
            break
        case let .speckles(color, density, size):
            let amount = speckles(
                p,
                normal: normal,
                density: Num.clamp(density),
                size: Num.clamp(size),
                footprint: footprint
            )
            // Speckles are a denser deposit of pigment in the shell: deep and saturated, with a little grain left.
            // The more pigment, the deeper the color, as in any translucent dye.
            let pigment = RGB(color).saturated(1.3).clamped(0.0005, 1)
            let texture = 0.8 + 0.2 * surface.albedo.luminance / max(base.luminance, 0.05)
            let speckled = pigment.power(1.2 + 0.5 * amount) * texture
            surface.albedo = surface.albedo.mixed(with: speckled, amount)
            surface.specularOcclusion *= 1 - 0.35 * amount
        case let .dots(color, size):
            let coverage = dots(p, size: Num.clamp(size), footprint: footprint)
            paint(&surface, RGB(color), coverage)
        case let .stripes(colors):
            guard !colors.isEmpty else { return }
            let (index, coverage) = stripes(p, footprint: footprint)
            paint(&surface, RGB(colors[index % colors.count]), coverage)
        case let .zigzag(color):
            paint(&surface, RGB(color), zigzag(p, footprint: footprint))
        case let .marble(color):
            let veins = marble(p, footprint: footprint)
            let vein = RGB(color)
            surface.albedo = surface.albedo.mixed(with: vein, veins)
        case let .dipDye(color):
            let (coverage, tide) = dipDye(p, footprint: footprint)
            let dye = RGB(color).power(1 + 0.35 * tide)
            surface.albedo = surface.albedo.mixed(
                with: dye * (surface.albedo.luminance / max(base.luminance, 0.05)),
                coverage
            )
        case let .confetti(colors):
            guard !colors.isEmpty else { return }
            let (index, coverage) = confetti(p, normal: normal, footprint: footprint)
            paint(&surface, RGB(colors[index % colors.count]), coverage)
        case let .stars(color):
            paint(&surface, RGB(color), stars(p, normal: normal, footprint: footprint))
        }
    }

    /// Opaque paint over the shell: its own color with a little of the shell texture showing through, and a satin
    /// sheen of its own (unless the whole egg is lacquered or metallic anyway).
    private func paint(_ surface: inout ShellSurface, _ color: RGB, _ coverage: Double) {
        guard coverage > 0 else { return }
        let texture = surface.albedo.luminance / max(base.luminance, 0.02)
        let painted = color * (0.85 + 0.15 * texture)
        surface.albedo = surface.albedo.mixed(with: painted, coverage)
        if appearance.finish == .matte {
            surface.roughness = Num.mix(surface.roughness, 0.4, coverage)
        }
        surface.specularOcclusion = Num.mix(surface.specularOcclusion, 1, coverage * 0.7)
    }

    /// Coverage of an edge at signed distance `distance` (positive inside), anti-aliased over one pixel.
    private func edge(_ distance: Double, _ footprint: Double) -> Double {
        Num.smoothstep(-footprint, footprint, distance)
    }

    /// Axis parameter in pattern space: −1 at the round end, +1 at the pointy end.
    private func axis(_ p: Vec3) -> Double {
        p.y / shape.halfHeight
    }

    /// Natural speckles, layered like on a real brown shell: many tiny flecks, fewer small speckles, a few larger
    /// spots that lie deeper in the shell (soft-edged and paler), crisp coarse dots for large settings and, for dense
    /// large settings, quail-like blotches. Every layer is a little denser on the lower left flank.
    private func speckles(_ p: Vec3, normal: Vec3, density: Double, size: Double, footprint: Double) -> Double {
        // Real brown eggs carry more speckles on one flank; the reference photo has them towards the lower left.
        let lean = -0.55 * p.x - 0.45 * p.y / shape.halfHeight
        let flank = Num.clamp(0.45 + 0.55 * lean + 0.35 * patternNoise.value(p * 2.5))
        let bias = Num.mix(flank, 1, density * density)
        // The fine flecks follow the flank only gently, so the whole egg stays speckled.
        let gentleBias = Num.mix(0.65, 1.2, flank)
        let shift = Vec3(warp.value(p * 30), warp.value(p * 30 + Vec3(9, 3, 1)), warp.value(p * 30 + Vec3(2, 8, 5)))
        let warped = p + shift * 0.006
        // A finer warp frays the outlines of the small marks, so no fleck is a perfect ellipse.
        let frayed = warped + Vec3(
            grain.value(p * 160 + Vec3(3, 1, 4)),
            grain.value(p * 160 + Vec3(1, 5, 9)),
            grain.value(p * 160 + Vec3(2, 6, 5))
        ) * 0.0012
        var amount = 0.0
        // Tiny flecks: most of the speckling, about 250 on the visible side; many are smaller than a pixel at game
        // size and only tint it.
        amount = max(amount, spots(frayed, normal: normal, SpotLayer(
            cell: 0.06,
            probability: Num.mix(0.5, 0.9, density) * gentleBias,
            radius: (0.0012, Num.mix(0.0038, 0.0055, size)),
            skew: 2.2,
            elongation: 2.2,
            softness: 0.35,
            darkness: (0.35, 1),
            seed: patternSeed ^ 0xF1EC
        ), footprint: footprint))
        // Small speckles, a few dozen.
        amount = max(amount, spots(frayed, normal: normal, SpotLayer(
            cell: 0.12,
            probability: Num.mix(0.35, 0.8, density) * bias,
            radius: (0.003, Num.mix(0.008, 0.013, size)),
            skew: 1.8,
            elongation: 1.8,
            softness: 0.3,
            darkness: (0.6, 1),
            seed: patternSeed ^ 0x5151
        ), footprint: footprint))
        // A few larger spots deposited deeper in the shell: blurred by the shell above them, and paler.
        amount = max(amount, spots(warped, normal: normal, SpotLayer(
            cell: 0.3,
            probability: Num.mix(0.45, 0.8, density) * bias,
            radius: (Num.mix(0.008, 0.02, size), Num.mix(0.016, 0.04, size)),
            skew: 1.5,
            elongation: 1.5,
            softness: 0.9,
            darkness: (0.22, 0.5),
            seed: patternSeed ^ 0x50F7
        ), footprint: footprint))
        // Crisp coarse dots for large settings.
        let coarse = Num.smoothstep(0.3, 0.6, size)
        if coarse > 0 {
            let cell = Num.mix(0.075, 0.16, size)
            amount = max(amount, spots(warped, normal: normal, SpotLayer(
                cell: cell,
                probability: Num.mix(0.12, 0.55, density) * bias * coarse,
                radius: (Num.mix(0.05, 0.26, size) * cell, Num.mix(0.16, 0.42, size) * cell),
                skew: 2,
                elongation: 1.3,
                softness: 0.28,
                darkness: (0.6, 1),
                seed: patternSeed
            ), footprint: footprint))
        }
        // Blotches for quail-like settings.
        if size > 0.45, density > 0.35 {
            let strength = Num.smoothstep(0.45, 0.8, size) * Num.smoothstep(0.35, 0.7, density)
            let frequency = Num.mix(9, 4.5, size)
            let field = patternNoise.fractal(warped * frequency, octaves: 4, footprint: footprint * frequency)
            let threshold = Num.mix(0.32, 0.02, density)
            let blotch = Num.smoothstep(threshold, threshold + 0.06, field)
            amount = max(amount, blotch * strength * (0.75 + 0.25 * grain.value(p * 18)))
        }
        return Num.clamp(amount)
    }

    /// One layer of scattered marks for `spots(_:normal:_:footprint:)`. Lengths are in egg units.
    private struct SpotLayer {
        /// Each cell of a 3D grid holds at most one mark, so a layer has about `probability / cell²` marks per unit
        /// of shell area.
        var cell: Double
        var probability: Double
        /// Radius range; `skew` above 1 makes small marks more common than large ones.
        var radius: (Double, Double)
        var skew: Double
        /// Largest ratio of length to width.
        var elongation: Double
        /// Width of the soft edge as a fraction of the radius.
        var softness: Double
        /// Range of pigment density.
        var darkness: (Double, Double)
        var seed: UInt64
    }

    /// Marks at random points of a 3D cell grid, projected onto the shell along its normal: every mark within half a
    /// cell of the surface shows at full size, so the density per area is exact, and each mark is stretched along a
    /// random direction, so they foreshorten towards the outline and no two look alike.
    ///
    /// Anti-aliasing keeps the amount of pigment: a mark smaller than a pixel spreads over the pixel with
    /// proportionally less strength, instead of flickering or growing to a full pixel, so a 64-pixel shop icon shows
    /// the same overall speckling as a large preview.
    private func spots(_ p: Vec3, normal: Vec3, _ layer: SpotLayer, footprint: Double) -> Double {
        let q = p / layer.cell
        let fx = q.x.rounded(.down), fy = q.y.rounded(.down), fz = q.z.rounded(.down)
        let pixel = 0.6 * footprint
        let reach = layer.radius.1 * layer.elongation * (1 + layer.softness) + pixel
        let slab = 0.5 * layer.cell
        var amount = 0.0
        for k in -1 ... 1 {
            for j in -1 ... 1 {
                for i in -1 ... 1 {
                    let cx = Int(fx) + i, cy = Int(fy) + j, cz = Int(fz) + k
                    let hash = Hash.of(cx, cy, cz, seed: layer.seed)
                    guard Hash.unit(hash) < layer.probability else { continue }
                    let feature = Vec3(
                        Double(cx) + Hash.unit(hash, 1),
                        Double(cy) + Hash.unit(hash, 2),
                        Double(cz) + Hash.unit(hash, 3)
                    ) * layer.cell
                    let offset = p - feature
                    let depth = offset.dot(normal)
                    guard abs(depth) < slab else { continue }
                    let tangent = offset - normal * depth
                    let squared = tangent.dot(tangent)
                    guard squared < reach * reach else { continue }
                    let radius = layer.radius.0 + (layer.radius.1 - layer.radius.0)
                        * pow(Hash.unit(hash, 4), layer.skew)
                    // Stretch along a random axis by shrinking the offset's component along it.
                    let cosine = 2 * Hash.unit(hash, 6) - 1
                    let angle = 2 * Double.pi * Hash.unit(hash, 7)
                    let sine = (1 - cosine * cosine).squareRoot()
                    let axis = Vec3(sine * cos(angle), sine * sin(angle), cosine)
                    let stretch = 1 + (layer.elongation - 1) * Hash.unit(hash, 8)
                    let along = tangent.dot(axis)
                    let distance = max(squared - along * along * (1 - 1 / (stretch * stretch)), 0).squareRoot()
                    // A mark convolved with the pixel: wider and proportionally fainter when it is tiny.
                    let spread = (radius * radius + pixel * pixel).squareRoot()
                    let soft = max(radius * layer.softness, pixel)
                    guard distance < spread + soft else { continue }
                    let darkness = layer.darkness.0 + (layer.darkness.1 - layer.darkness.0) * Hash.unit(hash, 5)
                    let strength = darkness * radius * radius / (spread * spread)
                    amount = max(amount, strength * Num.smoothstep(spread + soft, spread - soft, distance))
                }
            }
        }
        return amount
    }

    /// Polka dots in staggered rings around the axis, evenly spaced along each ring.
    private func dots(_ p: Vec3, size: Double, footprint: Double) -> Double {
        let radius = Num.mix(0.035, 0.085, size)
        let spacing = radius * 3.1
        let rowSpacing = spacing * 0.866
        let row = (p.y / rowSpacing).rounded()
        var coverage = 0.0
        for offset in -1 ... 1 {
            let k = row + Double(offset)
            let y = k * rowSpacing
            let ringRadius = shape.radius(y / shape.halfHeight)
            guard ringRadius > radius * 0.5 else { continue }
            let count = max(1, (2 * .pi * ringRadius / spacing).rounded())
            let step = 2 * Double.pi / count
            let shift = Int(k).isMultiple(of: 2) ? 0 : 0.5
            let angle = atan2(p.x, p.z)
            let j = (angle / step - shift).rounded()
            let centerAngle = (j + shift) * step
            let center = Vec3(ringRadius * sin(centerAngle), y, ringRadius * cos(centerAngle))
            let distance = (p - center).length
            coverage = max(coverage, edge(radius - distance, footprint))
        }
        return coverage
    }

    /// Bands at constant height along the axis, alternating base color and pattern colors; returns which pattern
    /// color applies and its coverage.
    private func stripes(_ p: Vec3, footprint: Double) -> (Int, Double) {
        let bands = 9.0
        let wobble = 0.006 * patternNoise.value(p * 6)
        let position = (axis(p) + 1) / 2 * bands + wobble * bands
        let index = position.rounded(.down)
        let fraction = position - index
        guard Int(index) % 2 == 1 else { return (0, 0) }
        let width = shape.halfHeight * 2 / bands
        let distance = min(fraction, 1 - fraction) * width
        // Count the colored bands from the pointy end, as the appearance documents.
        let fromTop = Int((bands - 1 - index) / 2)
        return (max(fromTop, 0), edge(distance, footprint))
    }

    /// A zigzag band around the middle, framed by two thin lines.
    private func zigzag(_ p: Vec3, footprint: Double) -> Double {
        let ringRadius = shape.radius(0)
        let arc = atan2(p.x, p.z) * ringRadius
        let teeth = 12.0
        let period = 2 * Double.pi * ringRadius / teeth
        let amplitude = 0.075
        let center = -0.02
        // Distance to a triangle wave: fold into one rising segment.
        var local = arc / period
        local -= local.rounded(.down)
        let x = (local < 0.5 ? local : 1 - local) * period
        let rise = 2 * amplitude / (period / 2)
        let lineY = center - amplitude + rise * x
        let distance = abs(p.y - lineY) / (1 + rise * rise).squareRoot()
        var coverage = edge(0.022 - distance, footprint)
        for side in [-1.0, 1.0] {
            let lineDistance = abs(p.y - (center + side * (amplitude + 0.07)))
            coverage = max(coverage, edge(0.009 - lineDistance, footprint))
        }
        return coverage
    }

    /// Marble veins: thin, sharp lines along a turbulent field, with softer secondary veins and clouding.
    private func marble(_ p: Vec3, footprint: Double) -> Double {
        let turbulence = patternNoise.fractal(p * 2.6, octaves: 5, footprint: footprint * 2.6)
        let phase = (p.x * 1.1 + p.y * 0.7 + p.z * 0.4) * 9 + turbulence * 7.5
        let primary = pow(1 - abs(sin(phase)), 10)
        let secondaryField = warp.fractal(p * 4.2 + Vec3(3, 1, 7), octaves: 4, footprint: footprint * 4.2)
        let secondary = pow(1 - abs(sin(p.y * 6 - p.x * 4 + secondaryField * 9)), 18) * 0.55
        let cloud = 0.18 * Num.smoothstep(0.1, 0.6, warp.fractal(p * 1.6, octaves: 3))
        return Num.clamp(0.9 * primary + secondary + cloud)
    }

    /// Dip dye on the round half: a slightly wavy liquid line with a darker tide mark; returns coverage and how much
    /// extra dye collected at the line.
    private func dipDye(_ p: Vec3, footprint: Double) -> (Double, Double) {
        let line = -0.06 * shape.halfHeight + 0.012 * patternNoise.value(atan2(p.x, p.z) * 1.7, 0.5)
        let distance = line - p.y
        let soft = max(0.008, footprint)
        let coverage = Num.smoothstep(-soft, soft, distance) * (0.9 + 0.1 * Num.smoothstep(0, 0.25, distance))
        let tide = Num.smoothstep(0.035, 0, abs(distance - 0.012))
        return (coverage, tide)
    }

    /// Small flecks in a 3D cell grid, each a rounded rectangle at a random angle in the shell's tangent plane.
    private func confetti(_ p: Vec3, normal: Vec3, footprint: Double) -> (Int, Double) {
        decals(p, normal: normal, cell: 0.07, probability: 0.85, seed: patternSeed ^ 0xC0FE) { local, hash in
            let half = Vec2(0.012 + 0.006 * Hash.unit(hash, 7), 0.0055 + 0.002 * Hash.unit(hash, 8))
            let q = Vec2(abs(local.x) - half.x + 0.003, abs(local.y) - half.y + 0.003)
            let outside = Vec2(max(q.x, 0), max(q.y, 0)).length + min(max(q.x, q.y), 0) - 0.003
            return edge(-outside, footprint)
        }
    }

    /// Five-pointed stars plus tiny dots, like a night sky.
    private func stars(_ p: Vec3, normal: Vec3, footprint: Double) -> Double {
        let big = decals(p, normal: normal, cell: 0.13, probability: 0.7, seed: patternSeed ^ 0x57A2) { local, hash in
            let radius = 0.02 + 0.022 * Hash.unit(hash, 7)
            return edge(-Self.starDistance(local, radius: radius), footprint)
        }.1
        let small = decals(
            p,
            normal: normal,
            cell: 0.055,
            probability: 0.45,
            seed: patternSeed ^ 0x0D07
        ) { local, hash in
            let radius = 0.0035 + 0.004 * Hash.unit(hash, 7)
            return edge(radius - local.length, footprint)
        }.1
        return max(big, small)
    }

    /// Signed distance to a regular five-pointed star (Inigo Quilez's formulation), negative inside.
    private static func starDistance(_ point: Vec2, radius: Double) -> Double {
        let k1 = Vec2(0.809_016_994_375, -0.587_785_252_292)
        let k2 = Vec2(-k1.x, k1.y)
        var p = Vec2(abs(point.x), point.y)
        p = p - k1 * (2 * max(k1.dot(p), 0))
        p = p - k2 * (2 * max(k2.dot(p), 0))
        p = Vec2(abs(p.x), p.y - radius)
        // From the tip to the inner vertex, which lies at `ratio · radius`, 36° from the tip: `(-k1.y, k1.x)`.
        let ratio = 0.42
        let ba = Vec2(-k1.y, k1.x) * ratio - Vec2(0, 1)
        let h = Num.clamp(p.dot(ba) / ba.dot(ba), 0, radius)
        let d = p - ba * h
        return d.length * (p.y * ba.x - p.x * ba.y < 0 ? -1 : 1)
    }

    /// Evaluates small decals placed at random points of a 3D cell grid, snapped onto the shell.
    ///
    /// Only features lying within half a cell of the surface are used, which keeps the snapping short, so every decal
    /// that can touch `p` comes from one of the 27 neighbouring cells. `coverage` gets the point in the decal's own
    /// 2D frame (randomly rotated in the tangent plane) and the cell hash.
    private func decals(
        _ p: Vec3,
        normal: Vec3,
        cell: Double,
        probability: Double,
        seed: UInt64,
        coverage: (Vec2, UInt64) -> Double
    ) -> (Int, Double) {
        let tangent = Vec3(0, 1, 0).cross(normal).normalized
        let bitangent = normal.cross(tangent)
        let q = p / cell
        let fx = q.x.rounded(.down), fy = q.y.rounded(.down), fz = q.z.rounded(.down)
        var best = (0, 0.0)
        for k in -1 ... 1 {
            for j in -1 ... 1 {
                for i in -1 ... 1 {
                    let cx = Int(fx) + i, cy = Int(fy) + j, cz = Int(fz) + k
                    let hash = Hash.of(cx, cy, cz, seed: seed)
                    guard Hash.unit(hash) < probability else { continue }
                    let feature = Vec3(
                        Double(cx) + Hash.unit(hash, 1),
                        Double(cy) + Hash.unit(hash, 2),
                        Double(cz) + Hash.unit(hash, 3)
                    ) * cell
                    // Snap radially onto the surface of revolution.
                    let ringRadius = shape.radius(feature.y / shape.halfHeight)
                    let radial = (feature.x * feature.x + feature.z * feature.z).squareRoot()
                    guard ringRadius > 0, radial > 1e-9, abs(radial - ringRadius) < cell * 0.5 else { continue }
                    let onSurface = Vec3(feature.x / radial * ringRadius, feature.y, feature.z / radial * ringRadius)
                    let offset = p - onSurface
                    guard offset.length < cell else { continue }
                    let angle = Hash.unit(hash, 6) * 2 * Double.pi
                    let local = Vec2(offset.dot(tangent), offset.dot(bitangent)).rotated(angle)
                    let value = coverage(local, hash)
                    if value > best.1 {
                        best = (Int(truncatingIfNeeded: hash >> 40), value)
                    }
                }
            }
        }
        return best
    }
}
