import CoreGraphics
import EggscapeArt
import EggscapeCore
import ImageIO
import os
import SpriteKit
import UniformTypeIdentifiers

/// Turns `EggscapeArt` pixel images into SpriteKit textures. The spoon comes pre-rendered from the asset catalog
/// (`make art`); eggs and effects are rendered on demand, and eggs are also cached on disk because every skin costs a
/// noticeable fraction of a second. One instance per screen scale lives as long as the app (`shared(screenScale:)`),
/// so runs, "Nochmal", hot-seat turns and races reuse its textures instead of rendering them again.
@MainActor
final class GameArtwork {
    /// Pixels per bowl unit of the spoon images in the asset catalog (`eggscape-art assets`).
    static let spoonAssetUnit = 498.0
    /// Width of the egg in bowl units.
    static let eggWidthUnits = 0.62

    let spoon: SKTexture
    let spoonShadow: SKTexture
    let spoonHighlight: SKTexture
    /// Registration of the three spoon textures, in the pixels of the asset images.
    let spoonLayout: SpoonArt.Layout
    let eggShadow: SKTexture
    let raindrops: [SKTexture]
    let streak: SKTexture
    /// The blowing leaves' particle; an emitter takes a single texture.
    let leaf: SKTexture

    private var eggs: [EggKey: SKTexture] = [:]
    private var brokenEggs: [EggKey: SKTexture] = [:]
    private static var instances: [CGFloat: GameArtwork] = [:]
    private static let logger = Logger(subsystem: "de.juliusedel.eggscape", category: "artwork")

    private struct EggKey: Hashable {
        let appearance: EggAppearance
        let width: Int
    }

    /// The artwork for a screen scale, created on first use.
    static func shared(screenScale: CGFloat) -> GameArtwork {
        if let artwork = instances[screenScale] {
            return artwork
        }
        let artwork = GameArtwork(screenScale: screenScale)
        instances[screenScale] = artwork
        return artwork
    }

    private init(screenScale: CGFloat) {
        spoonLayout = SpoonArt.layout(unit: Self.spoonAssetUnit)
        spoon = Self.assetTexture("Spoon") { SpoonArt.spoon(unit: Self.spoonAssetUnit) }
        spoonShadow = Self.assetTexture("SpoonShadow") { SpoonArt.shadow(unit: Self.spoonAssetUnit) }
        spoonHighlight = Self.assetTexture("SpoonHighlight") { SpoonArt.highlight(unit: Self.spoonAssetUnit) }
        eggShadow = Self.texture(EggArt.shadow(width: Int(140 * screenScale)))
        raindrops = (1 ... 4)
            .map { Self.texture(EffectArt.raindrop(diameter: Int(20 * screenScale), seed: UInt64($0))) }
        streak = Self.texture(EffectArt.streak(length: Int(46 * screenScale)))
        leaf = Self.texture(EffectArt.leaf(length: Int(26 * screenScale), seed: 11))
    }

    func egg(_ appearance: EggAppearance, widthPixels: Int) -> SKTexture {
        let key = EggKey(appearance: appearance, width: widthPixels)
        if let cached = eggs[key] {
            return cached
        }
        let texture = Self.texture(Self.cachedImage(name: "egg", key: key) {
            EggArt.egg(appearance, width: widthPixels)
        })
        Self.keep(texture, for: key, in: &eggs)
        return texture
    }

    func brokenEgg(_ appearance: EggAppearance, widthPixels: Int) -> SKTexture {
        let key = EggKey(appearance: appearance, width: widthPixels)
        if let cached = brokenEggs[key] {
            return cached
        }
        let texture = Self.texture(Self.cachedImage(name: "broken", key: key) {
            EggArt.broken(appearance, width: widthPixels)
        })
        Self.keep(texture, for: key, in: &brokenEggs)
        return texture
    }

    /// Stores a skin's texture and drops those of other skins: only the equipped skin is played, and this object lives
    /// as long as the app.
    private static func keep(_ texture: SKTexture, for key: EggKey, in cache: inout [EggKey: SKTexture]) {
        cache = cache.filter { $0.key.appearance == key.appearance }
        cache[key] = texture
    }

    // MARK: Conversion

    /// Wraps premultiplied RGBA8 sRGB bytes in a `CGImage`; usable from any thread.
    nonisolated static func cgImage(_ image: PixelImage) -> CGImage? {
        guard image.width > 0, image.height > 0,
              let provider = CGDataProvider(data: Data(image.rgba) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        return CGImage(
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: image.width * 4,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    static func texture(_ image: PixelImage) -> SKTexture {
        guard let cgImage = cgImage(image) else {
            logger.error("Empty pixel image \(image.width)x\(image.height)")
            return SKTexture()
        }
        return SKTexture(cgImage: cgImage)
    }

    /// The pre-rendered image from the asset catalog, or a runtime render if it is missing (e.g. before `make art`).
    private static func assetTexture(_ name: String, render: () -> PixelImage) -> SKTexture {
        if UIImage(named: name) != nil {
            return SKTexture(imageNamed: name)
        }
        logger.error("Missing asset \(name); rendering it at runtime")
        return texture(render())
    }

    // MARK: Disk cache

    /// Rendered eggs are kept in Caches, keyed by everything that affects their pixels.
    private static func cachedImage(name: String, key: EggKey, render: () -> PixelImage) -> PixelImage {
        let url = cacheURL(name: name, key: key)
        if let url, let data = try? Data(contentsOf: url), let image = decodePNG(data) {
            return image
        }
        let image = render()
        if let url, let cgImage = cgImage(image) {
            writePNG(cgImage, to: url)
        }
        return image
    }

    private static func cacheURL(name: String, key: EggKey) -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
              let encoded = try? JSONEncoder().encode(key.appearance)
        else { return nil }
        // FNV-1a over the appearance's JSON: stable across launches, unlike `hashValue`.
        var digest: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in encoded {
            digest = (digest ^ UInt64(byte)) &* 0x100_0000_01B3
        }
        let directory = caches.appendingPathComponent("EggArt-v\(cacheVersion)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(name)-\(key.width)-\(String(digest, radix: 16)).png")
    }

    /// Bump when a renderer changes so cached PNGs are rendered again.
    private static let cacheVersion = 2

    private static func writePNG(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    private static func decodePNG(_ data: Data) -> PixelImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return drawn ? PixelImage(width: image.width, height: image.height, rgba: bytes) : nil
    }
}
