import Foundation

/// Clear liquids (rain water, egg white) seen from above in the studio.
///
/// A clear liquid has almost no color of its own; what makes it visible in a photo is how it bends and mirrors the
/// light. The renderer never sees the background it will be drawn over (white studio or camera), so every effect is a
/// translucent layer that works over both: mirror reflections of the studio as white with alpha, refraction as a dark,
/// cool layer (the drop shows the darker room instead of the bright table), and caustics as white with alpha (light
/// focused onto the surface below, which brightens a gray ground and leaves an already white one white).
enum Water {
    /// Reflectance of water at normal incidence.
    static let reflectance = 0.02
    /// A soft box's diffuser is several times brighter in its core than on average. Water is smooth enough to mirror
    /// that core, which is why the tiny window highlight of a drop looks white in a photo while the same light on the
    /// matte shell stays a soft glow.
    static let coreBoost = 7.0
    /// What refraction shows instead of the lit table: the dark, slightly cool room.
    static let refractionTint = RGB(0.055, 0.062, 0.075)
    /// Light focused by the liquid: the warm white of the soft box.
    static let causticTint = RGB(1, 0.995, 0.97)

    /// Scene radiance mirrored by a liquid surface with normal `normal`.
    static func reflection(_ normal: Vec3, roughness: Double) -> Double {
        let cosine = max(normal.z, 1e-4)
        let mirror = Vec3.up.reflected(about: normal)
        let blur = Studio.blur(roughness: roughness)
        let fresnel = Shading.fresnel(reflectance, cosine: cosine, roughness: roughness)
        let boxes = Studio.key.radiance(mirror, blur: blur) + Studio.fill.radiance(mirror, blur: blur)
        return fresnel * (Studio.ambient(mirror, blur: blur) + coreBoost * boxes)
    }

    /// The display value of that reflection: the opacity of white to lay over whatever is below.
    static func highlight(_ normal: Vec3, roughness: Double) -> Double {
        Film.curve(reflection(normal, roughness: roughness))
    }
}

/// A drop of water lying on a surface, seen from above: a spherical cap with a slightly irregular outline, optionally
/// stretched along an axis (the flying droplets of a splash).
///
/// The look follows photographs of drops lit from one side: the half facing the light shows a dark crescent (looking
/// through the steep side of the lens you see the dark room, not the bright table), the far half holds a bright
/// caustic (the drop focuses the key light onto the surface behind its center), a thin dark contact line runs around
/// the outline, a crisp window highlight of the soft box sits towards the light, and a faint shadow falls beside the
/// drop away from the light. All lengths are in the caller's units.
struct Droplet: Sendable {
    var center: Vec2
    var radius: Double
    /// Elongation along `axis`, 1 for a round drop.
    var stretch: Double = 1
    var axis = Vec2(1, 0)
    /// Contact angle: how steep the cap meets the surface (radians).
    var contactAngle = 1.05
    /// Relative amplitudes and phases of the 2nd and 3rd harmonic of the outline.
    var wobble: (Double, Double, Double, Double) = (0, 0, 0, 0)
    /// Strength of the dark crescent and of the caustic.
    var rim = 0.62
    var caustic = 0.55

    /// Local frame: `q.x` along the axis (compressed by the stretch), `q.y` across it, and the outline radius there.
    private func local(_ p: Vec2) -> (q: Vec2, outline: Double, scale: Double) {
        let d = p - center
        let along = d.dot(axis), across = axis.x * d.y - axis.y * d.x
        let q = Vec2(along / stretch, across)
        let length = max(q.length, 1e-12)
        let angle = atan2(q.y, q.x)
        let outline = radius * (1 + wobble.0 * cos(2 * angle + wobble.1) + wobble.2 * cos(3 * angle + wobble.3))
        // A step in q along the axis is `stretch` times longer on the screen.
        let cosine = q.x / length, sine = q.y / length
        let scale = (cosine * cosine * stretch * stretch + sine * sine).squareRoot()
        return (q, outline, scale)
    }

    /// Signed distance to the outline (negative inside), accurate near the outline.
    func distance(_ p: Vec2) -> Double {
        let (q, outline, scale) = local(p)
        return (q.length - outline) * scale
    }

    /// Opacity of the drop's soft shadow on the surface at `p` (outside the drop only).
    func shadow(_ p: Vec2) -> Double {
        let shifted = distance(p + Studio.keySide * (0.3 * radius))
        return 0.16 * Shape2D.blurred(shifted, sigma: 0.2 * radius) * Num.smoothstep(-0.05 * radius, 0.1 * radius, distance(p))
    }

    /// The drop as a premultiplied layer at `p`, and the signed distance to its outline. `filter` is the width of
    /// the anti-aliasing box filter, `pixel` the size of one pixel (for line widths).
    func layer(_ p: Vec2, filter: Double, pixel: Double) -> (Premultiplied, Double) {
        let (q, outline, scale) = local(p)
        let distance = (q.length - outline) * scale
        let coverage = Shape2D.coverage(distance, width: filter)
        guard coverage > 0 else { return (.clear, distance) }
        let s = Num.clamp(q.length / max(outline, 1e-12), 0, 1)
        // Spherical cap: sphere radius 1 / sin(contact angle) in units of the outline radius.
        let tilt = sin(contactAngle) * s
        let lateral = q.length > 1e-12 ? Vec2(q.x / q.length, q.y / q.length) * tilt : .zero
        let screen = axis * (lateral.x / stretch) + Vec2(-axis.y, axis.x) * lateral.y
        let normal = Vec3(screen.x, screen.y, max(1 - tilt * tilt, 1e-4).squareRoot()).normalized
        let direction = (p - center).normalized
        let lit = Studio.towardsKey(direction.x, direction.y, low: -0.85, high: 0.85)
        let pixels = max(outline / pixel, 1)
        let line = max(1.1 / pixels, 0.07)

        var layer = Premultiplied.clear
        // The lit half lets less light reach the surface below it (it is bent towards the far half).
        layer.over(Water.refractionTint, alpha: 0.1 * lit * s)
        // Caustic: the drop focuses the key light into a bright crescent on the far side.
        let focus = exp(-pow((s - 0.6) / 0.24, 2)) * pow(1 - lit, 1.6)
        layer.over(Water.causticTint, alpha: caustic * focus)
        // Dark crescent where the steep, lit side refracts the dark room.
        let crescent = Num.smoothstep(0.5, 0.96, s) * (0.25 + 0.75 * pow(lit, 0.8))
        layer.over(Water.refractionTint, alpha: rim * crescent)
        // Contact line around the outline, and a glint of refracted light on the far edge.
        layer.over(Water.refractionTint, alpha: 0.45 * exp(-pow((1 - s) / line, 2)))
        layer.over(Water.causticTint, alpha: 0.5 * caustic * (1 - lit) * exp(-pow((1 - s - 2.2 * line) / line, 2)))
        // Mirror reflection of the studio: the soft box as a small window towards the light.
        layer.over(.white, alpha: Water.highlight(normal, roughness: 0.035))
        return (layer * coverage, distance)
    }
}
