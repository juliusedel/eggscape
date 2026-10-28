/// A joiner's estimate of the host's clock, so every phone starts the race at the same moment.
///
/// Each phone measures time with its own monotonic clock (for example `ProcessInfo.processInfo.systemUptime`), and
/// the clocks of two phones have unrelated zero points. Like NTP, the joiner pings the host and the host answers with
/// its clock reading. If the pong took as long as the ping, the host read its clock halfway through the round trip:
///
///     offset = hostTime − (sentAt + rtt / 2),   rtt = receivedAt − sentAt,   host clock = local clock + offset
///
/// A slow round trip most likely waited in a queue on one leg, which skews its offset by up to half the extra time,
/// while a fast one cannot be off by more than half its round trip. So the estimate is the median offset of the
/// fastest eighth of the kept round trips, at least one and at most `bestSamples`: with few round trips only the very
/// fastest is trustworthy, and with many the median of several also ignores one that was quick on one leg only. The
/// last `maxSamples` round trips are kept, because the clocks of two phones drift apart by a few hundredths of a
/// millisecond per second, which adds up over a session of several races.
///
/// Ping about twice a second while in the lobby, so the estimate is good by the time the host starts the race.
public struct ClockSync: Sendable, Equatable {
    /// One ping and its pong.
    public struct Sample: Sendable, Equatable {
        /// Round-trip time in seconds.
        public var rtt: Double
        /// Host clock minus local clock in seconds, assuming both legs took equally long.
        public var offset: Double

        public init(rtt: Double, offset: Double) {
            self.rtt = rtt
            self.offset = offset
        }
    }

    /// How many recent round trips are kept.
    public let maxSamples: Int
    /// The most round trips the estimate takes the median of.
    public let bestSamples: Int
    /// The kept round trips, oldest first.
    public private(set) var samples: [Sample] = []
    /// Host clock minus local clock in seconds; `nil` until the first pong arrived.
    public private(set) var offset: Double?
    /// The median round-trip time of the round trips behind `offset`, in seconds: the latency of a good moment, not of
    /// an unlucky one.
    public private(set) var rtt: Double?
    private var nextPingID: UInt32 = 0

    /// The defaults keep half a minute of round trips at two pings per second. They beat shorter windows and fixed
    /// medians in a simulation with Wi-Fi-like jitter (queueing delays of tens of milliseconds, the odd stall of a few
    /// hundred): after 20 round trips the error was below 0.8 ms in half of the runs and below 4 ms in 99 %, and a
    /// host clock running 40 ppm fast was followed within about 2 ms (99 %) over ten minutes.
    public init(maxSamples: Int = 64, bestSamples: Int = 5) {
        precondition(maxSamples > 0, "maxSamples must be positive")
        precondition(bestSamples > 0, "bestSamples must be positive")
        self.maxSamples = maxSamples
        self.bestSamples = min(bestSamples, maxSamples)
    }

    public var sampleCount: Int {
        samples.count
    }

    /// The next ping to send, stamped with the local clock right before sending.
    public mutating func makePing(localNow: Double) -> NetMessage {
        let id = nextPingID
        nextPingID &+= 1
        return .ping(id: id, sentAt: localNow)
    }

    /// The host's answer if `message` is a ping. The host passes its clock right before sending, so the reading is as
    /// close as possible to the middle of the round trip.
    public static func reply(to message: NetMessage, hostTime: Double) -> NetMessage? {
        guard case let .ping(id, sentAt) = message else {
            return nil
        }
        return .pong(id: id, pingSentAt: sentAt, hostTime: hostTime)
    }

    /// Adds the round trip a `pong` describes, received at `receivedAt` on the local clock; ignores other messages.
    /// - Returns: whether a round trip was added.
    @discardableResult
    public mutating func receive(_ message: NetMessage, receivedAt: Double) -> Bool {
        guard case let .pong(_, pingSentAt, hostTime) = message else {
            return false
        }
        return record(pingSentAt: pingSentAt, hostTime: hostTime, receivedAt: receivedAt)
    }

    /// Adds one round trip: the ping left at `pingSentAt` and its pong arrived at `receivedAt` (both on the local
    /// clock), carrying the host's clock reading `hostTime`.
    /// - Returns: `false` for an impossible round trip (negative or not finite), which is ignored.
    @discardableResult
    public mutating func record(pingSentAt: Double, hostTime: Double, receivedAt: Double) -> Bool {
        let rtt = receivedAt - pingSentAt
        guard rtt.isFinite, rtt >= 0, hostTime.isFinite else {
            return false
        }
        samples.append(Sample(rtt: rtt, offset: hostTime - (pingSentAt + rtt / 2)))
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
        updateEstimate()
        return true
    }

    /// The host clock reading at local time `localTime`, `nil` before the first pong.
    public func hostTime(fromLocal localTime: Double) -> Double? {
        offset.map { localTime + $0 }
    }

    /// The local clock reading at host time `hostTime` (such as `startAt`), `nil` before the first pong.
    public func localTime(fromHost hostTime: Double) -> Double? {
        offset.map { hostTime - $0 }
    }

    /// Forgets all round trips, for example when another phone becomes the host.
    public mutating func reset() {
        samples = []
        offset = nil
        rtt = nil
    }

    private mutating func updateEstimate() {
        let count = min(max(samples.count / 8, 1), bestSamples)
        // Fastest first; among equally fast round trips the newer one wins, so the choice never depends on the sort.
        let best = samples.enumerated()
            .sorted { ($0.element.rtt, $1.offset) < ($1.element.rtt, $0.offset) }
            .prefix(count)
            .map(\.element)
        offset = Self.median(best.map(\.offset))
        rtt = Self.median(best.map(\.rtt))
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else {
            return nil
        }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
