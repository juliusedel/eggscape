/// A score as Game Center stores it: an integer on one leaderboard.
///
/// Time trials report hundredths of a second, rounded up so a reported time is never better than the real one; their
/// leaderboards use an elapsed-time format to the hundredth of a second in App Store Connect. Endless runs report
/// whole meters, rounded down like the results screen, with an integer format.
public struct LeaderboardScore: Hashable, Sendable {
    public let leaderboard: LeaderboardID
    /// Hundredths of a second on a time-trial leaderboard, whole meters on the endless one.
    public let value: Int

    public init(leaderboard: LeaderboardID, value: Int) {
        self.leaderboard = leaderboard
        self.value = value
    }

    /// The score a run submits, or `nil` if it has nothing to submit. A time trial counts only when it reached the
    /// finish: lower is better there, so the time of a run that ended with broken eggs must never be reported. An
    /// endless run counts from one meter on.
    public init?(course: Course, finished: Bool, time: Double, meters: Double) {
        let value: Int
        switch course {
        case .timeTrial:
            guard finished, time.isFinite, time > 0 else {
                return nil
            }
            value = Self.hundredths(seconds: time)
        case .endless:
            value = Self.wholeMeters(meters)
            guard value > 0 else {
                return nil
            }
        }
        self.init(leaderboard: LeaderboardID(course: course), value: value)
    }

    /// The largest score: 248 days in hundredths of a second, or 2.1 million km. Clamping to it keeps corrupt input
    /// from trapping the conversion to `Int`.
    static let limit = Int(Int32.max)

    /// `seconds` in hundredths of a second, rounded up so a reported time is never better than the real one.
    ///
    /// A tolerance of a millionth of a hundredth absorbs floating-point noise: `1.1 * 100` is `110.00000000000001`,
    /// which must report 110, not 111. The result is clamped to `0 ... Int32.max`; NaN counts as the slowest time.
    public static func hundredths(seconds: Double) -> Int {
        guard !seconds.isNaN else {
            return limit
        }
        return clamped((seconds * 100 - 1e-6).rounded(.up))
    }

    /// `meters` in whole meters, rounded down like the results screen. The result is clamped to `0 ... Int32.max`;
    /// NaN counts as no distance.
    public static func wholeMeters(_ meters: Double) -> Int {
        guard !meters.isNaN else {
            return 0
        }
        return clamped(meters.rounded(.down))
    }

    /// The time a time-trial score stands for, e.g. to format a leaderboard entry like the results screen.
    public static func seconds(hundredths: Int) -> Double {
        Double(hundredths) / 100
    }

    private static func clamped(_ value: Double) -> Int {
        Int(min(max(value, 0), Double(limit)))
    }
}
