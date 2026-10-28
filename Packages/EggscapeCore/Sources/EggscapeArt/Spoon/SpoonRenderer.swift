import Foundation

/// Renders the three spoon layers. All of them evaluate the same geometry on the same pixel grid, so they register
/// exactly.
enum SpoonRenderer {
    enum Layer {
        case spoon, shadow, highlight
    }

    /// Edge and lip pixels are supersampled on an `n × n` grid.
    static let edgeSamples = 4
    static let detailSamples = 3

    /// The moving part of the key reflection ends this far inside the outline (bowl units), so a tilt shift of a
    /// few points never carries light past the spoon's edge.
    static let highlightInset = (start: 0.04, full: 0.1)

    static func render(_ layer: Layer, unit: Double) -> PixelImage {
        let layout = SpoonGeometry.layout(unit: unit)
        switch layer {
        case .spoon:
            return steel(layout, highlight: false)
        case .highlight:
            return steel(layout, highlight: true)
        case .shadow:
            return shadow(layout)
        }
    }

    // MARK: Steel

    private static func steel(_ layout: SpoonArt.Layout, highlight: Bool) -> PixelImage {
        let unit = max(layout.unit, 1e-6)
        let pixel = 1 / unit
        let shader = SteelShader()

        /// The spoon layer's color and the highlight's encoded increment at one sample.
        @Sendable func sample(_ x: Double, _ y: Double, distance: Double) -> (color: RGB, added: RGB) {
            let point = SpoonGeometry.surface(x, y)
            let light = shader.radiance(point, x: x, y: y, footprint: pixel)
            let moving = Num.smoothstep(highlightInset.start, highlightInset.full, -distance)
            let still = Film.develop(light.base + light.key * (1 - moving))
            guard highlight else { return (still, .black) }
            guard moving > 0 else { return (still, .black) }
            let full = Film.develop(light.base + light.key)
            let added = RGB(
                max(ColorCurve.fastEncoded(full.r) - ColorCurve.fastEncoded(still.r), 0),
                max(ColorCurve.fastEncoded(full.g) - ColorCurve.fastEncoded(still.g), 0),
                max(ColorCurve.fastEncoded(full.b) - ColorCurve.fastEncoded(still.b), 0)
            )
            return (still, added)
        }

        return Raster.render(width: layout.width, height: layout.height) { column, row in
            let x = (Double(column) + 0.5 - layout.bowlCenterX) * pixel
            let y = (layout.bowlCenterY - Double(row) - 0.5) * pixel
            let distance = SpoonGeometry.outlineDistance(x, y)
            if distance > 1.5 * pixel {
                return .clear
            }
            if highlight, distance > -highlightInset.start {
                return .clear
            }
            let n = samples(x, y, distance: distance, pixel: pixel)
            var color = RGB.black
            var added = RGB.black
            var covered = 0
            for j in 0 ..< n {
                for i in 0 ..< n {
                    let sx = x + (Double(i) + 0.5 - Double(n) / 2) / Double(n) * pixel
                    let sy = y - (Double(j) + 0.5 - Double(n) / 2) / Double(n) * pixel
                    let sampleDistance = n == 1 ? distance : SpoonGeometry.outlineDistance(sx, sy)
                    guard sampleDistance < 0 else { continue }
                    let value = sample(sx, sy, distance: sampleDistance)
                    color += value.color
                    added += value.added
                    covered += 1
                }
            }
            guard covered > 0 else { return .clear }
            let total = Double(n * n)
            if highlight {
                return additive(added / total, x: column, y: row)
            }
            return Encoder.pixel(color / Double(covered), alpha: Double(covered) / total, x: column, y: row)
        }
    }

    /// How finely to sample the pixel at `(x, y)`: the outline, the lip and the handle's rounded edges change faster
    /// than a pixel.
    private static func samples(_ x: Double, _ y: Double, distance: Double, pixel: Double) -> Int {
        if distance > -2 * pixel {
            return edgeSamples
        }
        let rim = SpoonGeometry.rim(x, y).distance
        if rim > -0.03, rim < SpoonGeometry.lip + 0.03 {
            return detailSamples
        }
        if y < -0.9, abs(abs(x) - SpoonGeometry.handleHalfWidth(y)) < 0.03 {
            return detailSamples
        }
        return 1
    }

    /// Encodes an increment of encoded sRGB values for additive blending: opaque wherever it adds light, so the
    /// result is the same whether the compositor multiplies the source by its alpha or not, and fully transparent
    /// elsewhere ("black adds nothing").
    private static func additive(_ value: RGB, x: Int, y: Int) -> Pixel8 {
        func channel(_ value: Double, _ index: Int) -> UInt8 {
            let dithered = (value * 255 + 0.5 * Encoder.dither(x, y, channel: index)).rounded()
            return UInt8(Num.clamp(dithered, 0, 255))
        }
        let pixel = Pixel8(r: channel(value.r, 0), g: channel(value.g, 1), b: channel(value.b, 2), a: 255)
        return pixel.r == 0 && pixel.g == 0 && pixel.b == 0 ? .clear : pixel
    }

    // MARK: Shadow

    /// Shadows on the white table are slightly cool: they are lit only by the room, not the warm-white key.
    private static let shadowTint = RGB(0.015, 0.02, 0.03)

    /// The spoon's shadow on the table.
    ///
    /// A table point is in shadow when the spoon crosses the ray from it towards the light. The bowl is a solid
    /// dish standing on its bottom: at height `z` its outline is the rim ellipse scaled by the radius where the dish
    /// reaches that height, so the union of a few slices gives the shadow a soft crescent below the bowl's far side.
    /// The handle is a thin strip at the height of its ridge. Every slice's penumbra grows with its height (the key
    /// is a large soft box), which keeps the shadow light and soft, like the reference photo's.
    private static func shadow(_ layout: SpoonArt.Layout) -> PixelImage {
        let unit = max(layout.unit, 1e-6)
        let pixel = 1 / unit
        let light = Studio.shadowDirection
        let shift = Vec2(light.x / light.z, light.y / light.z)
        let slices = 8

        return Raster.render(width: layout.width, height: layout.height) { column, row in
            let x = (Double(column) + 0.5 - layout.bowlCenterX) * pixel
            let y = (layout.bowlCenterY - Double(row) - 0.5) * pixel
            var cast = 0.0
            // The bowl, slice by slice.
            for slice in 1 ... slices {
                let z = SpoonGeometry.depth * Double(slice) / Double(slices)
                let radius = (1 - pow(1 - z / SpoonGeometry.depth, 4.0 / 3)).squareRoot()
                let qx = x + shift.x * z, qy = y + shift.y * z
                let scaled = SpoonGeometry.rim(qx / radius, qy / radius).distance * radius
                let edge = slice == slices ? SpoonGeometry.lip : 0
                cast = max(cast, coverage(scaled - edge, sigma: penumbra(z)))
            }
            // The neck and the handle at the height of their ridge.
            if y < -0.4 {
                var height = SpoonGeometry.ridge(y)
                for _ in 0 ..< 2 {
                    height = SpoonGeometry.ridge(y + shift.y * height)
                }
                let distance = SpoonGeometry.outlineDistance(x + shift.x * height, y + shift.y * height)
                cast = max(cast, coverage(distance, sigma: penumbra(height)))
            }
            // A faint, wide darkening of the table around the spoon, which hides a little of the room's light.
            let occlusion = coverage(SpoonGeometry.outlineDistance(x, y) - 0.02, sigma: 0.12)
            let density = 1 - (1 - 0.34 * cast) * (1 - 0.1 * occlusion)
            return Encoder.pixel(shadowTint, alpha: density, x: column, y: row)
        }
    }

    /// Standard deviation of the penumbra of an edge `height` above the table.
    private static func penumbra(_ height: Double) -> Double {
        0.012 + 0.22 * height
    }

    /// Fraction of a Gaussian blur of the shape that covers a point at signed distance `distance`.
    private static func coverage(_ distance: Double, sigma: Double) -> Double {
        0.5 * (1 - Num.erf(distance / (sigma * 2.0.squareRoot())))
    }
}
