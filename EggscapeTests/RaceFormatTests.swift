@testable import Eggscape
import Foundation
import Testing

struct RaceFormatTests {
    private let german = Locale(identifier: "de_DE")
    private let english = Locale(identifier: "en_US")

    @Test func germanTimesUseADecimalComma() {
        #expect(RaceFormat.time(42.3, locale: german) == "0:42,3")
        #expect(RaceFormat.time(754.5, locale: german) == "12:34,5")
    }

    @Test func englishTimesUseADecimalPoint() {
        #expect(RaceFormat.time(42.3, locale: english) == "0:42.3")
        #expect(RaceFormat.time(61.25, locale: english) == "1:01.2")
    }

    @Test func timesAreRoundedDownToTenths() {
        #expect(RaceFormat.time(59.99, locale: german) == "0:59,9")
        #expect(RaceFormat.time(5.05, locale: german) == "0:05,0")
    }

    @Test func negativeTimesShowZero() {
        #expect(RaceFormat.time(-3, locale: german) == "0:00,0")
    }

    @Test func minutesGoOnPastAnHour() {
        #expect(RaceFormat.time(3725, locale: english) == "62:05.0")
    }

    /// A modified phone could send such numbers, and converting them to `Int` would trap.
    @Test func numbersNoRunReachesShowWithoutCrashing() {
        let largest = RaceFormat.time(1_000_000, locale: german)
        #expect(RaceFormat.time(1e300, locale: german) == largest)
        #expect(RaceFormat.time(.infinity, locale: german) == largest)
        for nothing in [-1, -1e300, -Double.infinity, .nan] {
            #expect(RaceFormat.time(nothing, locale: german) == "0:00,0", "\(nothing)")
        }
        #expect(RaceFormat.meters(1e300) == 1_000_000)
        #expect(RaceFormat.meters(.infinity) == 1_000_000)
        for nothing in [-1, -1e300, -Double.infinity, .nan] {
            #expect(RaceFormat.meters(nothing) == 0, "\(nothing)")
        }
        #expect(RaceFormat.meters(128.9) == 128)
    }
}
