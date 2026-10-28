import CoreGraphics
import EggscapeArt
import Foundation
import ImageIO

enum ToolError: Error, CustomStringConvertible {
    case usage(String)
    case imageEncoding(String)

    var description: String {
        switch self {
        case let .usage(message): message
        case let .imageEncoding(path): "could not encode PNG at \(path)"
        }
    }
}

/// Writes `PixelImage`s as PNG through ImageIO (which stores straight alpha, as PNG requires).
enum PNGFile {
    static func cgImage(_ image: PixelImage) throws -> CGImage {
        guard
            let provider = CGDataProvider(data: Data(image.rgba) as CFData),
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let cgImage = CGImage(
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: image.width * 4,
                space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else {
            throw ToolError.imageEncoding("memory")
        }
        return cgImage
    }

    static func write(_ image: PixelImage, to url: URL) throws {
        let cgImage = try cgImage(image)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw ToolError.imageEncoding(url.path)
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ToolError.imageEncoding(url.path)
        }
    }
}
