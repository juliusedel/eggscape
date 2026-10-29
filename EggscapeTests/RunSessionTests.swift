@testable import Eggscape
import EggscapeCore
import Foundation
import Testing

@MainActor
struct RunSessionTests {
    /// A short time trial on fresh data, silent and without records or coins.
    private func makeSession(race: RaceHooks? = nil) -> RunSession {
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
        return RunSession(
            setup: RunSetup(mode: .timeTrial(.short, .off), raceSeed: 0xE665_CA9E),
            services: services,
            rules: race == nil ? .hotSeat : .race,
            race: race
        )
    }

    @Test func theFirstCountdownLetsTheEggWarmUp() {
        let session = makeSession()
        defer { session.stop() }
        session.calibrate()
        #expect(session.scene.mode == .warmUp)
    }

    @Test func theCountdownAfterAPauseKeepsTheEggWhereItWas() {
        let session = makeSession()
        defer { session.stop() }
        session.stageForScreenshot(skipping: 5, egg: .zero)
        session.pause()
        #expect(session.phase == .paused)
        session.resume()
        // Warming up would rescue an egg that was just rolling over the rim.
        #expect(session.scene.mode == .paused)
    }

    @Test func backFromARecalibrationIsThePauseMenu() {
        let session = makeSession()
        defer { session.stop() }
        session.stageForScreenshot(skipping: 5, egg: .zero)
        session.pause()
        session.recalibrate()
        #expect(session.phase == .calibrating)
        #expect(session.isRecalibrating)
        session.cancelRecalibration()
        #expect(session.phase == .paused)
        #expect(session.scene.mode == .paused)
        #expect(!session.isRecalibrating)
        #expect(!session.hasEnded)
    }

    @Test func aRecalibrationCountsDownWithoutWarmingUp() {
        let session = makeSession()
        defer { session.stop() }
        session.stageForScreenshot(skipping: 5, egg: .zero)
        session.pause()
        session.recalibrate()
        session.calibrate()
        #expect(!session.isRecalibrating)
        #expect(session.scene.mode == .paused)
    }

    @Test func anEndedRunStaysEnded() {
        let session = makeSession()
        defer { session.stop() }
        // Well past the finish of the 150 m course.
        session.stageForScreenshot(skipping: 90, egg: .zero)
        #expect(session.hasEnded)
        session.pause()
        session.resume()
        session.recalibrate()
        // The finish stays on screen for a moment before the results.
        #expect(session.phase == .running)
        #expect(session.scene.mode == .ended)
    }

    @Test func pausingARaceStillEndsTheSprint() {
        let session = makeSession(race: RaceHooks(
            startAt: .now + .seconds(3),
            onProgress: { _, _ in },
            onEggDropped: { _ in },
            onFinished: { _ in }
        ))
        defer { session.stop() }
        session.isSprinting = true
        session.pause()
        #expect(!session.isSprinting)
        #expect(session.phase == .countdown(3))
    }

    @Test func aPausedRunLetsTheScreenLock() {
        #expect(!RunSession.Phase.paused.keepsScreenAwake)
        #expect(RunSession.Phase.calibrating.keepsScreenAwake)
        #expect(RunSession.Phase.countdown(2).keepsScreenAwake)
        #expect(RunSession.Phase.running.keepsScreenAwake)
    }
}
