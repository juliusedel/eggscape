/// What happened in a run, as far as coins are concerned.
public struct RewardInput: Hashable, Sendable {
    public var course: Course
    public var weather: WeatherOption
    /// The finish line was reached. Endless runs never finish: they end when the last egg breaks.
    public var finished: Bool
    /// Distance covered.
    public var meters: Double
    public var eggsLost: Int
    /// The run set a new personal best: the best time on this distance, or the longest endless run. The app decides,
    /// because it keeps the personal bests.
    public var isPersonalBest: Bool
    /// Final place in a multiplayer race, 1 for the winner; `nil` in single player or without a place.
    public var multiplayerPlace: Int?
    /// Players who started the multiplayer race, including this one; `nil` in single player.
    public var playerCount: Int?

    public init(
        course: Course,
        weather: WeatherOption,
        finished: Bool,
        meters: Double,
        eggsLost: Int,
        isPersonalBest: Bool = false,
        multiplayerPlace: Int? = nil,
        playerCount: Int? = nil
    ) {
        self.course = course
        self.weather = weather
        self.finished = finished
        self.meters = meters
        self.eggsLost = eggsLost
        self.isPersonalBest = isPersonalBest
        self.multiplayerPlace = multiplayerPlace
        self.playerCount = playerCount
    }
}

/// The coins a run earned, itemized for the results screen.
public struct CoinReward: Hashable, Sendable {
    /// One line of the breakdown, such as "Kein Ei verloren +15" for a clean 100 m run.
    public struct Line: Hashable, Sendable {
        /// The bonuses are paid in proportion to the course length (see `CoinRewards.bonusReferenceMeters`).
        public enum Kind: String, CaseIterable, Hashable, Sendable {
            /// One coin per `CoinRewards.metersPerCoin` meters, on every course.
            case distance
            /// Reaching the finish of a time trial.
            case finish
            /// A finished time trial without a broken egg.
            case noEggLost
            /// What the weather multiplier added to the distance, finish and no-egg-lost coins.
            case weather
            /// A new personal best: the best time on the course, or the longest endless run.
            case personalBest
            /// The place in a multiplayer race.
            case place
        }

        public let kind: Kind
        public let coins: Int

        public init(kind: Kind, coins: Int) {
            self.kind = kind
            self.coins = coins
        }
    }

    /// The lines that earned coins, in the order the results screen lists them; empty if the run earned nothing.
    public let lines: [Line]
    /// The multiplier the weather put on the distance, finish and no-egg-lost coins: 1 in calm weather, 1.6 in a
    /// thunderstorm.
    public let weatherMultiplier: Double

    public init(lines: [Line], weatherMultiplier: Double = 1) {
        self.lines = lines
        self.weatherMultiplier = weatherMultiplier
    }

    public var total: Int {
        lines.reduce(0) { $0 + $1.coins }
    }

    /// The coins of one kind of line, 0 if the run earned none of it.
    public func coins(for kind: Line.Kind) -> Int {
        lines.first { $0.kind == kind }?.coins ?? 0
    }
}

/// How many coins a run pays.
///
/// Coins buy egg skins (see `SkinCatalog`), so this tuning decides how long a skin takes to earn. It pays by play
/// time: distance pays a coin per 5 m, and the time-trial bonuses grow with the course (`bonusReferenceMeters`), so a
/// clean time trial in calm weather pays about 1.6 coins per second on every course: 8 coins over 15 m (about 5 s),
/// 28 over 50 m (17 s) and 55 over 100 m (34 s), what the first egg to unlock costs. An endless run pays 0.6 coins
/// per second, plus 20 for a record. A reward is never negative.
public enum CoinRewards {
    /// Distance pays one coin per 5 m, so every run earns something, even one that ends with broken eggs. At the
    /// running speed of 3 m/s that is 0.6 coins per second; sprinting pays more for its extra risk.
    public static let metersPerCoin = 5.0

    /// The course length the time-trial bonuses below are set for. A course pays them in proportion to its length,
    /// rounded half up: in full over 100 m, half over 50 m and 15 % over 15 m, and a longer course would get more in
    /// the same proportion. Endless runs have no length and get the personal best in full.
    ///
    /// Flat bonuses made up most of a short run's coins: the old ones (15 for the finish, 10 for no broken egg) paid
    /// 28 coins for a clean 15 m run of 5 s, over five coins per second and four times the rate of the 100 m course,
    /// so the short course was the only one worth running for coins. In proportion, every course pays about the same
    /// per second of play, and the brown egg costs exactly one clean 100 m run.
    public static let bonusReferenceMeters = 100

    /// Reaching the finish of a time trial, the goal of the mode: 20 coins per 100 m of course.
    public static let finishBonus = 20

    /// A finished time trial without a broken egg, the skill the game is about: 15 coins per 100 m of course. With the
    /// finish and the distance, a clean 100 m run in calm weather pays 55 coins.
    public static let noEggLostBonus = 15

    /// A new personal best: 20 coins per 100 m of course in a time trial, a flat 20 for the longest endless run. Added
    /// after the weather multiplier, so a record pays the same in any weather.
    public static let personalBestBonus = 20

    /// The prize for places 1 to 4 of a multiplayer race, per 100 m of course. Added after the weather multiplier like
    /// the personal best: a prize does not depend on the weather. Over 15 m second and third place both get 2 coins,
    /// 2.25 and 1.5 rounded.
    public static let placeBonuses = [25, 15, 10, 5]

    /// A place bonus needs an opponent; alone, every "race" would be won.
    public static let minimumPlayersForPlaceBonus = 2

    /// No real run gets anywhere near this; it only keeps corrupt input from trapping the conversion to `Int`.
    private static let maximumRewardedMeters = 1_000_000.0

    /// The multiplier bad weather puts on the distance, finish and no-egg-lost coins.
    ///
    /// Harder weather pays more: wind (1.2) pushes the egg sideways, rain (1.3) makes the bowl slippery and adds drops
    /// and puddles, a thunderstorm (1.6) brings all of that plus lightning. Random weather (1.4) escalates from calm
    /// to storm along the track, so it pays between rain and storm. Endless runs always get 1: their weather already
    /// intensifies every 100 m, and every extra meter pays anyway.
    public static func weatherMultiplier(for weather: WeatherOption, on course: Course) -> Double {
        Double(weatherPercent(for: weather, on: course)) / 100
    }

    /// The coins `input` earned. The bonuses follow the course length; the weather multiplies the distance, finish
    /// and no-egg-lost coins, and the personal best and place bonuses come on top.
    public static func reward(for input: RewardInput) -> CoinReward {
        let course = input.course
        // Only a time trial has a finish line, so an endless run reported as finished earns no finish bonus.
        let finishedTimeTrial = input.finished && course.length != nil
        let distance = distanceCoins(meters: input.meters)
        let finish = finishedTimeTrial ? scaled(finishBonus, to: course) : 0
        let noEggLost = finishedTimeTrial && input.eggsLost <= 0 ? scaled(noEggLostBonus, to: course) : 0
        let subtotal = distance + finish + noEggLost
        let percent = weatherPercent(for: input.weather, on: course)
        // Rounded half up, in integers to stay exact.
        let weather = (subtotal * (percent - 100) + 50) / 100
        let personalBest = input.isPersonalBest ? scaled(personalBestBonus, to: course) : 0
        let place = placeBonus(place: input.multiplayerPlace, playerCount: input.playerCount, on: course)

        let amounts: [(kind: CoinReward.Line.Kind, coins: Int)] = [
            (.distance, distance),
            (.finish, finish),
            (.noEggLost, noEggLost),
            (.weather, weather),
            (.personalBest, personalBest),
            (.place, place),
        ]
        return CoinReward(
            lines: amounts.filter { $0.coins > 0 }.map { CoinReward.Line(kind: $0.kind, coins: $0.coins) },
            weatherMultiplier: Double(percent) / 100
        )
    }

    /// The weather multiplier in percent. Integer percentages keep the rounding exact, where `1.2 - 1` in floating
    /// point is slightly less than 0.2.
    private static func weatherPercent(for weather: WeatherOption, on course: Course) -> Int {
        guard course != .endless else {
            return 100
        }
        switch weather {
        case .off, .fixed(.clear): return 100
        case .fixed(.wind): return 120
        case .fixed(.rain): return 130
        case .fixed(.storm): return 160
        case .random: return 140
        }
    }

    /// Whole coins for the distance, rounded down like the meters on the results screen.
    private static func distanceCoins(meters: Double) -> Int {
        guard meters.isFinite, meters > 0 else {
            return 0
        }
        return Int(min(meters, maximumRewardedMeters) / metersPerCoin)
    }

    /// `bonus`, set for `bonusReferenceMeters` of course, paid for the length of `course`; in full without a length
    /// (endless). Rounded half up, in integers to stay exact like the weather line: course lengths are whole meters.
    private static func scaled(_ bonus: Int, to course: Course) -> Int {
        guard let length = course.length else {
            return bonus
        }
        return (bonus * Int(length.rounded()) + bonusReferenceMeters / 2) / bonusReferenceMeters
    }

    /// The prize for `place` on `course`; 0 without a place, without an opponent, or for a place the race cannot have.
    private static func placeBonus(place: Int?, playerCount: Int?, on course: Course) -> Int {
        guard let place, let playerCount, playerCount >= minimumPlayersForPlaceBonus,
              (1 ... min(playerCount, placeBonuses.count)).contains(place)
        else {
            return 0
        }
        return scaled(placeBonuses[place - 1], to: course)
    }
}
