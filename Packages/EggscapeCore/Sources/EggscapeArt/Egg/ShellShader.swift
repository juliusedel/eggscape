import Foundation

/// Lights a `ShellSurface` with the studio.
///
/// Energy-conserving layering: a diffuse body (with subsurface saturation on the shadow side) under a dielectric
/// specular layer, an optional clear coat on top, or a pure metal. Specular reflections look up the studio radiance in
/// the mirror direction, pre-blurred by the roughness, so the key soft box shows up as the broad, soft highlight of a
/// matte shell or as a crisp window on a lacquered one.
enum ShellShader {
    static func radiance(_ surface: ShellSurface, normal geometric: Vec3) -> RGB {
        let normal = (geometric + surface.bump).normalized
        let cosView = max(normal.z, 1e-4)
        let mirror = Vec3.up.reflected(about: normal)
        let blur = Studio.blur(roughness: surface.roughness)

        if let metal = surface.metal {
            // Polished metal is shot in a white tent (see `MetalStudio`): bright, smooth reflections of the sweep, the
            // cards and the soft boxes, tinted by the metal's own color and paling to white at grazing angles.
            let fresnel = Shading.fresnel(metal, cosine: cosView, roughness: surface.roughness)
            return fresnel * MetalStudio.radiance(mirror, blur: blur)
        }

        let fresnel = Shading.fresnel(surface.reflectance, cosine: cosView, roughness: surface.roughness)
        let irradiance = Studio.irradiance(normal)
        // How directly the key light reaches this point: 1 facing it, 0 at and beyond the terminator.
        let direct = Num.smoothstep(-0.25, 0.85, normal.dot(Studio.mainDirection))
        let pigment = surface.albedo.power(1 + surface.subsurface * (1 - direct))
        var color = pigment * (irradiance / .pi * (1 - fresnel))

        // A thin shell lets some key light through near the outline: a faint warm glow along the lit rim.
        let rim = pow(1 - cosView, 2) * Num.smoothstep(-0.2, 0.6, normal.dot(Studio.mainDirection))
        color += pigment.power(1.5) * (0.22 * rim * Studio.irradiance(Studio.mainDirection) / .pi)

        var specular = RGB(gray: fresnel * Studio.radiance(mirror, blur: blur) * surface.specularOcclusion)
        if surface.iridescence > 0 {
            // Nacre: interference in its thin layers tints the sheen. Only the palest first orders show, so the tint
            // drifts from warm white facing the camera through a breath of rose to a cool lavender and aqua at the
            // outline, where the light crosses the layers more steeply. Never a rainbow: every tint stays within a
            // few percent of white, and the body takes on only a little of it.
            let grazing = 1 - cosView
            let tint = nacre(Num.clamp(1.3 * grazing * grazing + surface.filmPhase))
            let strength = surface.iridescence
            specular = specular * RGB.white.mixed(with: tint, strength)
            color = color * RGB.white.mixed(with: tint, strength * (0.3 + 0.7 * Num.smoothstep(0.05, 0.6, grazing)))
        }
        color += specular

        if surface.coat > 0 {
            let coatFresnel = Shading.fresnel(0.05, cosine: cosView, roughness: 0.05) * surface.coat
            let reflection = Studio.radiance(mirror, blur: Studio.blur(roughness: 0.07))
            color = color * (1 - coatFresnel) + RGB(gray: coatFresnel * reflection)
        }
        return color
    }

    /// Stops of `nacre(_:)`: warm white, rose, lavender, aqua.
    private static let nacreStops = [
        RGB(1.0, 0.98, 0.95),
        RGB(1.0, 0.9, 0.92),
        RGB(0.89, 0.88, 1.0),
        RGB(0.84, 0.97, 0.96),
    ]

    /// The pastel interference colors of nacre along `t` (0 ... 1), as multipliers close to white.
    static func nacre(_ t: Double) -> RGB {
        let position = Num.clamp(t) * Double(nacreStops.count - 1)
        let index = min(Int(position), nacreStops.count - 2)
        let fraction = Num.smoothstep(0, 1, position - Double(index))
        return nacreStops[index].mixed(with: nacreStops[index + 1], fraction)
    }
}
