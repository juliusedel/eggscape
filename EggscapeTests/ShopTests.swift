@testable import Eggscape
import EggscapeCore
import Foundation
import Testing

@MainActor
struct ShopTests {
    /// Services on a fresh, isolated defaults domain, silent.
    private func makeServices() -> AppServices {
        let suite = "eggscape.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let services = AppServices(
            settings: SettingsStore(defaults: defaults),
            records: RecordsStore(defaults: defaults),
            wallet: WalletStore(defaults: defaults)
        )
        services.settings.isSoundOn = false
        services.settings.isHapticsOn = false
        return services
    }

    @Test func aNewPlayerUnlocksTheBrownEggWithOneCleanRun() throws {
        let services = makeServices()
        let wallet = services.wallet
        let brown = SkinCatalog.farmBrown
        #expect(!wallet.owns(brown))
        #expect(wallet.coinsMissing(for: brown) == brown.price)
        #expect(throws: WalletError.notOwned) { try wallet.equip(brown) }

        // The first clean long run in calm weather pays the brown egg's 55 coins; as the first finish over 100 m it is
        // a personal best, too, worth another 20. That is also enough for the quail egg after it, though not for both.
        let distance = RaceDistance.long
        let isPersonalBest = services.records.recordTime(33.6, distance: distance, weather: .off)
        #expect(isPersonalBest)
        wallet.earn(CoinRewards.reward(for: RewardInput(
            course: .timeTrial(distance),
            weather: .off,
            finished: true,
            meters: distance.meters,
            eggsLost: 0,
            isPersonalBest: isPersonalBest
        )))
        #expect(wallet.coins == 75)
        #expect(wallet.coinsMissing(for: brown) == 0)
        #expect(wallet.coinsMissing(for: SkinCatalog.quail) == 0)
        try wallet.purchase(brown)
        try wallet.equip(brown)
        #expect(wallet.equippedSkin.id == "farm-brown")
        #expect(wallet.coins == 20)
    }

    @Test func theCoinShopOpensFromAnyTab() {
        let navigation = AppNavigation()
        #expect(navigation.shopPage == .eggs)
        navigation.tab = .leaderboard
        navigation.showCoinShop()
        #expect(navigation.tab == .shop)
        #expect(navigation.shopPage == .coins)
    }

    @Test func theStagedShopMixesLockedAndUnlockedEggs() {
        let services = makeServices()
        ScreenshotStage.prepare(.shop, services: services)
        let wallet = services.wallet
        #expect(services.navigation.tab == .shop)
        #expect(services.navigation.shopPage == .eggs)
        #expect(wallet.equippedSkin.id == "polka-dots")
        #expect(wallet.owns(SkinCatalog.farmBrown))
        #expect(wallet.coins == 745)
        // The first rows of the grid show both, and further down there are eggs within reach and out of reach.
        let firstRows = SkinCatalog.all.prefix(6)
        #expect(firstRows.contains { wallet.owns($0) })
        #expect(firstRows.contains { !wallet.owns($0) })
        #expect(SkinCatalog.all.contains { !wallet.owns($0) && wallet.coinsMissing(for: $0) == 0 })
        #expect(SkinCatalog.all.contains { wallet.coinsMissing(for: $0) > 0 })
    }

    @Test func theOtherStagedScenesShowTheBoughtBrownEgg() {
        let services = makeServices()
        ScreenshotStage.prepare(.start, services: services)
        #expect(services.wallet.equippedSkin.id == "farm-brown")
        #expect(services.navigation.tab == .singleplayer)
        // The camera is the default background; the staged scenes show the studio surface.
        #expect(services.settings.background == .white)
    }

    @Test func theStagedResultsRunIsNoNewBest() throws {
        let services = makeServices()
        ScreenshotStage.prepare(.start, services: services)
        // Every scene gets the same history. The staged 100 m run does not sprint, so it is slower than 100 m at
        // running speed, and the results show the 55 coins of a clean run without the 20 for a new best.
        let best = try #require(services.records.bestTime(distance: .long, weather: .off))
        #expect(best < RaceDistance.long.meters / GameConfig.standard.runSpeed)
    }
}
