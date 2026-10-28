@testable import EggscapeArt
import EggscapeCore
import Testing

/// No color channel may exceed alpha in a premultiplied image.
private func premultiplied(_ image: PixelImage) -> Bool {
    stride(from: 0, to: image.rgba.count, by: 4).allSatisfy { index in
        let alpha = image.rgba[index + 3]
        return image.rgba[index] <= alpha && image.rgba[index + 1] <= alpha && image.rgba[index + 2] <= alpha
    }
}

private func cornersAreTransparent(_ image: PixelImage) -> Bool {
    let corners = [(0, 0), (image.width - 1, 0), (0, image.height - 1), (image.width - 1, image.height - 1)]
    return corners.allSatisfy { image.pixel(x: $0.0, y: $0.1).alpha == 0 }
}

/// Number of pixels with at least the given alpha.
private func coveredPixels(_ image: PixelImage, alpha: UInt8 = 1) -> Int {
    stride(from: 3, to: image.rgba.count, by: 4).count { image.rgba[$0] >= alpha }
}

struct BrokenEggTests {
    @Test func sizeIsWidthByFourFifths() {
        let image = EggArt.broken(SkinCatalog.farmBrown.appearance, width: 101)
        #expect(image.width == 101)
        #expect(image.height == 81)
        #expect(image.rgba.count == 101 * 81 * 4)
    }

    @Test func sameAppearanceGivesTheSameBytes() {
        let first = EggArt.broken(SkinCatalog.farmBrown.appearance, width: 96)
        let second = EggArt.broken(SkinCatalog.farmBrown.appearance, width: 96)
        #expect(first == second)
    }

    @Test func theYolkSitsOpaqueInTheMiddleAndTheCornersAreClear() {
        let image = EggArt.broken(SkinCatalog.farmBrown.appearance, width: 120)
        #expect(cornersAreTransparent(image))
        let center = image.pixel(x: image.width / 2 - 3, y: image.height / 2)
        #expect(center.alpha == 255)
        // Deep orange-yellow: red well above blue.
        #expect(Int(center.red) > Int(center.blue) + 100)
    }

    @Test func eggWhiteIsTranslucentAroundTheYolk() {
        let image = EggArt.broken(SkinCatalog.classicWhite.appearance, width: 160)
        let translucent = stride(from: 3, to: image.rgba.count, by: 4)
            .count { image.rgba[$0] > 4 && image.rgba[$0] < 200 }
        #expect(translucent > image.width * image.height / 20)
        #expect(coveredPixels(image, alpha: 250) > image.width * image.height / 30)
    }

    @Test func seedsChangeTheLayout() {
        var other = SkinCatalog.farmBrown.appearance
        other.seed &+= 1
        #expect(EggArt.broken(SkinCatalog.farmBrown.appearance, width: 64) != EggArt.broken(other, width: 64))
    }

    @Test(arguments: SkinCatalog.all)
    func everySkinBreaksIntoAValidImage(skin: EggSkin) {
        let image = EggArt.broken(skin.appearance, width: 48)
        #expect(premultiplied(image), "skin \(skin.id) breaks premultiplied alpha")
        #expect(cornersAreTransparent(image))
    }

    @Test func tinySizesStillWork() {
        for width in [0, 1, 2, 5] {
            let image = EggArt.broken(SkinCatalog.farmBrown.appearance, width: width)
            #expect(image.width >= 1 && image.height >= 1)
            #expect(premultiplied(image))
        }
    }
}

struct EffectArtTests {
    @Test func raindropIsASquareDropWithClearCorners() {
        let image = EffectArt.raindrop(diameter: 64, seed: 3)
        #expect(image.width == 64 && image.height == 64)
        #expect(premultiplied(image))
        #expect(cornersAreTransparent(image))
        #expect(coveredPixels(image, alpha: 8) > 64 * 64 / 4)
        #expect(image == EffectArt.raindrop(diameter: 64, seed: 3))
        #expect(image != EffectArt.raindrop(diameter: 64, seed: 4))
    }

    @Test func raindropShowsADarkRimTowardsTheLightAndAHighlight() {
        let image = EffectArt.raindrop(diameter: 120, seed: 1)
        // Brightest straight color and darkest covered pixel inside the drop.
        var brightest = 0.0, darkest = 1.0
        for y in 0 ..< image.height {
            for x in 0 ..< image.width {
                let pixel = image.pixel(x: x, y: y)
                guard pixel.alpha > 60 else { continue }
                let value = Double(pixel.green) / Double(pixel.alpha)
                brightest = max(brightest, value)
                darkest = min(darkest, value)
            }
        }
        #expect(brightest > 0.9)
        #expect(darkest < 0.35)
    }

    @Test func streakIsThinTallAndClearAtItsSides() {
        let image = EffectArt.streak(length: 200)
        #expect(image.height == 200)
        #expect(image.width < 20)
        #expect(premultiplied(image))
        #expect(coveredPixels(image) > 100)
        for y in 0 ..< image.height {
            #expect(image.pixel(x: 0, y: y).alpha == 0)
            #expect(image.pixel(x: image.width - 1, y: y).alpha == 0)
        }
        #expect(image == EffectArt.streak(length: 200))
    }

    @Test func leavesVaryWithTheSeed() {
        let first = EffectArt.leaf(length: 78, seed: 1)
        #expect(first.height == 78)
        #expect(first.width > 30 && first.width < 78)
        #expect(premultiplied(first))
        #expect(cornersAreTransparent(first))
        #expect(coveredPixels(first, alpha: 255) > first.width * first.height / 5)
        #expect(first == EffectArt.leaf(length: 78, seed: 1))
        #expect(first != EffectArt.leaf(length: 78, seed: 2))
    }

    @Test func leafColorsRangeFromGreenToAutumn() {
        /// Average straight color of the opaque pixels, per seed.
        func averageHue(_ image: PixelImage) -> (red: Double, green: Double) {
            var red = 0.0, green = 0.0, count = 0.0
            for index in stride(from: 0, to: image.rgba.count, by: 4) where image.rgba[index + 3] == 255 {
                red += Double(image.rgba[index])
                green += Double(image.rgba[index + 1])
                count += 1
            }
            return (red / max(count, 1), green / max(count, 1))
        }
        let hues = (0 ..< 24).map { averageHue(EffectArt.leaf(length: 40, seed: UInt64($0))) }
        #expect(hues.contains { $0.green > $0.red + 10 }, "no green leaf among 24 seeds")
        #expect(hues.contains { $0.red > $0.green + 40 }, "no orange or brown leaf among 24 seeds")
    }

    @Test func splashSpraysDropletsAroundTheCenter() {
        let image = EffectArt.splash(diameter: 160, seed: 9)
        #expect(image.width == 160 && image.height == 160)
        #expect(premultiplied(image))
        #expect(cornersAreTransparent(image))
        #expect(coveredPixels(image, alpha: 16) > 400)
        #expect(image == EffectArt.splash(diameter: 160, seed: 9))
        #expect(image != EffectArt.splash(diameter: 160, seed: 10))
    }

    @Test func tinyEffectsStillWork() {
        for size in [0, 1, 3] {
            #expect(premultiplied(EffectArt.raindrop(diameter: size, seed: 1)))
            #expect(premultiplied(EffectArt.streak(length: size)))
            #expect(premultiplied(EffectArt.leaf(length: size, seed: 1)))
            #expect(premultiplied(EffectArt.splash(diameter: size, seed: 1)))
        }
    }
}
