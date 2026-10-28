@testable import EggscapeCore
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
        // The small pack covers most rare skins, the medium one any epic skin, the large one both legendary skins.
        let rare = prices(.rare)
        #expect(rare.filter { $0 <= CoinPack.small.coins }.count * 2 > rare.count)
        #expect(prices(.epic).allSatisfy { $0 <= CoinPack.medium.coins })
        #expect(prices(.legendary).reduce(0, +) <= CoinPack.large.coins)
    }
}
