@testable import Eggscape
import EggscapeCore
import Foundation
import Testing

/// A fresh, isolated defaults domain per test.
private func makeDefaults() -> UserDefaults {
    let suite = "eggscape.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite) ?? .standard
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@MainActor
struct SettingsStoreTests {
    @Test func defaultsOnFirstLaunch() {
        let settings = SettingsStore(defaults: makeDefaults())
        #expect(settings.isSoundOn)
        #expect(settings.isHapticsOn)
        #expect(settings.sensitivity == 1)
        #expect(settings.playerName.isEmpty)
        #expect(settings.background == .camera)
        #expect(!settings.hasSeenTutorial)
        #expect(settings.calibrationZero == nil)
    }

    @Test func valuesSurviveARelaunch() {
        let defaults = makeDefaults()
        let settings = SettingsStore(defaults: defaults)
        settings.isSoundOn = false
        settings.isHapticsOn = false
        settings.sensitivity = 1.2
        settings.playerName = "Julius"
        settings.background = .white
        settings.hasSeenTutorial = true
        settings.calibrationZero = SIMD2(0.1, -0.6)

        let relaunched = SettingsStore(defaults: defaults)
        #expect(!relaunched.isSoundOn)
        #expect(!relaunched.isHapticsOn)
        #expect(relaunched.sensitivity == 1.2)
        #expect(relaunched.playerName == "Julius")
        #expect(relaunched.background == .white)
        #expect(relaunched.hasSeenTutorial)
        #expect(relaunched.calibrationZero == SIMD2(0.1, -0.6))
    }

    @Test func backgroundChosenInAnEarlierBuildIsKept() {
        let defaults = makeDefaults()
        // What builds with the white default stored once the player picked a background.
        defaults.set("white", forKey: "settings.background")
        #expect(SettingsStore(defaults: defaults).background == .white)
        defaults.set("camera", forKey: "settings.background")
        #expect(SettingsStore(defaults: defaults).background == .camera)
    }

    @Test func sensitivityAndNameAreLimited() {
        let defaults = makeDefaults()
        let settings = SettingsStore(defaults: defaults)
        settings.sensitivity = 3
        #expect(settings.sensitivity == 1.3)
        settings.sensitivity = 0
        #expect(settings.sensitivity == 0.7)
        settings.playerName = String(repeating: "x", count: 40)
        #expect(settings.playerName.count == SettingsStore.maxNameLength)
        #expect(SettingsStore(defaults: defaults).playerName.count == SettingsStore.maxNameLength)
    }

    @Test func displayNameFallsBackForBlankNames() {
        let settings = SettingsStore(defaults: makeDefaults())
        settings.playerName = "   "
        #expect(!settings.displayName.trimmingCharacters(in: .whitespaces).isEmpty)
        settings.playerName = " Mia "
        #expect(settings.displayName == "Mia")
    }

    @Test func typedNameIsTrimmedAndLimited() {
        let settings = SettingsStore(defaults: makeDefaults())
        settings.savePlayerName("  Mia \n")
        #expect(settings.playerName == "Mia")
        settings.savePlayerName("   ")
        #expect(settings.playerName.isEmpty)
        #expect(settings.displayName == String(localized: "Spieler"))
        settings.savePlayerName(" " + String(repeating: "x", count: 40))
        #expect(settings.playerName == String(repeating: "x", count: SettingsStore.maxNameLength))
    }

    @Test func resetRestoresDefaults() {
        let defaults = makeDefaults()
        let settings = SettingsStore(defaults: defaults)
        settings.isSoundOn = false
        settings.playerName = "Julius"
        settings.background = .white
        settings.calibrationZero = SIMD2(0.2, 0.2)
        settings.reset()
        #expect(settings.isSoundOn)
        #expect(settings.playerName.isEmpty)
        #expect(settings.background == .camera)
        #expect(settings.calibrationZero == nil)
        let relaunched = SettingsStore(defaults: defaults)
        #expect(relaunched.isSoundOn)
        #expect(relaunched.playerName.isEmpty)
        #expect(relaunched.background == .camera)
    }
}

@MainActor
struct RecordsStoreTests {
    @Test func keepsTheFastestTimePerDistanceAndWeather() {
        let defaults = makeDefaults()
        let records = RecordsStore(defaults: defaults)
        #expect(records.recordTime(5.52, distance: .short, weather: .off))
        #expect(!records.recordTime(5.7, distance: .short, weather: .off))
        #expect(records.recordTime(5.19, distance: .short, weather: .off))
        #expect(records.recordTime(7.5, distance: .short, weather: .fixed(.storm)))
        #expect(records.bestTime(distance: .short, weather: .off) == 5.19)
        #expect(records.bestTime(distance: .short, weather: .fixed(.storm)) == 7.5)
        #expect(records.bestTime(distance: .medium, weather: .off) == nil)

        let relaunched = RecordsStore(defaults: defaults)
        #expect(relaunched.bestTime(distance: .short, weather: .off) == 5.19)
    }

    @Test func timesFromTheLongerCoursesOfEarlierBuildsAreDropped() {
        let defaults = makeDefaults()
        // What builds with the 150, 300 and 600 m courses stored.
        defaults.set(["short.off": 48.7, "long.fixed-storm": 214.3], forKey: "records.bestTimes")
        defaults.set(412.0, forKey: "records.endlessMeters")

        let records = RecordsStore(defaults: defaults)
        // A 150 m time is no best for 15 m, so it neither shows up nor reaches Game Center ...
        #expect(records.bestTimes.isEmpty)
        #expect(records.bestTime(distance: .short, weather: .off) == nil)
        #expect(defaults.object(forKey: "records.bestTimes") == nil)
        // ... while Endlos did not change and keeps its record.
        #expect(records.bestEndless == 412)
        #expect(records.leaderboardScores == [LeaderboardScore(leaderboard: .endless, value: 412)])

        // The first time on the short course is a personal best again, and it is kept from now on.
        #expect(records.recordTime(6.1, distance: .short, weather: .off))
        let relaunched = RecordsStore(defaults: defaults)
        #expect(relaunched.bestTime(distance: .short, weather: .off) == 6.1)
        #expect(relaunched.bestEndless == 412)
    }

    @Test func keepsTheLongestEndlessRun() {
        let defaults = makeDefaults()
        let records = RecordsStore(defaults: defaults)
        #expect(!records.recordEndless(meters: 0))
        #expect(records.recordEndless(meters: 230))
        #expect(!records.recordEndless(meters: 120))
        #expect(RecordsStore(defaults: defaults).bestEndless == 230)
    }

    @Test func storageKeysAreStable() {
        #expect(RecordsStore.timeKey(distance: .long, weather: .fixed(.rain)) == "long.fixed-rain")
        #expect(RecordsStore.timeKey(distance: .short, weather: .random) == "short.random")
    }

    @Test func resetClearsEverything() {
        let defaults = makeDefaults()
        let records = RecordsStore(defaults: defaults)
        records.recordTime(17.4, distance: .medium, weather: .off)
        records.recordEndless(meters: 90)
        records.reset()
        #expect(records.bestTimes.isEmpty)
        #expect(records.bestEndless == nil)
        #expect(RecordsStore(defaults: defaults).bestEndless == nil)
    }
}

@MainActor
struct HotSeatRankingTests {
    private func outcome(finished: Bool, time: Double, meters: Double) -> RunOutcome {
        RunOutcome(
            mode: .timeTrial(.short, .off),
            finished: finished,
            time: time,
            meters: meters,
            eggsLost: finished ? 0 : 3,
            isPersonalBest: false
        )
    }

    @Test func finishersByTimeThenDistance() {
        let session = HotSeatSession(
            players: ["A", "B", "C", "D"],
            setup: RunSetup(mode: .timeTrial(.short, .off), raceSeed: 1)
        ) { _ in
            preconditionFailure("not started in this test")
        }
        let length = RaceDistance.short.meters
        session.finishTurn(with: outcome(finished: false, time: 3, meters: 8))
        session.finishTurn(with: outcome(finished: true, time: 5.5, meters: length))
        session.finishTurn(with: outcome(finished: false, time: 4, meters: 12))
        session.finishTurn(with: outcome(finished: true, time: 5.2, meters: length))
        #expect(session.ranking.map(\.name) == ["D", "B", "C", "A"])
        if case .standings = session.stage {} else {
            Issue.record("expected the standings after the last turn")
        }
    }
}

@MainActor
struct WalletStoreTests {
    @Test func startsWithTheFreeEggs() {
        let wallet = WalletStore(defaults: makeDefaults())
        #expect(wallet.coins == 0)
        #expect(wallet.equippedSkin.id == SkinCatalog.defaultSkinID)
        for id in SkinCatalog.freeSkinIDs {
            #expect(wallet.wallet.owns(skinID: id))
        }
    }

    @Test func purchasesAndEquipsSurviveARelaunch() throws {
        let defaults = makeDefaults()
        let wallet = WalletStore(defaults: defaults)
        wallet.earn(CoinReward(lines: [CoinReward.Line(kind: .distance, coins: 400)]))
        let skin = try #require(SkinCatalog.skin(id: "sky-blue"))
        try wallet.purchase(skin)
        try wallet.equip(skin)

        let relaunched = WalletStore(defaults: defaults)
        #expect(relaunched.coins == 400 - skin.price)
        #expect(relaunched.owns(skin))
        #expect(relaunched.equippedSkin.id == "sky-blue")
    }

    @Test func refusesSkinsThePlayerCannotAfford() throws {
        let wallet = WalletStore(defaults: makeDefaults())
        let skin = try #require(SkinCatalog.skin(id: "gold-metallic"))
        #expect(throws: WalletError.self) { try wallet.purchase(skin) }
        #expect(!wallet.owns(skin))
    }

    @Test func creditsEachCoinPackTransactionOnce() {
        let defaults = makeDefaults()
        let wallet = WalletStore(defaults: defaults)
        wallet.creditPurchase(transactionID: 42, productID: CoinPack.small.productID)
        wallet.creditPurchase(transactionID: 42, productID: CoinPack.small.productID)
        #expect(wallet.coins == CoinPack.small.coins)
        // After a relaunch the same transaction (e.g. redelivered by StoreKit) still counts only once.
        let relaunched = WalletStore(defaults: defaults)
        relaunched.creditPurchase(transactionID: 42, productID: CoinPack.small.productID)
        #expect(relaunched.coins == CoinPack.small.coins)
    }

    @Test func ignoresUnknownProducts() {
        let wallet = WalletStore(defaults: makeDefaults())
        wallet.creditPurchase(transactionID: 7, productID: "de.juliusedel.eggscape.unknown")
        #expect(wallet.coins == 0)
    }

    @Test func resetForgetsEverything() throws {
        let defaults = makeDefaults()
        let wallet = WalletStore(defaults: defaults)
        wallet.earn(CoinReward(lines: [CoinReward.Line(kind: .distance, coins: 900)]))
        try wallet.purchase(#require(SkinCatalog.skin(id: "mint")))
        wallet.reset()
        #expect(wallet.coins == 0)
        #expect(WalletStore(defaults: defaults).coins == 0)
    }
}

@MainActor
struct LeaderboardScoreSubmissionTests {
    @Test func recordsBecomeOneScorePerBoard() {
        let records = RecordsStore(defaults: makeDefaults())
        records.recordTime(5.5, distance: .short, weather: .off)
        records.recordTime(5.1, distance: .short, weather: .fixed(.wind))
        records.recordEndless(meters: 333)
        let scores = records.leaderboardScores
        #expect(scores.count == 2)
        #expect(scores.contains(LeaderboardScore(leaderboard: .shortTimeTrial, value: 510)))
        #expect(scores.contains(LeaderboardScore(leaderboard: .endless, value: 333)))
    }
}
