@testable import Eggscape
import EggscapeCore
import Foundation
import Testing

@MainActor
struct RunSessionTests {
    /// A short time trial (15 m, a little over 5 s) on fresh data, silent and without records or coins.
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
        session.stageForScreenshot(skipping: 2, egg: .zero)
        session.pause()
        #expect(session.phase == .paused)
        session.resume()
        // Warming up would rescue an egg that was just rolling over the rim.
        #expect(session.scene.mode == .paused)
    }

    @Test func backFromARecalibrationIsThePauseMenu() {
        let session = makeSession()
        defer { session.stop() }
        session.stageForScreenshot(skipping: 2, egg: .zero)
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
        session.stageForScreenshot(skipping: 2, egg: .zero)
        session.pause()
        session.recalibrate()
        session.calibrate()
        #expect(!session.isRecalibrating)
        #expect(session.scene.mode == .paused)
    }

    @Test func anEndedRunStaysEnded() {
        let session = makeSession()
        defer { session.stop() }
        // Well past the finish of the short course.
        session.stageForScreenshot(skipping: 2 * RaceDistance.short.meters / GameConfig.standard.runSpeed, egg: .zero)
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
            isReferee: false,
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

    /// App Store screenshots: a staged run is underway before its screen appears, so a capture can never find it on
    /// its calibration screen, however slowly the screen opens.
    @Test(arguments: [ScreenshotScene.sunnyRun, .rainRun, .stormRun, .results])
    func aStagedRunIsUnderwayBeforeItsScreenAppears(_ scene: ScreenshotScene) {
        let suite = "eggscape.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let services = AppServices(
            settings: SettingsStore(defaults: defaults),
            records: RecordsStore(defaults: defaults),
            wallet: WalletStore(defaults: defaults)
        )
        ScreenshotStage.prepare(scene, services: services)
        guard case let .single(flow) = services.launcher.flow else {
            Issue.record("\(scene.rawValue) started no run")
            return
        }
        defer { flow.session.stop() }
        #expect(flow.session.phase == .running)
        #expect(flow.session.hud.meters > 0)
    }

    /// App Store screenshots: a staged run stands still at its moment while the weather goes on, so a capture that
    /// comes late on a busy Mac finds neither a lightning flash nor the finish.
    @Test func aStagedRunStandsStillAtItsMoment() {
        let session = makeSession()
        defer { session.stop() }
        session.stageForScreenshot(skipping: 2, egg: .zero)
        let hud = session.hud
        let elapsed = session.scene.engine.elapsed
        // Ten seconds of frames, well past the finish of the 15 m course.
        for frame in 0 ..< 600 {
            session.scene.update(Double(frame) / 60)
        }
        #expect(session.hud == hud)
        #expect(session.scene.engine.elapsed == elapsed)
        #expect(!session.hasEnded)
        #expect(session.phase == .running)
    }

    @Test func aPausedRunLetsTheScreenLock() {
        #expect(!RunSession.Phase.paused.keepsScreenAwake)
        #expect(RunSession.Phase.calibrating.keepsScreenAwake)
        #expect(RunSession.Phase.countdown(2).keepsScreenAwake)
        #expect(RunSession.Phase.running.keepsScreenAwake)
    }
}
