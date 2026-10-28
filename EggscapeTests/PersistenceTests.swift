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
        #expect(settings.background == .white)
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
        settings.background = .camera
        settings.hasSeenTutorial = true
        settings.calibrationZero = SIMD2(0.1, -0.6)

        let relaunched = SettingsStore(defaults: defaults)
        #expect(!relaunched.isSoundOn)
        #expect(!relaunched.isHapticsOn)
        #expect(relaunched.sensitivity == 1.2)
        #expect(relaunched.playerName == "Julius")
        #expect(relaunched.background == .camera)
        #expect(relaunched.hasSeenTutorial)
        #expect(relaunched.calibrationZero == SIMD2(0.1, -0.6))
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

    @Test func resetRestoresDefaults() {
        let defaults = makeDefaults()
        let settings = SettingsStore(defaults: defaults)
        settings.isSoundOn = false
        settings.playerName = "Julius"
        settings.calibrationZero = SIMD2(0.2, 0.2)
        settings.reset()
        #expect(settings.isSoundOn)
        #expect(settings.playerName.isEmpty)
        #expect(settings.calibrationZero == nil)
        let relaunched = SettingsStore(defaults: defaults)
        #expect(relaunched.isSoundOn)
        #expect(relaunched.playerName.isEmpty)
    }
}

@MainActor
struct RecordsStoreTests {
    @Test func keepsTheFastestTimePerDistanceAndWeather() {
        let defaults = makeDefaults()
        let records = RecordsStore(defaults: defaults)
        #expect(records.recordTime(55.2, distance: .short, weather: .off))
        #expect(!records.recordTime(57, distance: .short, weather: .off))
        #expect(records.recordTime(51.9, distance: .short, weather: .off))
        #expect(records.recordTime(70, distance: .short, weather: .fixed(.storm)))
        #expect(records.bestTime(distance: .short, weather: .off) == 51.9)
        #expect(records.bestTime(distance: .short, weather: .fixed(.storm)) == 70)
        #expect(records.bestTime(distance: .medium, weather: .off) == nil)

        let relaunched = RecordsStore(defaults: defaults)
        #expect(relaunched.bestTime(distance: .short, weather: .off) == 51.9)
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
        records.recordTime(60, distance: .medium, weather: .off)
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
        session.finishTurn(with: outcome(finished: false, time: 30, meters: 80))
        session.finishTurn(with: outcome(finished: true, time: 55, meters: 150))
        session.finishTurn(with: outcome(finished: false, time: 40, meters: 120))
        session.finishTurn(with: outcome(finished: true, time: 52, meters: 150))
        #expect(session.ranking.map(\.name) == ["D", "B", "C", "A"])
        if case .standings = session.stage {} else {
            Issue.record("expected the standings after the last turn")
        }
    }
}
