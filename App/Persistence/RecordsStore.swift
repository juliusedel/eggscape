import EggscapeCore
import Foundation
import Observation

/// Personal bests: the fastest time per time-trial distance and weather, and the longest endless run.
@MainActor
@Observable
final class RecordsStore {
    private enum Key {
        /// Best times over 15, 50 and 100 m.
        static let times = "records.bestTimes.v2"
        /// Where builds with the 150, 300 and 600 m courses kept their times, under the same distance names. Those
        /// times are no bests for the shorter courses and must not reach their leaderboards, so they are deleted
        /// instead of read.
        static let retiredTimes = "records.bestTimes"
        /// Endlos did not change with the courses, so its record keeps its key.
        static let endless = "records.endlessMeters"
    }

    @ObservationIgnored private let defaults: UserDefaults
    /// Best times in seconds, keyed by `timeKey(distance:weather:)`.
    private(set) var bestTimes: [String: Double]
    /// Longest endless run in meters.
    private(set) var bestEndless: Double?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.removeObject(forKey: Key.retiredTimes)
        bestTimes = defaults.dictionary(forKey: Key.times) as? [String: Double] ?? [:]
        bestEndless = defaults.object(forKey: Key.endless) as? Double
    }

    func bestTime(distance: RaceDistance, weather: WeatherOption) -> Double? {
        bestTimes[Self.timeKey(distance: distance, weather: weather)]
    }

    /// Stores a finished time trial; returns `true` if it beats the previous best.
    @discardableResult
    func recordTime(_ time: Double, distance: RaceDistance, weather: WeatherOption) -> Bool {
        let key = Self.timeKey(distance: distance, weather: weather)
        guard bestTimes[key].map({ time < $0 }) ?? true else { return false }
        bestTimes[key] = time
        defaults.set(bestTimes, forKey: Key.times)
        return true
    }

    /// Stores an endless run; returns `true` if it beats the previous best.
    @discardableResult
    func recordEndless(meters: Double) -> Bool {
        guard meters > 0, bestEndless.map({ meters > $0 }) ?? true else { return false }
        bestEndless = meters
        defaults.set(meters, forKey: Key.endless)
        return true
    }

    /// The best score per Game Center leaderboard: the fastest time per distance in any weather, and the longest
    /// endless run.
    var leaderboardScores: [LeaderboardScore] {
        var scores: [LeaderboardScore] = []
        for distance in RaceDistance.allCases {
            let times = WeatherOption.choices.compactMap { bestTime(distance: distance, weather: $0) }
            if let best = times.min(),
               let score = LeaderboardScore(
                   course: .timeTrial(distance),
                   finished: true,
                   time: best,
                   meters: distance.meters
               )
            {
                scores.append(score)
            }
        }
        if let bestEndless,
           let score = LeaderboardScore(course: .endless, finished: false, time: 0, meters: bestEndless)
        {
            scores.append(score)
        }
        return scores
    }

    func reset() {
        defaults.removeObject(forKey: Key.times)
        defaults.removeObject(forKey: Key.endless)
        bestTimes = [:]
        bestEndless = nil
    }

    /// Stable storage key, e.g. "short.off" or "long.fixed-storm".
    static func timeKey(distance: RaceDistance, weather: WeatherOption) -> String {
        "\(distance.rawValue).\(weather.storageKey)"
    }
}

extension WeatherOption {
    /// Stable identifier for storage and analytics-free bookkeeping.
    var storageKey: String {
        switch self {
        case .off: "off"
        case let .fixed(kind): "fixed-\(kind.rawValue)"
        case .random: "random"
        }
    }
}
