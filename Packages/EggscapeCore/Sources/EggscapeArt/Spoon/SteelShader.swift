import Foundation

/// Polished stainless steel, lit by the same studio as the eggs.
///
/// Steel has no diffuse color: everything it shows is the studio, mirrored about the surface normal and blurred a
/// little by the polish. The concave bowl therefore shows an inverted, curved picture of the studio (the key soft box
/// as a bright window on the bowl's far wall, the black flag as dark zones), the convex handle a long streak where its
/// dome faces the key, and the rolled lip a thin line where its normals sweep through every light at once.
///
/// Steel shows the whole room, so it also shows what the egg cannot: like every product shot of polished metal, the
/// set is wrapped in white diffusion around the camera (a light tent) and white cards that keep the far side from
/// reflecting as a black hole. The black flag still reads, as a dark gray, which gives the metal its definition.
///
/// The key soft box's reflection is returned separately: it is the part the game moves with the tilt (see
/// `SpoonArt.highlight(unit:)`).
struct SteelShader: Sendable {
    /// Radiance of the light tent around the camera, seen within about 30° of straight up.
    static let tent = 1.0
    /// The white cards around the set: a little light from every direction above the table.
    static let cards = 0.15

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
        if point.inBowl {
            // Pressed and polished: long, shallow waves that bend the reflections a little, as on any real spoon.
            let wave = Vec3(
                polish.fractal(x * 3.1, y * 2.7, octaves: 3),
                polish.fractal(x * 2.9 + 17, y * 3.3, octaves: 3),
                0
            )
            normal = (normal + wave * 0.018 * normal.z).normalized
            roughness = 0.16
            shade = 1 + 0.012 * fineGrain(x, y, footprint: footprint)
        } else {
            // The lip is mirror-polished; the handle is brushed along its length: fine streaks that vary the polish
            // (and with it the brightness) across the handle, but stay constant along it.
            let streak = brushed(x, y, footprint: footprint) * point.brushed
            normal = (normal + Vec3(0.02 * streak, 0, 0)).normalized
            roughness = Num.mix(0.12, 0.2, point.brushed) + 0.04 * streak
            shade = 1 + 0.045 * streak
        }

        let cosView = max(normal.z, 1e-4)
        var mirror = Vec3.up.reflected(about: normal)
        var fresnel = Shading.fresnel(Self.reflectance, cosine: cosView, roughness: roughness) * shade
        // The bowl's wall and the inner half of the lip look down into the bowl.
        let facesBowl = point.rimDistance < SpoonGeometry.lip / 2 && point.brushed < 0.5
        if facesBowl, mirror.z < 0.2 {
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
        return Radiance(
            base: fresnel * Self.surroundings(mirror, blur: blur),
            key: fresnel * Studio.key.radiance(mirror, blur: blur)
        )
    }

    /// Radiance of everything but the key soft box in `direction`, blurred by `blur` radians: the studio's room and
    /// fill light, the light tent over the set and the white cards around it.
    static func surroundings(_ direction: Vec3, blur: Double) -> Double {
        // The tent is a little brighter on the key's side, where the soft box lights it from inside. The lean is
        // linear in the direction, so it stays smooth straight up.
        let keySide = direction.x * Studio.keySide.x + direction.y * Studio.keySide.y
        let lean = Num.clamp(0.75 + 0.6 * keySide, 0.4, 1.2)
        let tent = Self.tent * lean * Num.smoothstep(0.47 - blur, 0.86 + blur, direction.z)
        let cards = Self.cards * Num.smoothstep(-0.08 - blur, 0.12 + blur, direction.z)
        return Studio.ambient(direction, blur: blur) + Studio.fill.radiance(direction, blur: blur) + tent + cards
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
