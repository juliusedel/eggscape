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
            let fresnel = Shading.fresnel(metal, cosine: cosView, roughness: surface.roughness)
            return fresnel * Studio.radiance(mirror, blur: blur)
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
            // Thin-film interference of nacre: the hue shifts with the viewing angle; pastel, not rainbow.
            let phase = surface.filmPhase + 1.4 * (1 - cosView) + 0.15
            let film = RGB(
                0.5 + 0.5 * cos(2 * .pi * phase),
                0.5 + 0.5 * cos(2 * .pi * (phase + 0.33)),
                0.5 + 0.5 * cos(2 * .pi * (phase + 0.67))
            ).mixed(with: .white, 0.4) * 1.5
            specular = specular * film * surface.iridescence + specular * (1 - surface.iridescence)
            color += film * (0.035 * irradiance / .pi * surface.iridescence)
        }
        color += specular

        if surface.coat > 0 {
            let coatFresnel = Shading.fresnel(0.05, cosine: cosView, roughness: 0.05) * surface.coat
            let reflection = Studio.radiance(mirror, blur: Studio.blur(roughness: 0.07))
            color = color * (1 - coatFresnel) + RGB(gray: coatFresnel * reflection)
        }
        return color
    }
}
