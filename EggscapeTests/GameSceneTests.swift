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
}
