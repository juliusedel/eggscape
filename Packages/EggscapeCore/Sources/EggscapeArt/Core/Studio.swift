import Foundation

/// The photo studio every piece of artwork is lit by, so the egg, the spoon and the effects agree.
///
/// It models the owner's reference photo: one large rectangular soft box at the top right, slightly in front of the
/// viewer; a dark studio on the far side, so the shadow side of the egg falls off into a deep, saturated brown; and a
/// white table that is brightly lit except in the object's own shadow, so grazing reflections along the outline pick
/// up a pale rim. The same analytic description serves diffuse lighting (closed-form irradiance) and mirror
/// reflections (radiance per direction, pre-blurred by the surface roughness), which keeps shading energy-consistent
/// without any random sampling.
enum Studio {
    /// A rectangular area light, described in its own gnomonic plane (tangent plane at distance 1), where a flat
    /// rectangle stays a rectangle.
    struct SoftBox: Sendable {
        let center: Vec3
        let across: Vec3
        let along: Vec3
        /// Half-extent in plane units (the tangent of the half-angle) across and along.
        let halfSize: (Double, Double)
        let radiance: Double
        /// Edge feathering of the diffuser in plane units.
        let feather: Double
        /// Solid angle, for diffuse lighting.
        let solidAngle: Double
        /// Width of the soft terminator, as the sine of an angle.
        let wrap: Double

        init(azimuth: Double, elevation: Double, halfSize: (Double, Double), radiance: Double, feather: Double) {
            center = Vec3.direction(azimuth: azimuth, elevation: elevation)
            across = Vec3.up.cross(center).normalized
            along = center.cross(across)
            self.halfSize = halfSize
            self.radiance = radiance
            self.feather = feather
            // Solid angle of a centred rectangle in the gnomonic plane (exact).
            let a = halfSize.0, b = halfSize.1
            solidAngle = 4 * asin(a * b / ((1 + a * a) * (1 + b * b)).squareRoot())
            // A disc of the same solid angle would give sqrt(Ω/π); the box is feathered and hotter in the middle,
            // which narrows the transition (matches the terminator of the reference photo).
            wrap = 0.45 * (solidAngle / .pi).squareRoot()
        }

        /// Radiance seen in direction `direction`, blurred by a reflection lobe of angular standard deviation `blur`.
        func radiance(_ direction: Vec3, blur: Double) -> Double {
            let facing = direction.dot(center)
            guard facing > 0.05 else { return 0 }
            let u = direction.dot(across) / facing
            let v = direction.dot(along) / facing
            // The gnomonic projection stretches away from the centre, so the same angular blur covers more of it.
            let sigma = (feather * feather + blur * blur * (1 + u * u + v * v)).squareRoot()
            let shape = Num.blurredBox(u, half: halfSize.0, sigma: sigma)
                * Num.blurredBox(v, half: halfSize.1, sigma: sigma)
            // Real soft boxes are a little hotter in the middle than at the edges.
            let spread = (u * u) / (halfSize.0 * halfSize.0) + (v * v) / (halfSize.1 * halfSize.1)
            let hotSpot = 1.12 - 0.3 * min(spread, 1.4)
            return radiance * shape * hotSpot * Num.smoothstep(0.05, 0.25, facing)
        }

        /// Irradiance on a surface with normal `normal`, with the soft terminator of an area light.
        func irradiance(_ normal: Vec3) -> Double {
            radiance * solidAngle * Studio.smoothCosine(normal.dot(center), wrap: wrap)
        }
    }

    /// The key light: a soft box to the right, high up and a little in front of the viewer. Its reflection is the
    /// soft highlight right of the egg's center in the reference photo.
    static let key = SoftBox(azimuth: -5, elevation: 52, halfSize: (0.32, 0.44), radiance: 15, feather: 0.05)

    /// A second, dimmer box towards the top of the screen. Together with the key it puts the light's center of
    /// gravity at the top right, as measured on the reference (shading falls off towards the left and the bottom).
    static let fill = SoftBox(azimuth: 100, elevation: 32, halfSize: (0.6, 0.3), radiance: 5.2, feather: 0.08)

    /// Where the light comes from on average (azimuth 26°, elevation 55°): the reference photo's shading gradient.
    static let mainDirection = Vec3.direction(azimuth: 26, elevation: 55)

    /// Horizontal direction towards the light.
    static let keySide = Vec2(mainDirection.x, mainDirection.y).normalized

    /// Radiance of the lit white table (a white surface under the studio light develops to almost pure white).
    static let table = 2.2
    /// The studio around the lights: walls, a white backdrop near the horizon and a white ceiling scrim.
    static let wallsNear = 0.16
    static let backdropNear = 1.3
    static let ceiling = 0.6

    /// Where shadows come from: the effective direction of the light for cast shadows, and their softness.
    static let shadowDirection = Vec3.direction(azimuth: 26, elevation: 58)
    static let shadowSoftness = 0.2

    /// Smooth replacement for `max(cos, 0)` of a light with angular radius `asin(wrap)`: identical away from the
    /// terminator, and a quadratic blend across it, so lighting from a large source has no hard edge.
    static func smoothCosine(_ cosine: Double, wrap: Double) -> Double {
        if cosine >= wrap {
            return cosine
        }
        if cosine <= -wrap {
            return 0
        }
        return (cosine + wrap) * (cosine + wrap) / (4 * wrap)
    }

    /// 0 for directions away from the key light, 1 towards it (horizontal component only).
    static func towardsKey(_ x: Double, _ y: Double, low: Double = -0.7, high: Double = 0.8) -> Double {
        let length = (x * x + y * y).squareRoot()
        guard length > 1e-9 else { return 0.5 }
        return Num.smoothstep(low, high, (x * keySide.x + y * keySide.y) / length)
    }

    /// Radiance of everything except the soft boxes in direction `direction`, blurred by `blur` radians.
    ///
    /// On the far side of the light stands a black flag (a standard product-photography trick for contrast): it hides
    /// the far table near the horizon and the walls up to about 60°, so the shadow side of the egg falls off into
    /// deep brown and steel shows dark reflections there. Steeper down, the table in front of the flag is lit again,
    /// which gives the pale rim along the egg's left outline.
    static func ambient(_ direction: Vec3, blur: Double) -> Double {
        let z = direction.z
        let side = towardsKey(direction.x, direction.y)
        let far = 1 - side
        // The table, with the object's own shadow straight below it on the far side.
        let shadowed = (1 - towardsKey(direction.x, direction.y, low: -0.9, high: 0.4))
            * Num.smoothstep(0.85, 1.0 + blur, -z)
        let tableRadiance = table * (1 - 0.7 * shadowed)
        let wallFade = Num.smoothstep(0.02, 0.5 + blur, z)
        var sky = Num.mix(backdropNear, wallsNear, wallFade)
        sky = Num.mix(sky, ceiling, Num.smoothstep(0.55, 0.95 + blur, z))
        let horizon = 0.03 + blur
        let open = Num.mix(tableRadiance, sky, Num.smoothstep(-horizon, horizon, z))
        let flag = far * Num.smoothstep(-0.5 - blur, -0.22, z) * (1 - Num.smoothstep(0.72, 0.92 + blur, z))
        return Num.mix(open, flagRadiance, flag)
    }

    /// The black flag on the far side.
    static let flagRadiance = 0.03

    /// Radiance arriving from `direction`, pre-blurred by `blur` (radians): what a mirror-like surface reflects.
    static func radiance(_ direction: Vec3, blur: Double) -> Double {
        ambient(direction, blur: blur) + key.radiance(direction, blur: blur) + fill.radiance(direction, blur: blur)
    }

    /// Irradiance on a diffuse surface with normal `normal`, from the soft box, the table bounce and the room.
    static func irradiance(_ normal: Vec3) -> Double {
        let lower = 0.5 - 0.5 * normal.z
        let upper = 0.5 + 0.5 * normal.z
        let side = towardsKey(normal.x, normal.y)
        // The flag and the object's shadow take away most of the bounce on the far side.
        let tableSeen = table * (0.15 + 0.85 * towardsKey(normal.x, normal.y, low: -0.9, high: 0.4))
        let roomSeen = Num.mix(flagRadiance, 0.5 * (wallsNear + backdropNear), side) * 0.5 + 0.4 * ceiling * upper
        return key.irradiance(normal) + fill.irradiance(normal)
            + Double.pi * (lower * tableSeen * 0.35 + upper * roomSeen)
    }

    /// Angular standard deviation of the reflection lobe of a surface with perceptual roughness `roughness`.
    static func blur(roughness: Double) -> Double {
        1.25 * roughness * roughness
    }
}

/// Microfacet helpers.
enum Shading {
    /// Schlick's Fresnel approximation, with the grazing boost damped for rough surfaces.
    static func fresnel(_ f0: Double, cosine: Double, roughness: Double) -> Double {
        let grazing = max(1 - roughness, f0)
        let m = 1 - Num.clamp(cosine)
        let m2 = m * m
        return f0 + (grazing - f0) * m2 * m2 * m
    }

    static func fresnel(_ f0: RGB, cosine: Double, roughness: Double) -> RGB {
        RGB(
            fresnel(f0.r, cosine: cosine, roughness: roughness),
            fresnel(f0.g, cosine: cosine, roughness: roughness),
            fresnel(f0.b, cosine: cosine, roughness: roughness)
        )
    }
}
