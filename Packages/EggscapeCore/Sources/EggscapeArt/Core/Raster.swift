import Foundation

/// One finished pixel: premultiplied sRGB bytes.
struct Pixel8: Sendable, Equatable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8

    static let clear = Pixel8(r: 0, g: 0, b: 0, a: 0)
}

/// Turns shaded values into premultiplied 8-bit pixels with dithering.
enum Encoder {
    /// Interleaved gradient noise (Jimenez 2014): a cheap, position-only pattern with blue-noise-like spectrum, so
    /// dithering is deterministic and invisible.
    static func gradientNoise(_ x: Int, _ y: Int) -> Double {
        let value = 0.067_110_56 * Double(x) + 0.005_837_15 * Double(y)
        let inner = value - value.rounded(.down)
        let outer = 52.982_918_9 * inner
        return outer - outer.rounded(.down)
    }

    /// Triangular dither in -1 ... 1 for one channel (two decorrelated samples summed).
    static func dither(_ x: Int, _ y: Int, channel: Int) -> Double {
        gradientNoise(x + 23 * channel, y + 41 * channel) + gradientNoise(x + 113 + 7 * channel, y + 71) - 1
    }

    /// Encodes a display-linear color (after `Film`) with coverage `alpha` as a premultiplied sRGB pixel.
    ///
    /// The color is encoded first and then multiplied by the quantized alpha, which is what `premultipliedLast` sRGB
    /// images contain; doing it in this order keeps every channel `<=` alpha and avoids dark fringes on edges.
    static func pixel(_ color: RGB, alpha: Double, x: Int, y: Int) -> Pixel8 {
        let alphaScaled = Num.clamp(alpha) * 255
        guard alphaScaled >= 0.5 else { return .clear }
        let alphaByte: Double
        if alphaScaled >= 254.5 {
            alphaByte = 255
        } else {
            let jitter = gradientNoise(x + 57, y + 13) - 0.5
            alphaByte = Num.clamp((alphaScaled + jitter).rounded(), 1, 254)
        }
        func channel(_ value: Double, _ index: Int) -> UInt8 {
            let encoded = ColorCurve.fastEncoded(value) * alphaByte
            let dithered = (encoded + 0.5 * dither(x, y, channel: index)).rounded()
            return UInt8(Num.clamp(dithered, 0, alphaByte))
        }
        return Pixel8(r: channel(color.r, 0), g: channel(color.g, 1), b: channel(color.b, 2), a: UInt8(alphaByte))
    }
}

/// A raw pointer that may cross into `DispatchQueue.concurrentPerform`. Each worker writes a disjoint set of rows, so
/// sharing it is safe even though the compiler cannot prove it.
private struct SharedBytes: @unchecked Sendable {
    let base: UnsafeMutablePointer<UInt8>
}

/// Renders images row by row on all cores.
///
/// Every pixel is computed from its coordinates alone (no shared random state), so the result is identical no matter
/// how the rows are scheduled.
enum Raster {
    static func render(width: Int, height: Int, pixel: @Sendable (Int, Int) -> Pixel8) -> PixelImage {
        guard width > 0, height > 0 else { return PixelImage(width: max(width, 0), height: max(height, 0)) }
        let count = width * height * 4
        let bytes = [UInt8](unsafeUninitializedCapacity: count) { buffer, initialized in
            guard let base = buffer.baseAddress else {
                initialized = 0
                return
            }
            let shared = SharedBytes(base: base)
            let rowsPerTask = max(1, min(16, height / 64))
            let tasks = (height + rowsPerTask - 1) / rowsPerTask
            DispatchQueue.concurrentPerform(iterations: tasks) { task in
                let firstRow = task * rowsPerTask
                for y in firstRow ..< min(firstRow + rowsPerTask, height) {
                    var index = y * width * 4
                    for x in 0 ..< width {
                        let value = pixel(x, y)
                        shared.base[index] = value.r
                        shared.base[index + 1] = value.g
                        shared.base[index + 2] = value.b
                        shared.base[index + 3] = value.a
                        index += 4
                    }
                }
            }
            initialized = count
        }
        return PixelImage(width: width, height: height, rgba: bytes)
    }

    /// Evaluates `value` for every cell of a `width` × `height` grid in parallel; used for low-resolution helper maps.
    static func grid(width: Int, height: Int, value: @Sendable (Int, Int) -> Double) -> [Double] {
        guard width > 0, height > 0 else { return [] }
        let count = width * height
        return [Double](unsafeUninitializedCapacity: count) { buffer, initialized in
            guard let base = buffer.baseAddress else {
                initialized = 0
                return
            }
            let shared = SharedDoubles(base: base)
            DispatchQueue.concurrentPerform(iterations: height) { y in
                for x in 0 ..< width {
                    shared.base[y * width + x] = value(x, y)
                }
            }
            initialized = count
        }
    }
}

private struct SharedDoubles: @unchecked Sendable {
    let base: UnsafeMutablePointer<Double>
}

/// A low-resolution map sampled with bilinear interpolation, for soft quantities such as shadows.
struct ScalarMap: Sendable {
    let width: Int
    let height: Int
    let values: [Double]

    /// Bilinear sample at continuous grid coordinates (cell centres at integers); outside the grid it clamps.
    func sample(_ x: Double, _ y: Double) -> Double {
        let fx = Num.clamp(x, 0, Double(width - 1))
        let fy = Num.clamp(y, 0, Double(height - 1))
        let x0 = min(Int(fx), width - 2 < 0 ? 0 : width - 2)
        let y0 = min(Int(fy), height - 2 < 0 ? 0 : height - 2)
        let x1 = min(x0 + 1, width - 1)
        let y1 = min(y0 + 1, height - 1)
        let tx = fx - Double(x0)
        let ty = fy - Double(y0)
        let top = values[y0 * width + x0] * (1 - tx) + values[y0 * width + x1] * tx
        let bottom = values[y1 * width + x0] * (1 - tx) + values[y1 * width + x1] * tx
        return top * (1 - ty) + bottom * ty
    }
}
