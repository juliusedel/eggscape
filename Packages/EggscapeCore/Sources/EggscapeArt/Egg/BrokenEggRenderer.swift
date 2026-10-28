import EggscapeCore
import Foundation

/// An egg that fell off the spoon and smashed on the ground, seen from directly above.
///
/// Built like the real thing, back to front: the egg white spreads into an irregular puddle (a thin, watery outer part
/// with a rounded meniscus at its edge and a firmer mound around the yolk), the yolk sits in it as a glossy dome, and
/// three to six shell fragments lie around it, some skin up, some showing the white membrane inside, each with a small
/// contact shadow. The fragments use the egg's own `ShellMaterial`, mapped back to the place on the intact egg they
/// broke out of, so a gold or dotted egg breaks into gold or dotted pieces, and everything is lit by `Studio`.
///
/// Units: the image is 1 wide and `aspect` tall, centered on the origin, `y` up the screen.
enum BrokenEggRenderer {
    static let aspect = 0.8
    /// Edge pixels are supersampled on an `n × n` grid.
    static let edgeSamples = 3

    static func render(_ appearance: EggAppearance, width: Int) -> PixelImage {
        let width = max(width, 1)
        let height = max(Int((Double(width) * aspect).rounded()), 1)
        let scene = BrokenEgg(appearance: appearance)
        let pixel = 1 / Double(width)
        let top = Double(height) * pixel / 2
        return Supersampler.render(width: width, height: height, samples: edgeSamples) { x, y, filter in
            scene.shade(Vec2(x * pixel - 0.5, top - y * pixel), pixel: pixel, filter: filter * pixel)
        }
    }
}

/// The layout and materials of one smashed egg; a pure function of the appearance's seed.
struct BrokenEgg: Sendable {
    struct Blob: Sendable {
        var center: Vec2
        var radius: Double
    }

    /// The yolk: a slightly oval, slightly irregular dome.
    struct Yolk: Sendable {
        var center: Vec2
        var radii: Vec2
        var angle: Double
        var height: Double
        var wobble: (Double, Double, Double, Double)

        /// Elliptical radius (1 on the outline) and its gradient.
        func radial(_ p: Vec2) -> (Double, Vec2) {
            let d = (p - center).rotated(-angle)
            let polar = atan2(d.y, d.x)
            let bump = 1 + wobble.0 * cos(2 * polar + wobble.1) + wobble.2 * cos(3 * polar + wobble.3)
            let e = Vec2(d.x / radii.x, d.y / radii.y)
            let s = e.length / bump
            let gradient = Vec2(d.x / (radii.x * radii.x), d.y / (radii.y * radii.y)) * (1 / max(e.length * bump, 1e-9))
            return (s, gradient.rotated(angle))
        }

        func distance(_ p: Vec2) -> Double {
            let (s, gradient) = radial(p)
            return (s - 1) / max(gradient.length, 1e-9)
        }

        /// Surface normal of the dome: a sagging sphere, flatter on top and steep at the base.
        func normal(_ p: Vec2) -> Vec3 {
            let (s, gradient) = radial(p)
            let s2 = min(s * s, 0.995)
            // z = h · (1 − s²)^0.62, so dz/ds = −1.24 h s (1 − s²)^−0.38.
            let slope = 1.24 * height * s * pow(1 - s2, -0.38)
            return Vec3(gradient.x * slope, gradient.y * slope, 1).normalized
        }
    }

    /// One piece of shell lying on the ground.
    struct Piece: Sendable {
        var center: Vec2
        var angle: Double
        /// Outline in the piece's own frame (unrotated, relative to `center`).
        var outline: [Vec2]
        var bound: Double
        /// Concave side up: shows the white membrane inside.
        var insideUp: Bool
        /// Where the curved piece is highest (convex) or lowest (concave), in the piece's frame.
        var apex: Vec2
        /// Where on the intact egg it came from: axis parameter and angle around the axis.
        var originT: Double
        var originPhi: Double
        /// How high the piece stands off the ground, for its shadow.
        var lift: Double
        /// A piece rarely lies flat: it rests on an edge or on a crumb, which tilts its whole surface.
        var lean: Vec2

        func local(_ p: Vec2) -> Vec2 {
            (p - center).rotated(-angle)
        }
    }

    let appearance: EggAppearance
    let shape: EggShape
    let material: ShellMaterial
    let puddle: [Blob]
    let drops: [Blob]
    let mound: [Blob]
    let yolk: Yolk
    let pieces: [Piece]
    let warp: Noise
    let ripple: Noise
    let fibers: Noise

    /// The intact egg was this wide in image units; fragments keep its scale and curvature.
    static let eggScale = 0.62
    /// Radius of curvature of the shell (half the egg's width).
    static let shellRadius = 0.5 * eggScale
    /// Thickness of the shell, seen as a white line along a broken edge.
    static let shellThickness = 0.0042

    static let yolkColor = RGB(hex: 0xE58A0C)
    static let membraneColor = RGB(hex: 0xC9C2B3)
    static let cutColor = RGB(hex: 0xF6F3EC)

    init(appearance: EggAppearance) {
        self.appearance = appearance
        shape = EggShape(aspect: EggArt.aspect)
        material = ShellMaterial(appearance: appearance, shape: shape)
        warp = Noise(seed: Hash.seed(appearance.seed, 0xB001))
        ripple = Noise(seed: Hash.seed(appearance.seed, 0xB002))
        fibers = Noise(seed: Hash.seed(appearance.seed, 0xB003))
        var random = SplitMix64(seed: Hash.seed(appearance.seed, 0xB004))

        let yolkCenter = Vec2(random.uniform(-0.06 ... 0.0), random.uniform(-0.015 ... 0.03))
        let yolkRadius = random.uniform(0.112 ... 0.122)
        yolk = Yolk(
            center: yolkCenter,
            radii: Vec2(yolkRadius, yolkRadius * random.uniform(0.9 ... 0.96)),
            angle: random.uniform(0 ... .pi),
            height: yolkRadius * 0.62,
            wobble: (
                random.uniform(0.0 ... 0.02),
                random.uniform(0 ... 6.3),
                random.uniform(0.0 ... 0.012),
                random.uniform(0 ... 6.3)
            )
        )

        // The puddle: a large central blob and lobes where the white ran out further, inside the image bounds.
        var puddle = [Blob(center: Vec2(yolkCenter.x * 0.5, yolkCenter.y * 0.5 - 0.01), radius: 0.19)]
        let lobes = 7
        let start = random.uniform(0 ... 2 * .pi)
        for k in 0 ..< lobes {
            let angle = start + (Double(k) + random.uniform(-0.3 ... 0.3)) / Double(lobes) * 2 * .pi
            let distance = random.uniform(0.11 ... 0.2)
            let radius = random.uniform(0.07 ... 0.125)
            let limit = Vec2(0.43 - radius, 0.33 - radius)
            let center = Vec2(
                Num.clamp(cos(angle) * distance * 1.2, -limit.x, limit.x),
                Num.clamp(sin(angle) * distance * 0.85, -limit.y, limit.y)
            )
            puddle.append(Blob(center: center, radius: radius))
        }
        self.puddle = puddle

        // The firm albumen: a mound around the yolk, slightly off-center.
        let moundShift = Vec2(random.uniform(-0.04 ... 0.04), random.uniform(-0.03 ... 0.03))
        mound = [
            Blob(center: yolkCenter + moundShift, radius: yolkRadius * 1.45),
            Blob(center: yolkCenter - moundShift * 1.6, radius: yolkRadius * 1.15),
        ]

        // A few separate droplets of egg white that splashed off.
        var drops: [Blob] = []
        for _ in 0 ..< 4 {
            let angle = random.uniform(0 ... 2 * .pi)
            let direction = Vec2(cos(angle) * 1.2, sin(angle) * 0.85)
            let radius = random.uniform(0.006 ... 0.016)
            var reach = 0.2
            while reach < 0.45, Self.puddleDistance(direction * reach, puddle) < radius + 0.012 {
                reach += 0.005
            }
            let center = direction * (reach + random.uniform(0.0 ... 0.02))
            guard abs(center.x) < 0.47 - radius, abs(center.y) < 0.37 - radius else { continue }
            drops.append(Blob(center: center, radius: radius))
        }
        self.drops = drops

        pieces = Self.scatterPieces(&random, avoiding: yolk, puddle: puddle)
    }

    // MARK: Layout

    /// Three to six fragments around the puddle: one big cup, a few medium pieces, some crumbs.
    private static func scatterPieces(_ random: inout SplitMix64, avoiding yolk: Yolk, puddle: [Blob]) -> [Piece] {
        let count = 3 + random.index(below: 4)
        let sizes = [0.13, 0.1, 0.075, 0.055, 0.04, 0.03]
        let start = random.uniform(0 ... 2 * .pi)
        var pieces: [Piece] = []
        for index in 0 ..< count {
            let size = sizes[index] * random.uniform(0.88 ... 1.12)
            // Spread evenly around the yolk, big pieces near the rim of the puddle, crumbs anywhere.
            let angle = start + (Double(index) + random.uniform(-0.25 ... 0.25)) * 2 * .pi / Double(count) * 1.0
            let direction = Vec2(cos(angle), sin(angle) * 0.78)
            var reach = 0.05
            while reach < 0.42, puddleDistance(yolk.center + direction * reach, puddle) < -size * 0.35 {
                reach += 0.005
            }
            reach += random.uniform(-0.03 ... 0.02)
            reach = max(reach, yolk.radii.x + size + 0.02)
            var center = yolk.center + direction * reach
            let limit = Vec2(0.485 - size * 1.05, 0.385 - size * 1.05)
            center = Vec2(Num.clamp(center.x, -limit.x, limit.x), Num.clamp(center.y, -limit.y, limit.y))
            let outline = jaggedOutline(&random, size: size)
            let bound = outline.map(\.length).max() ?? size
            let insideUp = index == 0 ? true : index == 1 ? false : random.chance(0.4)
            pieces.append(Piece(
                center: center,
                angle: random.uniform(0 ... 2 * .pi),
                outline: outline,
                bound: bound,
                insideUp: insideUp,
                apex: Vec2(random.uniform(-0.25 ... 0.25), random.uniform(-0.25 ... 0.25)) * size,
                originT: random.uniform(-0.75 ... 0.75),
                originPhi: random.uniform(-1.2 ... 1.2),
                lift: size * (insideUp ? 0.14 : 0.24),
                lean: Vec2(random.uniform(-0.22 ... 0.22), random.uniform(-0.22 ... 0.22))
            ))
        }
        return pieces
    }

    /// A fracture outline: a rough polygon whose edges are straight cracks with small zigzags.
    private static func jaggedOutline(_ random: inout SplitMix64, size: Double) -> [Vec2] {
        let corners = 6 + random.index(below: 4)
        let elongation = random.uniform(0.62 ... 0.95)
        var main: [Vec2] = []
        for k in 0 ..< corners {
            let angle = (Double(k) + random.uniform(-0.3 ... 0.3)) / Double(corners) * 2 * .pi
            let radius = size * random.uniform(0.6 ... 1.0)
            main.append(Vec2(cos(angle) * radius, sin(angle) * radius * elongation))
        }
        var outline: [Vec2] = []
        for k in 0 ..< corners {
            let a = main[k], b = main[(k + 1) % corners]
            outline.append(a)
            let edge = b - a
            let normal = Vec2(-edge.y, edge.x)
            let steps = 1 + random.index(below: 3)
            for step in 1 ... steps {
                let t = (Double(step) + random.uniform(-0.25 ... 0.25)) / Double(steps + 1)
                outline.append(a + edge * t + normal * random.uniform(-0.09 ... 0.09))
            }
        }
        return outline
    }

    static func puddleDistance(_ p: Vec2, _ blobs: [Blob]) -> Double {
        guard let first = blobs.first else { return .infinity }
        var distance = (p - first.center).length - first.radius
        for blob in blobs.dropFirst() {
            distance = Num.smoothMin(distance, (p - blob.center).length - blob.radius, 0.07)
        }
        return distance
    }

    // MARK: Egg white

    /// Signed distance to the outline of the egg white, with a ragged, wandering edge.
    func whiteDistance(_ p: Vec2) -> Double {
        let warped = p + Vec2(warp.value(p.x * 5, p.y * 5), warp.value(p.x * 5 + 17, p.y * 5 - 9)) * 0.03
        var distance = Self.puddleDistance(warped, puddle)
        distance += 0.0035 * warp.fractal(p.x * 13 + 3, p.y * 13, octaves: 2)
        for drop in drops {
            distance = min(distance, (p - drop.center).length - drop.radius)
        }
        return distance
    }

    /// How much of the firm albumen is at `p`, 0 ... 1.
    func moundAmount(_ p: Vec2) -> Double {
        let warped = p + Vec2(ripple.value(p.x * 7, p.y * 7), ripple.value(p.x * 7 - 5, p.y * 7 + 11)) * 0.02
        return Num.smoothstep(0.02, -0.07, Self.puddleDistance(warped, mound))
    }

    /// Height of the egg white's surface: a meniscus at the edge, the mound and a gentle unevenness.
    func whiteHeight(_ p: Vec2) -> Double {
        let inside = max(-whiteDistance(p), 0)
        let thin = 0.0105 * tanh(inside / 0.016)
        let firm = 0.0095 * moundAmount(p)
        let uneven = 0.0014 * ripple.fractal(p.x * 10, p.y * 10, octaves: 3) * Num.smoothstep(0, 0.04, inside)
        return thin + firm + uneven
    }

    // MARK: Shading

    func shade(_ p: Vec2, pixel: Double, filter: Double) -> Sample {
        var color = Premultiplied.clear
        var edge = Double.infinity

        // The yolk's soft shadow on the ground, seen through the egg white.
        let yolkShadow = Shape2D.blurred(yolk.distance(p + Studio.keySide * 0.03), sigma: 0.026)
        color.over(Self.shadowTint, alpha: 0.3 * yolkShadow)

        let white = whiteDistance(p)
        edge = min(edge, abs(white) / pixel)
        let whiteCoverage = Shape2D.coverage(white, width: filter)
        if whiteCoverage > 0 {
            color.over(eggWhite(p, distance: white, pixel: pixel) * whiteCoverage)
        }

        let yolkDistance = yolk.distance(p)
        edge = min(edge, abs(yolkDistance) / pixel)
        let yolkCoverage = Shape2D.coverage(yolkDistance, width: filter)
        if yolkCoverage > 0 {
            color.over(Film.develop(yolkRadiance(p)), alpha: yolkCoverage)
        }

        for piece in pieces {
            let q = piece.local(p)
            guard q.length < piece.bound + 0.06 else { continue }
            let distance = Shape2D.polygon(q, piece.outline)
            // Contact shadow: a soft one shifted away from the light and a tight dark line where the piece touches.
            let shifted = Shape2D.polygon(piece.local(p + Studio.keySide * piece.lift), piece.outline)
            let soft = Shape2D.blurred(shifted, sigma: 0.3 * piece.lift + 0.003)
            let contact = piece.insideUp ? 0 : Shape2D.blurred(distance - 0.0015, sigma: 0.0025)
            color.over(Self.shadowTint, alpha: 0.42 * soft + 0.45 * contact)
            edge = min(edge, abs(distance) / pixel)
            let coverage = Shape2D.coverage(distance, width: filter)
            if coverage > 0 {
                color.over(Film.develop(pieceRadiance(piece, q, distance: distance, pixel: pixel)), alpha: coverage)
            }
        }
        return Sample(color: color, edge: edge)
    }

    /// Shadows on the white table are slightly cool: they are lit only by the room.
    static let shadowTint = RGB(0.015, 0.02, 0.03)

    /// The egg white as a translucent layer.
    private func eggWhite(_ p: Vec2, distance: Double, pixel: Double) -> Premultiplied {
        let step = 0.0025
        let h = whiteHeight(p)
        let normal = Vec3(
            -(whiteHeight(p + Vec2(step, 0)) - h) / step,
            -(whiteHeight(p + Vec2(0, step)) - h) / step,
            1
        ).normalized
        let inside = max(-distance, 0)
        let firm = moundAmount(p)
        // Which way the edge faces: the downhill direction of the meniscus.
        let lit = Studio.towardsKey(normal.x, normal.y, low: -0.6, high: 0.7)
        let slope = (normal.x * normal.x + normal.y * normal.y).squareRoot()

        var layer = Premultiplied.clear
        // Body: thin albumen is almost clear with a yellow-green cast; the firm albumen is a little milky.
        let body = RGB(0.56, 0.55, 0.38).mixed(with: RGB(0.8, 0.79, 0.63), firm)
        layer.over(body, alpha: 0.08 + 0.1 * firm)
        // Refraction at the meniscus shows the darker room: a fine dark line at the edge, wider on the lit side.
        let line = max(1.3 * pixel, 0.0035)
        let refraction = 0.36 * exp(-pow(inside / line, 2)) + 0.16 * lit * exp(-inside / 0.012) + 0.5 * slope * slope
        layer.over(Water.refractionTint, alpha: refraction)
        // The meniscus focuses light into a bright line just inside the far edge.
        let focus = exp(-pow((inside - 0.009) / 0.006, 2)) * (1 - lit)
        layer.over(Water.causticTint, alpha: 0.32 * focus)
        // Mirror reflections: the rim towards the light catches the soft box.
        layer.over(.white, alpha: 0.7 * Water.highlight(normal, roughness: 0.1))
        return layer
    }

    private func yolkRadiance(_ p: Vec2) -> RGB {
        let normal = yolk.normal(p)
        let (s, _) = yolk.radial(p)
        let direct = Num.smoothstep(-0.25, 0.85, normal.dot(Studio.mainDirection))
        // Light that travelled further through the yolk comes out deeper and more saturated.
        let mottle = 1 + 0.05 * ripple.fractal(p.x * 40, p.y * 40, octaves: 2)
        let pigment = Self.yolkColor.power(1 + 0.55 * (1 - direct)) * mottle
        var color = pigment * (Studio.irradiance(normal) / .pi)
        // Subsurface glow: light scattered inside the yolk leaves through its base on the shadow side.
        let base = Num.smoothstep(0.55, 1, s)
        color += Self.yolkColor.power(1.6) * (0.9 * base * (1 - direct))
        // The wet membrane mirrors the studio.
        color += RGB(gray: 0.5 * Water.reflection(normal, roughness: 0.16) + 2.5 * Water.glint(normal))
        return color
    }

    // MARK: Shell pieces

    /// The point of the intact egg a piece's local point `q` came from, and the egg's normal there.
    private func eggPoint(_ piece: Piece, _ q: Vec2) -> (Vec3, Vec3) {
        let local = Vec2(q.x, q.y) * (1 / Self.eggScale)
        let ringRadius = max(shape.radius(piece.originT), 0.1)
        let y = piece.originT * shape.halfHeight + local.y
        let t = Num.clamp(y / shape.halfHeight, -0.97, 0.97)
        let radius = shape.radius(t)
        let phi = piece.originPhi + local.x / ringRadius
        let position = Vec3(radius * sin(phi), t * shape.halfHeight, radius * cos(phi))
        let normal = Vec3(sin(phi), -shape.radiusSlope(t), cos(phi)).normalized
        return (position, normal)
    }

    private func pieceRadiance(_ piece: Piece, _ q: Vec2, distance: Double, pixel: Double) -> RGB {
        // The piece is a cap of a sphere with the shell's curvature.
        let relative = q - piece.apex
        let tilt = Vec2(relative.x, relative.y) * (1 / Self.shellRadius)
        let tilted = (piece.insideUp ? tilt * -1 : tilt) + piece.lean
        let lateral = tilted.rotated(piece.angle)
        let normal = Vec3(lateral.x, lateral.y, max(1 - tilt.dot(tilt), 0.05).squareRoot()).normalized
        let inside = -distance

        if piece.insideUp {
            // From the edge inwards: the outer skin turning down, the white fracture face, then the membrane.
            if inside < 0.0016 {
                return skin(piece, q, normal: Vec3(-lateral.x * 3, -lateral.y * 3, 1).normalized, pixel: pixel) * 0.85
            }
            if inside < 0.0016 + Self.shellThickness {
                return Self.cutColor * (Studio.irradiance(Vec3(normal.x * 0.3, normal.y * 0.3, 1).normalized) / .pi)
            }
            return membrane(piece, q, normal: normal, inside: inside)
        }
        var color = skin(piece, q, normal: normal, pixel: pixel)
        // The fracture face peeks out as a fine pale line along the edge.
        let cut = Num.smoothstep(0.0024, 0.0008, inside)
        color = color.mixed(with: Self.cutColor * (Studio.irradiance(normal) / .pi * 0.8), cut)
        return color
    }

    /// The outer side of the shell, with the egg's own material.
    private func skin(_ piece: Piece, _ q: Vec2, normal: Vec3, pixel: Double) -> RGB {
        let (position, eggNormal) = eggPoint(piece, q)
        let surface = material.surface(at: position, normal: eggNormal, footprint: pixel / Self.eggScale)
        return ShellShader.radiance(surface, normal: normal)
    }

    /// The inner membrane: off-white, fibrous, partly wet with egg white; the rim shades the side towards the light.
    private func membrane(_ piece: Piece, _ q: Vec2, normal: Vec3, inside: Double) -> RGB {
        let fiber = fibers.fractal(q.x * 140, q.y * 140, octaves: 2)
        let tint = RGB(appearance.base).clamped(0.0005, 1)
        let albedo = Self.membraneColor.mixed(with: tint, 0.08) * (1 + 0.04 * fiber)
        // Self-shadow of the cup: points close to the rim on the light's side are shaded by the wall.
        let depth = max(min(inside, 0.03), 0) * piece.lift * 30
        let towardsLight = Shape2D.polygon(q + Studio.keySide.rotated(-piece.angle) * (0.004 + depth), piece.outline)
        let shadowed = 1 - 0.55 * Num.smoothstep(-0.003, 0.002, towardsLight)
        var color = albedo * (Studio.irradiance(normal) / .pi * shadowed)
        // Light shining through the thin shell warms the side away from the light.
        let glow = 1 - Studio.towardsKey(normal.x, normal.y)
        color += tint * albedo * (0.25 * glow)
        // Wet patches of egg white mirror the studio.
        let wet = Num.smoothstep(0.1, 0.35, fibers.fractal(q.x * 30 + 7, q.y * 30, octaves: 2))
        let roughness = Num.mix(0.45, 0.1, wet)
        let fresnel = Shading.fresnel(0.035, cosine: max(normal.z, 1e-4), roughness: roughness)
        let mirror = Vec3.up.reflected(about: normal)
        color += RGB(gray: fresnel * Studio.radiance(mirror, blur: Studio.blur(roughness: roughness)) * shadowed)
        return color
    }
}
