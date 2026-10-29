@testable import EggscapeCore
import Foundation
import Testing

private func wallet(coins: Int) -> Wallet {
    var wallet = Wallet()
    wallet.credit(coins: coins)
    return wallet
}

private func decode(_ json: String) throws -> Wallet {
    try JSONDecoder().decode(Wallet.self, from: Data(json.utf8))
}

struct WalletTests {
    @Test func aNewWalletHasOnlyTheClassicEggAndNoCoins() {
        let wallet = Wallet()
        #expect(wallet.coins == 0)
        #expect(wallet.ownedSkinIDs == ["classic-white"])
        #expect(!wallet.owns(skinID: "farm-brown"))
        #expect(wallet.equippedSkinID == "classic-white")
        #expect(wallet.equippedSkin == SkinCatalog.classicWhite)
        #expect(wallet.processedTransactionIDs.isEmpty)
    }

    @Test func creditAddsCoins() {
        var wallet = wallet(coins: 55)
        wallet.credit(coins: 0)
        wallet.credit(coins: CoinRewards.reward(for: RewardInput(
            course: .endless,
            weather: .off,
            finished: false,
            meters: 100,
            eggsLost: 3
        )).total)
        #expect(wallet.coins == 75)
    }

    @Test func purchaseSpendsCoinsAndAddsTheSkin() throws {
        var wallet = wallet(coins: 500)
        try wallet.purchase(skin: SkinCatalog.polkaDots)
        #expect(wallet.coins == 50)
        #expect(wallet.owns(skinID: "polka-dots"))
        // Buying does not put the skin on.
        #expect(wallet.equippedSkinID == "classic-white")
    }

    @Test func theExactPriceIsEnough() throws {
        var wallet = wallet(coins: 4800)
        try wallet.purchase(skin: SkinCatalog.goldMetallic)
        #expect(wallet.coins == 0)
        #expect(wallet.owns(skinID: "gold-metallic"))
    }

    @Test func purchaseNeedsEnoughCoins() {
        var wallet = wallet(coins: 100)
        #expect(throws: WalletError.insufficientCoins(missing: 20)) {
            try wallet.purchase(skin: SkinCatalog.lemonYellow)
        }
        #expect(wallet.coins == 100)
        #expect(!wallet.owns(skinID: "lemon-yellow"))
    }

    @Test func coinsMissingCountDownToZero() throws {
        var wallet = wallet(coins: 100)
        #expect(wallet.coinsMissing(for: SkinCatalog.lemonYellow) == 20)
        #expect(wallet.coinsMissing(for: SkinCatalog.skyBlue) == 0)
        #expect(wallet.coinsMissing(for: SkinCatalog.classicWhite) == 0)
        // The catalog's price counts, not the one a stale or hand-made skin claims.
        let bargain = EggSkin(
            id: "gold-metallic",
            appearance: SkinCatalog.goldMetallic.appearance,
            price: 1,
            tier: .common
        )
        #expect(wallet.coinsMissing(for: bargain) == 4700)

        try wallet.purchase(skin: SkinCatalog.skyBlue)
        #expect(wallet.coinsMissing(for: SkinCatalog.farmBrown) == 45)
        wallet.credit(coins: 45)
        #expect(wallet.coinsMissing(for: SkinCatalog.farmBrown) == 0)
    }

    @Test func ownedSkinsCannotBeBoughtAgain() throws {
        var wallet = wallet(coins: 1000)
        try wallet.purchase(skin: SkinCatalog.mint)
        #expect(throws: WalletError.alreadyOwned) {
            try wallet.purchase(skin: SkinCatalog.mint)
        }
        #expect(wallet.coins == 800)
        // Free skins are always owned.
        #expect(throws: WalletError.alreadyOwned) {
            try wallet.purchase(skin: SkinCatalog.classicWhite)
        }
        #expect(wallet.coins == 800)
    }

    @Test func unknownSkinsCannotBeBought() {
        var wallet = wallet(coins: 10000)
        let bootleg = EggSkin(id: "bootleg", appearance: SkinCatalog.goldMetallic.appearance, price: 1, tier: .common)
        #expect(throws: WalletError.unknownSkin) {
            try wallet.purchase(skin: bootleg)
        }
        #expect(wallet.coins == 10000)
        #expect(!wallet.owns(skinID: "bootleg"))
    }

    @Test func theCatalogSetsThePrice() throws {
        var wallet = wallet(coins: 5000)
        let bargain = EggSkin(
            id: "gold-metallic",
            appearance: SkinCatalog.goldMetallic.appearance,
            price: 1,
            tier: .common
        )
        try wallet.purchase(skin: bargain)
        #expect(wallet.coins == 200)
    }

    @Test func onlyOwnedSkinsCanBeEquipped() throws {
        var wallet = wallet(coins: 5000)
        #expect(throws: WalletError.notOwned) {
            try wallet.equip(skinID: "gold-metallic")
        }
        // The brown egg has to be unlocked like any other.
        #expect(throws: WalletError.notOwned) {
            try wallet.equip(skinID: "farm-brown")
        }
        #expect(throws: WalletError.unknownSkin) {
            try wallet.equip(skinID: "unicorn")
        }
        #expect(wallet.equippedSkinID == "classic-white")

        try wallet.purchase(skin: SkinCatalog.farmBrown)
        try wallet.equip(skinID: "farm-brown")
        #expect(wallet.equippedSkin == SkinCatalog.farmBrown)
        try wallet.purchase(skin: SkinCatalog.goldMetallic)
        try wallet.equip(skinID: "gold-metallic")
        #expect(wallet.equippedSkin == SkinCatalog.goldMetallic)
        #expect(wallet.coins == 145)
    }

    @Test func eachTransactionIsCreditedOnce() {
        var wallet = Wallet()
        let first = wallet.creditPurchase(transactionID: 2_000_000_123_456_789, coins: CoinPack.small.coins)
        // StoreKit delivers the same transaction again, e.g. after a crash before it was finished.
        let again = wallet.creditPurchase(transactionID: 2_000_000_123_456_789, coins: CoinPack.small.coins)
        #expect(first)
        #expect(!again)
        #expect(wallet.coins == 600)

        let other = wallet.creditPurchase(transactionID: 2_000_000_123_456_790, coins: CoinPack.large.coins)
        #expect(other)
        #expect(wallet.coins == 5600)
        #expect(wallet.processedTransactionIDs == [2_000_000_123_456_789, 2_000_000_123_456_790])
    }

    @Test func codableRoundTrip() throws {
        var wallet = wallet(coins: 2345)
        try wallet.purchase(skin: SkinCatalog.marble)
        try wallet.equip(skinID: "marble")
        wallet.creditPurchase(transactionID: .max, coins: CoinPack.small.coins)
        wallet.creditPurchase(transactionID: 7, coins: CoinPack.medium.coins)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(wallet)
        let decoded = try JSONDecoder().decode(Wallet.self, from: data)
        #expect(decoded == wallet)
        #expect(decoded.coins == 3245)
        #expect(decoded.equippedSkinID == "marble")
        // Sets are written sorted, so the same wallet always gives the same data.
        #expect(try encoder.encode(decoded) == data)
    }

    @Test func decodingRepairsInsteadOfFailing() throws {
        let wallet = try decode(#"{"coins": -40, "ownedSkinIDs": ["gold-metallic"], "equippedSkinID": "marble"}"#)
        #expect(wallet.coins == 0)
        // Free skins are always owned, and an equipped skin that is not owned falls back to the default.
        #expect(wallet.ownedSkinIDs == ["gold-metallic", "classic-white"])
        #expect(wallet.equippedSkinID == "classic-white")
        #expect(wallet.processedTransactionIDs.isEmpty)

        #expect(try decode("{}") == Wallet())
    }

    @Test func aBrownEggFromWhenItWasFreeIsKept() throws {
        // Earlier builds gave every player the brown egg and stored it with the owned skins.
        let wallet = try decode(#"""
        {"coins": 30, "ownedSkinIDs": ["classic-white", "farm-brown"], "equippedSkinID": "farm-brown"}
        """#)
        #expect(wallet.owns(skinID: "farm-brown"))
        #expect(wallet.equippedSkin == SkinCatalog.farmBrown)
        #expect(wallet.coins == 30)
    }

    @Test func aSkinFromANewerVersionKeepsTheEggVisible() throws {
        let wallet = try decode(#"{"ownedSkinIDs": ["future-skin"], "equippedSkinID": "future-skin"}"#)
        #expect(wallet.equippedSkinID == "future-skin")
        #expect(wallet.equippedSkin == SkinCatalog.defaultSkin)
    }

    @Test func creditSaturatesInsteadOfOverflowing() throws {
        var wallet = try decode(#"{"coins": 9223372036854775807}"#)
        wallet.credit(coins: 10)
        #expect(wallet.coins == .max)
    }
}
