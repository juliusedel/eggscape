@testable import EggscapeCore
import Foundation
import Testing

/// What a clean, finished 150 m time trial in calm weather pays: the yardstick for the skin prices.
let oneRunReward = CoinRewards.reward(for: RewardInput(
    course: .timeTrial(.short),
    weather: .off,
    finished: true,
    meters: 150,
    eggsLost: 0
)).total

struct SkinCatalogTests {
    @Test func idsAreStableAndInDisplayOrder() {
        // Wallets store these ids, so a renamed id takes the skin away from its owners: append, never change.
        #expect(SkinCatalog.all.map(\.id) == [
            "classic-white", "farm-brown", "quail",
            "sky-blue", "lemon-yellow", "rose", "mint", "orange", "lilac",
            "polka-dots", "navy-stripes", "zigzag", "dip-dye", "confetti", "marble",
            "starry-night", "pearl-white", "silver-metallic", "gold-metallic", "rainbow-stripes",
        ])
    }

    @Test func seedsAreStable() {
        // The seed pins the natural irregularities of an egg that players may have bought.
        let seeds = Dictionary(
            SkinCatalog.all.map { ($0.id, $0.appearance.seed) },
            uniquingKeysWith: { first, _ in first }
        )
        #expect(seeds == [
            "classic-white": 0x1864_ABD3_D0E4_0B42,
            "farm-brown": 0x1C1B_04FB_02B2_BC5F,
            "quail": 0xC782_8900_DE8D_F473,
            "sky-blue": 0xDF79_1C7A_27AA_6200,
            "lemon-yellow": 0x6833_E16C_0625_998E,
            "rose": 0xA62B_C3DE_072B_A3C0,
            "mint": 0xAAB0_2DED_AF74_0502,
            "orange": 0x85AA_6824_4C7C_F7BB,
            "lilac": 0xC040_51A0_5376_23A6,
            "polka-dots": 0xD42A_E514_F195_108B,
            "navy-stripes": 0x3BFF_197D_7BDF_8A83,
            "zigzag": 0x24D5_C4D5_6188_4B15,
            "dip-dye": 0xF21B_6999_8BE0_1EBD,
            "confetti": 0x2AAD_6F8E_B22D_3D54,
            "marble": 0xC231_2970_CC3D_544D,
            "starry-night": 0xADB8_F6BA_5007_48BC,
            "pearl-white": 0x6193_1E61_B295_0968,
            "silver-metallic": 0x7E6F_CECB_825D_FAC0,
            "gold-metallic": 0x24BC_B617_E7BD_7D5D,
            "rainbow-stripes": 0xC96F_339D_8F78_E63E,
        ])
    }

    @Test func idsAndSeedsAreUnique() {
        let skins = SkinCatalog.all
        #expect(Set(skins.map(\.id)).count == skins.count)
        #expect(Set(skins.map(\.appearance.seed)).count == skins.count)
    }

    @Test func idsAreLowercaseWordsWithHyphens() {
        for skin in SkinCatalog.all {
            let isPlain = skin.id.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }
            #expect(isPlain && !skin.id.hasPrefix("-") && !skin.id.hasSuffix("-"), "\(skin.id)")
        }
    }

    @Test func onlyTheClassicWhiteEggIsFree() {
        #expect(SkinCatalog.all.filter(\.isFree).map(\.id) == ["classic-white"])
        #expect(SkinCatalog.freeSkinIDs == ["classic-white"])
        #expect(SkinCatalog.classicWhite.tier == .common)
    }

    @Test func pricesMatchTiers() {
        for skin in SkinCatalog.all where !skin.isFree {
            #expect(skin.tier.priceRange.contains(skin.price), "\(skin.id) costs \(skin.price)")
        }
        #expect(SkinCatalog.all.allSatisfy { $0.price >= 0 })
        // Every tier is on sale.
        #expect(Set(SkinCatalog.all.map(\.tier)) == Set(EggSkin.Tier.allCases))
    }

    @Test func tiersAscendWithoutOverlap() {
        let tiers = EggSkin.Tier.allCases
        for (lower, higher) in zip(tiers, tiers.dropFirst()) {
            #expect(lower < higher)
            #expect(lower.priceRange.upperBound < higher.priceRange.lowerBound)
        }
    }

    @Test func pricesClimbExponentiallyAlongTheDisplayOrder() throws {
        let ladder = SkinCatalog.all.dropFirst()
        for (cheaper, dearer) in zip(ladder, ladder.dropFirst()) {
            let step = Double(dearer.price) / Double(cheaper.price)
            #expect(cheaper.price < dearer.price, "\(dearer.id) costs \(dearer.price)")
            #expect((1.2 ... 1.4).contains(step), "\(cheaper.id) → \(dearer.id) is ×\(step)")
            // The tier bands follow the ladder, so a higher tier never comes before a lower one.
            #expect(cheaper.tier <= dearer.tier, "\(dearer.id)")
        }
        // About ×1.3 per egg on average.
        let first = try #require(ladder.first)
        let last = try #require(ladder.last)
        let growth = pow(Double(last.price) / Double(first.price), 1 / Double(ladder.count - 1))
        #expect((1.25 ... 1.35).contains(growth), "×\(growth) per egg")
    }

    @Test func pricesAreFriendlyNumbers() {
        for skin in SkinCatalog.all {
            // Steps of 5 below 100 coins, of 10 below 1,000 and of 100 above.
            let step = skin.price < 100 ? 5 : skin.price < 1000 ? 10 : 100
            #expect(skin.price.isMultiple(of: step), "\(skin.id) costs \(skin.price)")
        }
    }

    @Test func theBrownEggCostsAboutOneRun() {
        // The first egg to unlock is about one run away, and no egg is cheaper.
        let price = Double(SkinCatalog.farmBrown.price)
        #expect(abs(price - Double(oneRunReward)) <= 0.2 * Double(oneRunReward), "\(price) vs \(oneRunReward)")
        #expect(SkinCatalog.all.filter { !$0.isFree }.map(\.price).min() == SkinCatalog.farmBrown.price)
    }

    @Test func theLastEggIsTheDearestAtAboutSixThousand() {
        let prices = SkinCatalog.all.map(\.price)
        #expect(prices.last == prices.max())
        #expect((5500 ... 6500).contains(prices.last ?? 0))
    }

    @Test func everyPatternAndFinishIsSold() {
        let appearances = SkinCatalog.all.map(\.appearance)
        #expect(Set(appearances.map(\.pattern.kind)) == Set(EggAppearance.Pattern.Kind.allCases))
        #expect(Set(appearances.map(\.finish)) == Set(EggAppearance.Finish.allCases))
    }

    @Test func patternParametersAreInRange() {
        for skin in SkinCatalog.all {
            switch skin.appearance.pattern {
            case let .speckles(_, density, size):
                #expect((0 ... 1).contains(density) && (0 ... 1).contains(size), "\(skin.id)")
            case let .dots(_, size):
                #expect((0 ... 1).contains(size), "\(skin.id)")
            case let .stripes(colors), let .confetti(colors):
                #expect(colors.count >= 2, "\(skin.id)")
            case .plain, .zigzag, .marble, .dipDye, .stars:
                break
            }
        }
    }

    @Test func theWhiteAndBrownEggsLookNatural() {
        let white = SkinCatalog.classicWhite.appearance
        #expect(white.pattern == .plain)
        #expect(white.finish == .matte)
        // Nearly white with a faint warm tint: a little more red than blue.
        #expect(min(white.base.red, white.base.green, white.base.blue) > 0.85)
        #expect(white.base.red > white.base.blue && white.base.red - white.base.blue < 0.1)

        let brown = SkinCatalog.farmBrown.appearance
        #expect(brown.base == EggAppearance.Color(hex: 0xC8804E))
        #expect(brown.finish == .matte)
        guard case let .speckles(speckle, _, size) = brown.pattern else {
            Issue.record("farm brown should be speckled, is \(brown.pattern)")
            return
        }
        // Fine speckles, darker than the shell.
        #expect(size < 0.3)
        #expect(speckle.red < brown.base.red && speckle.green < brown.base.green && speckle.blue < brown.base.blue)
    }

    @Test func dyedSkinsAreSatinSolids() {
        let dyed = [
            SkinCatalog.skyBlue, SkinCatalog.lemonYellow, SkinCatalog.rose,
            SkinCatalog.mint, SkinCatalog.orange, SkinCatalog.lilac,
        ]
        for skin in dyed {
            #expect(skin.appearance.pattern == .plain, "\(skin.id)")
            #expect(skin.appearance.finish == .satin, "\(skin.id)")
            #expect(skin.tier == .common, "\(skin.id)")
        }
    }

    @Test func specialFinishes() {
        #expect(SkinCatalog.pearlWhite.appearance.finish == .pearl)
        #expect(SkinCatalog.silverMetallic.appearance.finish == .metallic)
        #expect(SkinCatalog.goldMetallic.appearance.finish == .metallic)
        #expect(SkinCatalog.goldMetallic.tier == .legendary)
        #expect(SkinCatalog.rainbowStripes.appearance.finish == .glossy)
        #expect(SkinCatalog.rainbowStripes.appearance.pattern.kind == .stripes)
        #expect(SkinCatalog.rainbowStripes.tier == .legendary)
    }

    @Test func lookUpByID() {
        for skin in SkinCatalog.all {
            #expect(SkinCatalog.skin(id: skin.id) == skin)
        }
        #expect(SkinCatalog.skin(id: "unicorn") == nil)
        #expect(SkinCatalog.skin(id: "") == nil)
        #expect(SkinCatalog.skin(id: "Classic-White") == nil)
    }

    @Test func defaultSkinIsTheFreeClassicWhite() {
        #expect(SkinCatalog.defaultSkinID == "classic-white")
        #expect(SkinCatalog.defaultSkin == SkinCatalog.classicWhite)
        #expect(SkinCatalog.defaultSkin.isFree)
    }

    @Test func skinsSurviveCodable() throws {
        let data = try JSONEncoder().encode(SkinCatalog.all)
        #expect(try JSONDecoder().decode([EggSkin].self, from: data) == SkinCatalog.all)
    }
}
