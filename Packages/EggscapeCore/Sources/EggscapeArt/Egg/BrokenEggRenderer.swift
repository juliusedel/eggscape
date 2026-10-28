import EggscapeCore
import Foundation

enum BrokenEggRenderer {
    static func render(_: EggAppearance, width: Int) -> PixelImage {
        PixelImage(width: max(width, 1), height: max(Int((Double(width) * 0.8).rounded()), 1))
    }
}
