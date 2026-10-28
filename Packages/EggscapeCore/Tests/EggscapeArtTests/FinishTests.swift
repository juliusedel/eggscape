@testable import EggscapeArt
import EggscapeCore
import Testing

/// Color statistics of the fully opaque pixels of an egg, in encoded sRGB (0 ... 1), which is what the eye judges.
private struct OpaqueStatistics {
    var mean: (red: Double, green: Double, blue: Double)
    /// Mean Rec. 709 luma of the encoded values.
    var luminance: Double
    /// Fraction of pixels darker than a luma of 0.2: "black" areas.
    var darkFraction: Double
    /// Mean and 99th percentile of the chroma (largest minus smallest channel).
    var chroma: Double
    var chroma99: Double

    init(_ image: PixelImage) {
        var red = 0.0, green = 0.0, blue = 0.0, luma = 0.0, dark = 0.0, chromaSum = 0.0
        var chromas: [Double] = []
        for index in stride(from: 0, to: image.rgba.count, by: 4) where image.rgba[index + 3] == 255 {
            let r = Double(image.rgba[index]) / 255
            let g = Double(image.rgba[index + 1]) / 255
            let b = Double(image.rgba[index + 2]) / 255
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
            red += r
            green += g
            blue += b
            luma += y
            dark += y < 0.2 ? 1 : 0
            let c = max(r, g, b) - min(r, g, b)
            chromaSum += c
            chromas.append(c)
        }
        let count = Double(max(chromas.count, 1))
        mean = (red / count, green / count, blue / count)
        luminance = luma / count
        darkFraction = dark / count
        chroma = chromaSum / count
        chromas.sort()
        chroma99 = chromas.isEmpty ? 0 : chromas[min(chromas.count - 1, Int(Double(chromas.count) * 0.99))]
    }
}

private func isPremultiplied(_ image: PixelImage) -> Bool {
    stride(from: 0, to: image.rgba.count, by: 4).allSatisfy { index in
        let alpha = image.rgba[index + 3]
        let premultiplied = image.rgba[index] <= alpha && image.rgba[index + 1] <= alpha
            && image.rgba[index + 2] <= alpha
        return premultiplied && (alpha > 0 || image.rgba[index] | image.rgba[index + 1] | image.rgba[index + 2] == 0)
    }
}

struct FinishTests {
    static let metals = [SkinCatalog.goldMetallic, SkinCatalog.silverMetallic]

    /// Polished metal in a white studio reflects mostly bright surroundings: no black chrome.
    @Test(arguments: metals)
    func metallicEggsAreBright(skin: EggSkin) {
        let statistics = OpaqueStatistics(EggArt.egg(skin.appearance, width: 160))
        #expect(statistics.luminance > 0.55, "\(skin.id) mean luma \(statistics.luminance)")
        // Only the thin band near the horizon may get dark.
        #expect(statistics.darkFraction < 0.02, "\(skin.id) dark fraction \(statistics.darkFraction)")
    }

    @Test func goldIsWarmAndSilverIsNeutral() {
        let gold = OpaqueStatistics(EggArt.egg(SkinCatalog.goldMetallic.appearance, width: 120)).mean
        #expect(gold.red > gold.green + 0.08)
        #expect(gold.green > gold.blue + 0.25)
        let silver = OpaqueStatistics(EggArt.egg(SkinCatalog.silverMetallic.appearance, width: 120)).mean
        #expect(abs(silver.red - silver.blue) < 0.05)
        #expect(abs(silver.red - silver.green) < 0.05)
    }

    /// Pearl is a soft white with gentle tints, never a rainbow.
    @Test func pearlStaysSubtle() {
        let statistics = OpaqueStatistics(EggArt.egg(SkinCatalog.pearlWhite.appearance, width: 160))
        #expect(statistics.luminance > 0.75)
        #expect(statistics.chroma < 0.06, "mean chroma \(statistics.chroma)")
        #expect(statistics.chroma99 < 0.14, "99th percentile chroma \(statistics.chroma99)")
    }

    /// The speckles of the brown egg are many but fine: they barely change its overall color.
    @Test func farmBrownSpecklesKeepTheOverallColor() {
        let speckled = SkinCatalog.farmBrown.appearance
        var plain = speckled
        plain.pattern = .plain
        let withImage = EggArt.egg(speckled, width: 320)
        let withoutImage = EggArt.egg(plain, width: 320)
        let darkening = 1 - OpaqueStatistics(withImage).luminance / OpaqueStatistics(withoutImage).luminance
        #expect(darkening >= 0, "speckles darken by \(darkening)")
        #expect(darkening < 0.03, "speckles darken by \(darkening)")
        // Yet they are there: a few percent of the pixels are visibly darker (the same geometry, so pixels match).
        var marked = 0, opaque = 0
        for index in stride(from: 0, to: withImage.rgba.count, by: 4)
            where withImage.rgba[index + 3] == 255 && withoutImage.rgba[index + 3] == 255
        {
            opaque += 1
            let difference = Int(withoutImage.rgba[index + 1]) - Int(withImage.rgba[index + 1])
            marked += difference > 12 ? 1 : 0
        }
        let fraction = Double(marked) / Double(max(opaque, 1))
        #expect(fraction > 0.005 && fraction < 0.12, "speckled fraction \(fraction)")
    }

    /// A navy egg with small stars stays mostly navy (the stars are decals, not the background).
    @Test func starryNightIsMostlyDark() {
        let statistics = OpaqueStatistics(EggArt.egg(SkinCatalog.starryNight.appearance, width: 160))
        #expect(statistics.luminance < 0.35, "mean luma \(statistics.luminance)")
    }

    @Test(arguments: EggAppearance.Finish.allCases)
    func everyFinishIsDeterministic(finish: EggAppearance.Finish) {
        let appearance = EggAppearance(
            base: EggAppearance.Color(hex: 0xC8804E),
            pattern: .speckles(color: EggAppearance.Color(hex: 0x7A4426), density: 0.35, size: 0.15),
            finish: finish,
            seed: 42
        )
        #expect(EggArt.egg(appearance, width: 96) == EggArt.egg(appearance, width: 96))
    }

    /// Premultiplied alpha holds for every finish, with and without a pattern, down to icon sizes.
    @Test(arguments: EggAppearance.Finish.allCases)
    func everyFinishIsPremultiplied(finish: EggAppearance.Finish) {
        let patterns: [EggAppearance.Pattern] = [
            .plain,
            .speckles(color: EggAppearance.Color(hex: 0x3A2A1E), density: 0.8, size: 0.7),
            .stripes(colors: [EggAppearance.Color(hex: 0x24406E)]),
        ]
        for pattern in patterns {
            let appearance = EggAppearance(base: EggAppearance.Color(hex: 0xD8B04C), pattern: pattern, finish: finish)
            for width in [1, 7, 64] {
                #expect(isPremultiplied(EggArt.egg(appearance, width: width)), "\(finish) \(pattern) at \(width)")
            }
        }
    }
}
