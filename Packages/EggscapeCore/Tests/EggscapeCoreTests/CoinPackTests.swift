@testable import EggscapeCore
import Foundation
import Testing

struct CoinPackTests {
    @Test func productIDsMatchAppStoreConnect() {
        #expect(CoinPack.productIDs == [
            "de.juliusedel.eggscape.coins.small",
            "de.juliusedel.eggscape.coins.medium",
            "de.juliusedel.eggscape.coins.large",
        ])
        #expect(Set(CoinPack.productIDs).count == CoinPack.all.count)
        #expect(CoinPack.all.map(\.id) == CoinPack.productIDs)
    }

    @Test func amounts() {
        #expect(CoinPack.all.map(\.coins) == [600, 2000, 5000])
        #expect(CoinPack.small.coins == 600)
        #expect(CoinPack.medium.coins == 2000)
        #expect(CoinPack.large.coins == 5000)
    }

    @Test func lookUpByProductID() {
        for pack in CoinPack.all {
            #expect(CoinPack.pack(productID: pack.productID) == pack)
        }
        #expect(CoinPack.pack(productID: "de.juliusedel.eggscape.coins.huge") == nil)
        #expect(CoinPack.pack(productID: "") == nil)
    }

    @Test func packsAreSizedAgainstSkinPrices() {
        let prices = { (tier: EggSkin.Tier) in SkinCatalog.all.filter { $0.tier == tier }.map(\.price) }
        // The small pack buys any common egg, the medium one any rare egg, the large one any egg but the last.
        #expect(prices(.common).allSatisfy { $0 <= CoinPack.small.coins })
        #expect(prices(.rare).allSatisfy { $0 <= CoinPack.medium.coins })
        #expect(SkinCatalog.all.dropLast().allSatisfy { $0.price <= CoinPack.large.coins })
    }

    @Test func theDearestEggTakesTheLargePackPlusSomePlay() {
        let dearest = SkinCatalog.all.map(\.price).max() ?? 0
        #expect(dearest > CoinPack.large.coins)
        // On top of the pack, 1,000 coins: about two dozen clean long runs in calm weather (36 short ones).
        let cleanLongRun = CoinRewards.reward(for: RewardInput(
            course: .timeTrial(.long),
            weather: .off,
            finished: true,
            meters: RaceDistance.long.meters,
            eggsLost: 0
        )).total
        #expect(dearest - CoinPack.large.coins <= 24 * cleanLongRun, "\(dearest) coins")
    }

    @Test func theBestValueIsTheMostCoinsForTheMoney() {
        // The suggested App Store prices: 0.99, 2.99 and 5.99.
        let appStore: [String: Decimal] = [
            CoinPack.small.productID: Decimal(99) / 100,
            CoinPack.medium.productID: Decimal(299) / 100,
            CoinPack.large.productID: Decimal(599) / 100,
        ]
        #expect(CoinPack.bestValue(prices: appStore) == .large)
        // Another storefront may price the packs so that the medium one is the deal.
        let other: [String: Decimal] = [
            CoinPack.small.productID: 1,
            CoinPack.medium.productID: 2,
            CoinPack.large.productID: 9,
        ]
        #expect(CoinPack.bestValue(prices: other) == .medium)
    }

    @Test func aTieGoesToTheBiggerPack() {
        let prices: [String: Decimal] = [
            CoinPack.small.productID: 1,
            CoinPack.medium.productID: 2,
            CoinPack.large.productID: 5,
        ]
        #expect(CoinPack.bestValue(prices: prices) == .large)
    }

    @Test func aBestValueNeedsTwoPricedPacks() {
        #expect(CoinPack.bestValue(prices: [:]) == nil)
        #expect(CoinPack.bestValue(prices: [CoinPack.small.productID: 1]) == nil)
        // Unknown products and prices that are not positive do not count.
        #expect(CoinPack.bestValue(prices: [
            CoinPack.small.productID: 1,
            CoinPack.medium.productID: 0,
            CoinPack.large.productID: -5,
            "de.juliusedel.eggscape.coins.huge": Decimal(1) / 100,
        ]) == nil)
        #expect(CoinPack.bestValue(prices: [CoinPack.medium.productID: 0, CoinPack.large.productID: 6]) == nil)
    }
}
