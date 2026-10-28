@testable import EggscapeCore
import Testing

struct FixedTimestepTests {
    @Test func sixtyFramesPerSecondRunTwoStepsEach() {
        var timestep = FixedTimestep(rate: 120)
        let steps = (0 ..< 60).map { _ in timestep.consume(1.0 / 60) }
        #expect(steps.allSatisfy { $0 == 2 })
    }

    @Test func oddFrameTimesAverageOut() {
        var timestep = FixedTimestep(rate: 120)
        let total = (0 ..< 1000).reduce(0) { sum, index in
            sum + timestep.consume(index.isMultiple(of: 2) ? 0.013 : 0.004)
        }
        // 1000 frames averaging 8.5 ms = 8.5 s = 1020 steps, give or take the remainder.
        #expect(abs(total - 1020) <= 1)
    }

    @Test func hitchesAreClamped() {
        var timestep = FixedTimestep(rate: 120, maxFrameDuration: 0.25)
        #expect(timestep.consume(3) == 30)
        #expect(timestep.consume(-1) == 0)
    }
}
