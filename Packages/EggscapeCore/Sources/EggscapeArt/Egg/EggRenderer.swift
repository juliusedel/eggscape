import EggscapeCore
import Foundation

/// Renders the whole egg and its shadow.
enum EggRenderer {
    /// Edge pixels are supersampled on an `n × n` grid.
    static let edgeSamples = 4

    static func egg(_ appearance: EggAppearance, width: Int) -> PixelImage {
        let width = max(width, 1)
        let height = max(Int((Double(width) * EggArt.aspect).rounded()), 1)
        let shape = EggShape(aspect: EggArt.aspect)
        let material = ShellMaterial(appearance: appearance, shape: shape)
        // The egg spans the image exactly: 1 unit wide, `aspect` units tall.
        let scaleX = 1 / Double(width)
        let scaleY = EggArt.aspect / Double(height)
        let pixel = max(scaleX, scaleY)

        @Sendable func sample(_ x: Double, _ y: Double) -> RGB? {
            guard let point = shape.surface(x: x, y: y) else { return nil }
            let footprint = pixel / max(point.normal.z, 0.2)
            let surface = material.surface(at: point.position, normal: point.normal, footprint: footprint)
            return Film.develop(ShellShader.radiance(surface, normal: point.normal))
        }

        return Raster.render(width: width, height: height) { column, row in
            let x = (Double(column) + 0.5) * scaleX - 0.5
            let y = shape.halfHeight - (Double(row) + 0.5) * scaleY
            let distance = shape.signedDistance(x: x, y: y) / pixel
            if distance > 1.5 {
                return .clear
            }
            if distance < -1.5 {
                return Encoder.pixel(sample(x, y) ?? .black, alpha: 1, x: column, y: row)
            }
            var sum = RGB.black
            var covered = 0
            let n = edgeSamples
            for j in 0 ..< n {
                for i in 0 ..< n {
                    let sx = x + (Double(i) + 0.5 - Double(n) / 2) / Double(n) * scaleX
                    let sy = y - (Double(j) + 0.5 - Double(n) / 2) / Double(n) * scaleY
                    if let color = sample(sx, sy) {
                        sum += color
                        covered += 1
                    }
                }
            }
            guard covered > 0 else { return .clear }
            return Encoder.pixel(sum / Double(covered), alpha: Double(covered) / Double(n * n), x: column, y: row)
        }
    }

    /// The egg's shadow on a surface below it: a dark contact core under the egg and a soft cast shadow around it.
    ///
    /// The egg outline occupies the central `1 / EggArt.shadowSpread` of the image, so the soft falloff fits inside.
    static func shadow(width: Int) -> PixelImage {
        let width = max(width, 1)
        let height = max(Int((Double(width) * EggArt.aspect).rounded()), 1)
        let shape = EggShape(aspect: EggArt.aspect)
        let spread = EggArt.shadowSpread
        // Image pixels to egg units: the egg is `width / spread` pixels wide.
        let scaleX = spread / Double(width)
        let scaleY = spread * EggArt.aspect / Double(height)
        // Shadows on the white table are slightly cool: they are lit only by the room, not the warm-white key.
        let tint = RGB(0.015, 0.02, 0.03)

        return Raster.render(width: width, height: height) { column, row in
            let x = (Double(column) + 0.5 - Double(width) / 2) * scaleX
            let y = (Double(height) / 2 - Double(row) - 0.5) * scaleY
            let distance = Self.smoothEggDistance(shape, x: x, y: y)
            // Contact: the egg touches the surface along a small patch in its middle, where no light gets in.
            let core = Self.blurredEdge(Self.smoothEggDistance(shape, x: x / 0.7, y: y / 0.7) * 0.7, sigma: 0.06)
            // Cast shadow: the outline, softened by the size of the soft box.
            let cast = Self.blurredEdge(distance + 0.01, sigma: 0.085)
            let density = 1 - (1 - 0.72 * core) * (1 - 0.5 * cast)
            return Encoder.pixel(tint, alpha: density, x: column, y: row)
        }
    }

    /// Fraction of a Gaussian blur of the egg that covers a point at signed distance `distance`.
    private static func blurredEdge(_ distance: Double, sigma: Double) -> Double {
        0.5 * (1 - Num.erf(distance / (sigma * 2.0.squareRoot())))
    }

    /// Signed distance to the egg outline (negative inside) that stays smooth beyond the tips, for blurring.
    private static func smoothEggDistance(_ shape: EggShape, x: Double, y: Double) -> Double {
        // An ellipse with the egg's slight top-bottom asymmetry is accurate to well under the blur radius.
        let halfWidth = 0.5 * (1 - EggShape.asymmetry * Num.clamp(y / shape.halfHeight, -1, 1))
        let q = Vec2(x / halfWidth, y / shape.halfHeight)
        let length = q.length
        let gradient = Vec2(x / (halfWidth * halfWidth), y / (shape.halfHeight * shape.halfHeight)).length / max(length, 1e-9)
        return (length - 1) / max(gradient, 1e-9)
    }
}
