@testable import EggscapeCore
import Testing

struct EggscapeCoreTests {
    @Test func protocolVersionIsPositive() {
        #expect(EggscapeCore.protocolVersion >= 1)
    }
}
