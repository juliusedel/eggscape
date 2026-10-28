import Foundation

/// A pixel built up from translucent layers: premultiplied, in display-linear values (after `Film`).
///
/// Water, egg white and shadows are partly transparent and end up over a background the renderer never sees (the
/// white studio or the live camera). Stacking layers with the `over` operator in premultiplied form keeps that exact,
/// averaging premultiplied samples is the correct box filter for anti-aliasing, and the result reaches `Encoder` only
/// once, so the 8-bit invariant (no channel above alpha) holds by construction.
struct Premultiplied: Sendable {
    var color: RGB
    var alpha: Double

    static let clear = Premultiplied(color: .black, alpha: 0)

    /// Lays a straight (not premultiplied) color `top` with opacity `alpha` over the pixel.
    mutating func over(_ top: RGB, alpha: Double) {
        let alpha = Num.clamp(alpha)
        guard alpha > 0 else { return }
        color = top * alpha + color * (1 - alpha)
        self.alpha = alpha + self.alpha * (1 - alpha)
    }

    /// Lays a premultiplied layer over the pixel.
    mutating func over(_ top: Premultiplied) {
        color = top.color + color * (1 - top.alpha)
        alpha = top.alpha + alpha * (1 - top.alpha)
    }

    static func + (a: Premultiplied, b: Premultiplied) -> Premultiplied {
        Premultiplied(color: a.color + b.color, alpha: a.alpha + b.alpha)
    }

    static func * (a: Premultiplied, s: Double) -> Premultiplied {
        Premultiplied(color: a.color * s, alpha: a.alpha * s)
    }

    func pixel(x: Int, y: Int) -> Pixel8 {
        guard alpha > 1e-6 else { return .clear }
        return Encoder.pixel(color / alpha, alpha: alpha, x: x, y: y)
    }
}

/// One shaded sample and how far it is from the nearest hard edge, in pixels.
struct Sample: Sendable {
    var color: Premultiplied
    var edge: Double
}

/// Renders an image from a sample function, supersampling only where an edge passes through a pixel.
///
/// Interior pixels are smooth (lighting, soft shadows, translucency) and need one sample; pixels within 1.5 px of a
/// silhouette are refined on an `n × n` grid. The shader gets the sample position in pixels (x right, y down from the
/// top-left corner) and the width of the box filter it should anti-alias analytic edges with: 1 for a full pixel,
/// `1 / n` for a sub-sample, so coverage stays smooth even where the grid alone would give only `n² + 1` levels.
enum Supersampler {
    static func render(
        width: Int,
        height: Int,
        samples n: Int,
        shade: @Sendable (_ x: Double, _ y: Double, _ filter: Double) -> Sample
    ) -> PixelImage {
        Raster.render(width: width, height: height) { column, row in
            let center = shade(Double(column) + 0.5, Double(row) + 0.5, 1)
            guard n > 1, center.edge < 1.5 else { return center.color.pixel(x: column, y: row) }
            var sum = Premultiplied.clear
            let step = 1 / Double(n)
            for j in 0 ..< n {
                for i in 0 ..< n {
                    let x = Double(column) + (Double(i) + 0.5) * step
                    let y = Double(row) + (Double(j) + 0.5) * step
                    sum = sum + shade(x, y, step).color
                }
            }
            return (sum * (step * step)).pixel(x: column, y: row)
        }
    }
}

/// Signed distance functions and filters for flat outlines (negative inside).
enum Shape2D {
    /// Signed distance to a closed polygon, exact (Inigo Quilez's winding-number formulation).
    static func polygon(_ p: Vec2, _ vertices: [Vec2]) -> Double {
        guard let first = vertices.first else { return .infinity }
        var distance = (p - first).dot(p - first)
        var sign = 1.0
        var j = vertices.count - 1
        for i in 0 ..< vertices.count {
            let a = vertices[i], b = vertices[j]
            let edge = b - a
            let w = p - a
            let t = Num.clamp(w.dot(edge) / max(edge.dot(edge), 1e-18))
            let offset = w - edge * t
            distance = min(distance, offset.dot(offset))
            let above = p.y >= a.y, below = p.y < b.y, turn = edge.x * w.y > edge.y * w.x
            if (above && below && turn) || (!above && !below && !turn) {
                sign = -sign
            }
            j = i
        }
        return sign * distance.squareRoot()
    }

    /// Coverage of a shape at signed distance `distance` under a box filter `width` wide.
    static func coverage(_ distance: Double, width: Double) -> Double {
        Num.clamp(0.5 - distance / max(width, 1e-12))
    }

    /// How much of a Gaussian blur (standard deviation `sigma`) of a shape covers a point at signed distance
    /// `distance`: the profile of a soft shadow.
    static func blurred(_ distance: Double, sigma: Double) -> Double {
        0.5 * (1 - Num.erf(distance / (sigma * 2.0.squareRoot())))
    }
}
