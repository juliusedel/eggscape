@testable import EggscapeCore
import Foundation
import Testing

/// An exponentially distributed delay, the classic model of time spent waiting in network queues.
private func queueing(mean: Double, _ rng: inout SplitMix64) -> Double {
    -mean * log(1 - rng.nextUnit())
}

/// `value` exists and lies within `tolerance` of `expected`.
private func isClose(_ value: Double?, to expected: Double, tolerance: Double = 1e-9) -> Bool {
    guard let value else {
        return false
    }
    return abs(value - expected) < tolerance
}

struct ClockSyncTests {
    @Test func symmetricRoundTripGivesTheExactOffset() {
        var clock = ClockSync()
        // Pinged at 10 s, 20 ms each way, and the host's clock is 1000 s ahead.
        let recorded = clock.record(pingSentAt: 10, hostTime: 1010.02, receivedAt: 10.04)
        #expect(recorded)
        #expect(isClose(clock.offset, to: 1000))
        #expect(isClose(clock.rtt, to: 0.04))
        #expect(clock.sampleCount == 1)
    }

    @Test func lopsidedRoundTripIsOffByHalfTheDifference() {
        // 30 ms there and 10 ms back: assuming 20 ms each way puts the estimate 10 ms off, which is why ClockSync
        // trusts fast round trips most.
        var clock = ClockSync()
        clock.record(pingSentAt: 10, hostTime: 1010.03, receivedAt: 10.04)
        #expect(isClose(clock.offset, to: 1000.01))
    }

    @Test func convertsBetweenTheClocks() throws {
        var clock = ClockSync()
        #expect(clock.hostTime(fromLocal: 5) == nil)
        #expect(clock.localTime(fromHost: 5) == nil)
        clock.record(pingSentAt: 10, hostTime: 1010.02, receivedAt: 10.04)
        let startAt = try #require(clock.hostTime(fromLocal: 12))
        #expect(isClose(startAt, to: 1012))
        #expect(isClose(clock.localTime(fromHost: startAt), to: 12))
    }

    @Test func convergesDespiteJitterAndStalls() {
        var rng = SplitMix64(seed: 2026)
        var clock = ClockSync()
        let trueOffset = 4321.123
        var naiveSum = 0.0
        let pings = 40
        for index in 0 ..< pings {
            let sentAt = 100 + Double(index) * 0.5
            // Wi-Fi-like: a few milliseconds of base latency plus queueing, a busier uplink than downlink, and now and
            // then a stall of a few hundred milliseconds.
            let up = 0.003 + queueing(mean: 0.020, &rng) + (rng.chance(0.15) ? rng.uniform(0.05 ... 0.3) : 0)
            let down = 0.003 + queueing(mean: 0.006, &rng)
            let hostTime = sentAt + up + trueOffset
            let receivedAt = sentAt + up + down
            let recorded = clock.record(pingSentAt: sentAt, hostTime: hostTime, receivedAt: receivedAt)
            #expect(recorded)
            naiveSum += hostTime - (sentAt + (receivedAt - sentAt) / 2)
        }
        #expect(isClose(clock.offset, to: trueOffset, tolerance: 0.005))
        // The jitter matters: the average over all round trips is far off.
        #expect(!isClose(naiveSum / Double(pings), to: trueOffset, tolerance: 0.01))
        #expect(clock.sampleCount == pings)
    }

    @Test func followsADriftingHostClock() {
        // The host's crystal runs 40 ppm fast, which adds up to 24 ms over ten minutes of lobbies and races.
        var rng = SplitMix64(seed: 99)
        var clock = ClockSync()
        let hostClock = { (local: Double) in 500 + local * (1 + 40e-6) }
        var local = 0.0
        while local < 600 {
            let up = 0.004 + queueing(mean: 0.010, &rng)
            let down = 0.004 + queueing(mean: 0.010, &rng)
            clock.record(pingSentAt: local, hostTime: hostClock(local + up), receivedAt: local + up + down)
            local += 0.5
        }
        #expect(clock.sampleCount == clock.maxSamples)
        #expect(isClose(clock.hostTime(fromLocal: local), to: hostClock(local), tolerance: 0.005))
    }

    @Test func oldRoundTripsAgeOut() {
        var clock = ClockSync(maxSamples: 4, bestSamples: 2)
        for index in 0 ..< 4 {
            let sentAt = Double(index)
            clock.record(pingSentAt: sentAt, hostTime: sentAt + 0.001 + 10, receivedAt: sentAt + 0.002)
        }
        #expect(isClose(clock.offset, to: 10))
        // Once out of the window a round trip no longer counts, however fast it was.
        for index in 4 ..< 8 {
            let sentAt = Double(index)
            clock.record(pingSentAt: sentAt, hostTime: sentAt + 0.01 + 20, receivedAt: sentAt + 0.02)
        }
        #expect(isClose(clock.offset, to: 20))
        #expect(clock.sampleCount == 4)
    }

    @Test func medianIgnoresAFastButLopsidedRoundTrip() {
        var clock = ClockSync()
        // 23 honest round trips of 10 or 12 ms; with 24 kept, the estimate uses the median of the fastest three.
        for index in 0 ..< 23 {
            let sentAt = Double(index)
            let leg = index.isMultiple(of: 2) ? 0.005 : 0.006
            clock.record(pingSentAt: sentAt, hostTime: sentAt + leg + 100, receivedAt: sentAt + 2 * leg)
        }
        // The fastest round trip of all, 8 ms, but all of it on the way back: alone it would be 4 ms off.
        clock.record(pingSentAt: 30, hostTime: 30 + 100, receivedAt: 30.008)
        #expect(isClose(clock.offset, to: 100))
        #expect(isClose(clock.rtt, to: 0.01))
    }

    @Test func fewRoundTripsTrustTheFastest() {
        var clock = ClockSync()
        clock.record(pingSentAt: 0, hostTime: 0.150 + 50, receivedAt: 0.200)
        clock.record(pingSentAt: 1, hostTime: 1.002 + 50, receivedAt: 1.004)
        clock.record(pingSentAt: 2, hostTime: 2.090 + 50, receivedAt: 2.120)
        #expect(isClose(clock.offset, to: 50))
        #expect(isClose(clock.rtt, to: 0.004))
    }

    @Test func ignoresImpossibleRoundTrips() {
        var clock = ClockSync()
        let recorded = [
            // The pong arrived before the ping left.
            clock.record(pingSentAt: 10, hostTime: 1000, receivedAt: 9.9),
            clock.record(pingSentAt: .nan, hostTime: 1000, receivedAt: 10),
            clock.record(pingSentAt: 10, hostTime: .infinity, receivedAt: 10.1),
            clock.record(pingSentAt: 10, hostTime: 1000, receivedAt: .infinity),
        ]
        #expect(recorded == [false, false, false, false])
        #expect(clock.sampleCount == 0)
        #expect(clock.offset == nil)
    }

    @Test func pingAndPongCarryTheTimestamps() throws {
        var clock = ClockSync()
        let first = clock.makePing(localNow: 10)
        let second = clock.makePing(localNow: 10.5)
        #expect(first == .ping(id: 0, sentAt: 10))
        #expect(second == .ping(id: 1, sentAt: 10.5))

        let pong = try #require(ClockSync.reply(to: first, hostTime: 1010.02))
        #expect(pong == .pong(id: 0, pingSentAt: 10, hostTime: 1010.02))
        #expect(ClockSync.reply(to: .ready(true), hostTime: 1) == nil)

        let usedReady = clock.receive(.ready(true), receivedAt: 11)
        let usedPong = clock.receive(pong, receivedAt: 10.04)
        #expect(!usedReady)
        #expect(usedPong)
        #expect(isClose(clock.offset, to: 1000))
    }

    @Test func resetForgetsEverything() {
        var clock = ClockSync()
        clock.record(pingSentAt: 10, hostTime: 1010.02, receivedAt: 10.04)
        clock.reset()
        #expect(clock.offset == nil)
        #expect(clock.rtt == nil)
        #expect(clock.sampleCount == 0)
        #expect(clock.localTime(fromHost: 1) == nil)
    }
}
