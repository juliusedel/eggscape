@testable import EggscapeArt
import EggscapeCore
import Testing

/// Checks every pixel of `image` for the premultiplied-alpha invariant: no color channel exceeds alpha.
private func isPremultiplied(_ image: PixelImage) -> Bool {
    stride(from: 0, to: image.rgba.count, by: 4).allSatisfy { index in
        let alpha = image.rgba[index + 3]
        return image.rgba[index] <= alpha && image.rgba[index + 1] <= alpha && image.rgba[index + 2] <= alpha
    }
}

struct EggArtTests {
    @Test func sameAppearanceGivesTheSameBytes() {
        let first = EggArt.egg(SkinCatalog.farmBrown.appearance, width: 64)
        let second = EggArt.egg(SkinCatalog.farmBrown.appearance, width: 64)
        #expect(first == second)
    }

    @Test func differentSkinsLookDifferent() {
        let white = EggArt.egg(SkinCatalog.classicWhite.appearance, width: 48)
        let brown = EggArt.egg(SkinCatalog.farmBrown.appearance, width: 48)
        #expect(white != brown)
    }

    @Test func sizeFollowsTheAspectRatio() {
        let image = EggArt.egg(SkinCatalog.classicWhite.appearance, width: 100)
        #expect(image.width == 100)
        #expect(image.height == Int((100 * EggArt.aspect).rounded()))
        #expect(image.rgba.count == image.width * image.height * 4)
    }

    @Test func cornersAreTransparentAndTheCenterIsOpaque() {
        let image = EggArt.egg(SkinCatalog.farmBrown.appearance, width: 80)
        #expect(image.pixel(x: 0, y: 0).alpha == 0)
        #expect(image.pixel(x: image.width - 1, y: image.height - 1).alpha == 0)
        #expect(image.pixel(x: image.width / 2, y: image.height / 2).alpha == 255)
    }

    @Test(arguments: SkinCatalog.all)
    func everySkinRendersAValidImage(skin: EggSkin) {
        let image = EggArt.egg(skin.appearance, width: 40)
        #expect(image.pixel(x: image.width / 2, y: image.height / 2).alpha == 255)
        #expect(isPremultiplied(image), "skin \(skin.id) breaks premultiplied alpha")
    }

    @Test func everyFinishRenders() {
        for finish in EggAppearance.Finish.allCases {
            let appearance = EggAppearance(base: EggAppearance.Color(hex: 0x84C3E6), finish: finish)
            let image = EggArt.egg(appearance, width: 32)
            #expect(isPremultiplied(image), "finish \(finish) breaks premultiplied alpha")
        }
    }

    @Test func shadowIsSoftAndDark() {
        let shadow = EggArt.shadow(width: 60)
        let center = shadow.pixel(x: shadow.width / 2, y: shadow.height / 2)
        #expect(center.alpha > 40)
        #expect(shadow.pixel(x: 0, y: 0).alpha == 0)
        #expect(isPremultiplied(shadow))
        // A shadow is dark: its color is never brighter than a mid gray at full alpha.
        #expect(Int(center.red) * 255 < Int(center.alpha) * 128)
    }
}
