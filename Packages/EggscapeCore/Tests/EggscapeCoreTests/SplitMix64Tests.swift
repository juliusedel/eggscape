@testable import EggscapeCore
import Testing

struct SplitMix64Tests {
    @Test func matchesReferenceSequence() {
        // First outputs of the reference implementation for seed 0; pins the algorithm across platforms.
        var rng = SplitMix64(seed: 0)
        #expect(rng.next() == 0xE220_A839_7B1D_CDAF)
        #expect(rng.next() == 0x6E78_9E6A_A1B9_65F4)
        #expect(rng.next() == 0x06C4_5D18_8009_454F)
    }

    @Test func helpersStayInRange() {
        var rng = SplitMix64(seed: 42)
        for _ in 0 ..< 10000 {
            let unit = rng.nextUnit()
            #expect(unit >= 0 && unit < 1)
            let value = rng.uniform(0.15 ... 0.35)
            #expect(value >= 0.15 && value <= 0.35)
            #expect((0 ..< 3).contains(rng.index(below: 3)))
            let direction = rng.direction()
            #expect(abs((direction * direction).sum() - 1) < 1e-12)
        }
    }

    @Test func streamsAreIndependentAndStable() {
        let root = SplitMix64(seed: 2024)
        var gusts = root.stream(1)
        var lightning = root.stream(2)
        var gustsAgain = root.stream(1)
        let first = (0 ..< 5).map { _ in gusts.next() }
        #expect(first == (0 ..< 5).map { _ in gustsAgain.next() })
        #expect(first != (0 ..< 5).map { _ in lightning.next() })
    }
}
