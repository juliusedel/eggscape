import Foundation

/// Polished stainless steel, lit by the same studio as the eggs.
///
/// Steel has no diffuse color: everything it shows is the studio, mirrored about the surface normal and blurred a
/// little by the polish. The concave bowl therefore shows an inverted, curved picture of the studio (the key soft box
/// as a bright window on the bowl's far wall, the black flag as dark zones), the convex handle a long streak where its
/// dome faces the key, and the rolled lip a thin line where its normals sweep through every light at once.
///
/// The key soft box's reflection is returned separately: it is the part the game moves with the tilt (see
/// `SpoonArt.highlight(unit:)`).
struct SteelShader: Sendable {
    /// Reflectance of polished stainless steel at normal incidence: about 60 %, nearly neutral, with the faint cool
    /// cast of the chromium in it.
    static let reflectance = RGB(0.55, 0.567, 0.6)

    /// Reflected radiance, split into the key soft box and everything else.
    struct Radiance: Sendable {
        var base: RGB
        var key: RGB
    }

    private let polish = Noise(seed: 0x5EED_5900_0001)
    private let grain = Noise(seed: 0x5EED_5900_0002)

    /// Shades the spoon at `(x, y)` (bowl units); `footprint` is the size of one pixel in bowl units.
    func radiance(_ point: SpoonGeometry.Point, x: Double, y: Double, footprint: Double) -> Radiance {
        var normal = point.normal
        var roughness: Double
        var shade = 1.0
        switch point.part {
        case .bowl:
            // Pressed and polished: long, shallow waves that bend the reflections a little, as on any real spoon.
            let wave = Vec3(polish.fractal(x * 3.1, y * 2.7, octaves: 3), polish.fractal(x * 2.9 + 17, y * 3.3, octaves: 3), 0)
            normal = (normal + wave * 0.018 * normal.z).normalized
            roughness = 0.16
            shade = 1 + 0.012 * fineGrain(x, y, footprint: footprint)
        case .lip:
            roughness = 0.12
        case .handle:
            // Brushed along its length: fine streaks that vary the polish (and with it the brightness) across the
            // handle, but stay constant along it.
            let streak = brushed(x, y, footprint: footprint)
            normal = (normal + Vec3(0.012 * streak, 0, 0)).normalized
            roughness = 0.2 + 0.035 * streak
            shade = 1 + 0.03 * streak
        }

        let cosView = max(normal.z, 1e-4)
        var mirror = Vec3.up.reflected(about: normal)
        var fresnel = Shading.fresnel(Self.reflectance, cosine: cosView, roughness: roughness) * shade
        if point.part == .bowl, mirror.z < 0.2 {
            // A ray leaving the steep wall downwards meets the opposite wall and is mirrored again, upwards.
            let bounce = Num.smoothstep(0.2, -0.1, mirror.z)
            let second = Vec3(-mirror.x * 0.6, -mirror.y * 0.6, abs(mirror.z) + 0.5).normalized
            mirror = Vec3(
                Num.mix(mirror.x, second.x, bounce),
                Num.mix(mirror.y, second.y, bounce),
                Num.mix(mirror.z, second.z, bounce)
            ).normalized
            fresnel = fresnel * (1 - bounce + bounce * Self.reflectance.luminance)
        }
        let blur = Studio.blur(roughness: roughness)
        let base = Studio.ambient(mirror, blur: blur) + Studio.fill.radiance(mirror, blur: blur)
        let key = Studio.key.radiance(mirror, blur: blur)
        return Radiance(base: fresnel * base, key: fresnel * key)
    }

    /// Fine, isotropic unevenness of the polish (−1 ... 1), faded out where it would be finer than a pixel.
    private func fineGrain(_ x: Double, _ y: Double, footprint: Double) -> Double {
        let frequency = 160.0
        let fade = Num.clamp(1.5 - 2 * frequency * footprint)
        return fade * grain.fractal(x * frequency, y * frequency, octaves: 2)
    }

    /// Brushing streaks along the handle (−1 ... 1): very fine across, long along the handle.
    private func brushed(_ x: Double, _ y: Double, footprint: Double) -> Double {
        let across = 210.0
        let fade = Num.clamp(1.5 - 2 * across * footprint)
        let fine = grain.value(x * across, y * 3.5)
        let coarse = grain.value(x * across * 0.31 + 41, y * 1.2)
        return fade * (0.6 * fine + 0.4 * coarse)
    }
}
