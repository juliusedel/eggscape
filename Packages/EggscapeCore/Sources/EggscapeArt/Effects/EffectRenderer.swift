import Foundation

enum EffectRenderer {
    static func raindrop(diameter: Int, seed _: UInt64) -> PixelImage {
        PixelImage(width: max(diameter, 1), height: max(diameter, 1))
    }

    static func streak(length: Int) -> PixelImage {
        PixelImage(width: max(length / 12, 3), height: max(length, 1))
    }

    static func leaf(length: Int, seed _: UInt64) -> PixelImage {
        PixelImage(width: max(length * 2 / 3, 1), height: max(length, 1))
    }

    static func splash(diameter: Int, seed _: UInt64) -> PixelImage {
        PixelImage(width: max(diameter, 1), height: max(diameter, 1))
    }
}
