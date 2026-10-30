@testable import Eggscape
import EggscapeCore
import SpriteKit
import Testing

@MainActor
struct GameSceneTests {
    @Test func endingTheRunSkipsTheRestOfTheFrame() {
        // With a single egg the run is over as soon as it rolls off the spoon.
        var config = GameConfig.standard
        config.eggsPerRun = 1
        let scene = GameScene(
            engine: RunEngine(config: config, course: .endless, weather: .clear, localSeed: 7),
            appearance: EggAppearance(base: .init(hex: 0xF2E6D4)),
            reduceMotion: true
        )
        var framesWhileRunning = 0
        var framesAfterTheEnd = 0
        // Like `RunSession`, which ends the run while handling the events of the frame that broke the last egg.
        scene.onEvents = { [unowned scene] _ in
            if scene.engine.isOver {
                scene.mode = .ended
            }
        }
        scene.onFrame = { [unowned scene] _ in
            if scene.mode == .running {
                framesWhileRunning += 1
            } else {
                framesAfterTheEnd += 1
            }
        }
        scene.input = { RunEngine.Input(tilt: SIMD2(0.5, 0)) }
        scene.mode = .running

        for frame in 0 ..< 600 where scene.mode == .running {
            scene.update(Double(frame) / 60)
        }

        #expect(scene.mode == .ended)
        #expect(framesWhileRunning > 0)
        #expect(framesAfterTheEnd == 0)
    }

    /// The App Store screenshot of a storm (`ScreenshotStage`). Held with a fixed tilt instead, the egg falls before
    /// the capture.
    @Test func aHeldEggSurvivesTheStagedStorm() {
        let setup = RunSetup(
            mode: .timeTrial(.long, .fixed(.storm)),
            raceSeed: LaunchOptions(arguments: ["--screenshot-mode", "run-storm"]).raceSeed()
        )
        let scene = GameScene(
            engine: RunEngine(course: setup.course, weather: setup.weatherSchedule, localSeed: setup.localSeed),
            appearance: EggAppearance(base: .init(hex: 0xF2E6D4)),
            reduceMotion: true
        )
        scene.holdEgg(at: SIMD2(0.22, -0.08))
        scene.mode = .running
        // The 14 seconds it skips, and the moments until the capture, still well short of the 100 m.
        scene.fastForward(seconds: 22)
        #expect(scene.engine.eggsLost == 0)
        #expect(scene.engine.phase == .running)
    }

    @Test func vignetteIsRenderedOncePerSizeAtASixteenthOfIt() {
        let size = CGSize(width: 402, height: 874)
        let texture = GameScene.vignette(size: size)
        #expect(texture.size() == CGSize(width: 26, height: 55))
        #expect(GameScene.vignette(size: size) === texture)
    }
}
