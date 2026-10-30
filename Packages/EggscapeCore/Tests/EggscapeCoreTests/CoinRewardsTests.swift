@testable import EggscapeCore
import Testing

/// A clean, finished long time trial (100 m, the course the bonuses are set for) in calm weather unless told
/// otherwise.
private func reward(
    _ course: Course = .timeTrial(.long),
    weather: WeatherOption = .off,
    finished: Bool = true,
    meters: Double = RaceDistance.long.meters,
    eggsLost: Int = 0,
    personalBest: Bool = false,
    place: Int? = nil,
    players: Int? = nil
) -> CoinReward {
    CoinRewards.reward(for: RewardInput(
        course: course,
        weather: weather,
        finished: finished,
        meters: meters,
        eggsLost: eggsLost,
        isPersonalBest: personalBest,
        multiplayerPlace: place,
        playerCount: players
    ))
}

/// A finished time trial over `distance` without a broken egg, in calm weather unless told otherwise.
private func cleanRun(
    _ distance: RaceDistance,
    weather: WeatherOption = .off,
    personalBest: Bool = false,
    place: Int? = nil,
    players: Int? = nil
) -> CoinReward {
    reward(
        .timeTrial(distance),
        weather: weather,
        meters: distance.meters,
        personalBest: personalBest,
        place: place,
        players: players
    )
}

/// An endless run that ended when the last egg broke.
private func endless(meters: Double, weather: WeatherOption = .off, personalBest: Bool = false) -> CoinReward {
    reward(.endless, weather: weather, finished: false, meters: meters, eggsLost: 3, personalBest: personalBest)
}

struct CoinRewardsTests {
    @Test func aCleanLongRunInCalmWeatherPays55() {
        let result = reward()
        // 100 m / 5 m = 20, +20 for the finish, +15 for losing no egg: the bonuses in full, as they are set for 100 m.
        #expect(result.lines == [
            CoinReward.Line(kind: .distance, coins: 20),
            CoinReward.Line(kind: .finish, coins: 20),
            CoinReward.Line(kind: .noEggLost, coins: 15),
        ])
        #expect(result.total == 55)
        #expect(result.weatherMultiplier == 1)
    }

    @Test(arguments: [(RaceDistance.short, 3, 3, 2), (.medium, 10, 10, 8), (.long, 20, 20, 15)])
    func theBonusesFollowTheCourseLength(distance: RaceDistance, distanceCoins: Int, finish: Int, noEggLost: Int) {
        // A coin per 5 m on every course. The bonuses pay 15 % over 15 m (3 and 2.25 coins) and half over 50 m (10 and
        // 7.5), rounded half up.
        let result = cleanRun(distance)
        #expect(result.lines == [
            CoinReward.Line(kind: .distance, coins: distanceCoins),
            CoinReward.Line(kind: .finish, coins: finish),
            CoinReward.Line(kind: .noEggLost, coins: noEggLost),
        ])
        #expect(result.total == distanceCoins + finish + noEggLost)
    }

    @Test(arguments: [(RaceDistance.short, 8), (.medium, 28), (.long, 55)])
    func cleanRunsPayAboutTheSamePerSecondOnEveryCourse(distance: RaceDistance, total: Int) {
        // At running speed 8 coins in 5 s, 28 in 17 s and 55 in 33 s: about 1.6 coins per second. With flat bonuses
        // the 15 m paid 28 coins, four times the rate of the 100 m course, and was the course to farm.
        let coinsPerSecond = { (distance: RaceDistance) in
            Double(cleanRun(distance).total) * GameConfig.standard.runSpeed / distance.meters
        }
        #expect(cleanRun(distance).total == total)
        #expect(abs(coinsPerSecond(distance) / coinsPerSecond(.long) - 1) <= 0.1, "\(coinsPerSecond(distance)) per s")
    }

    @Test func aBrokenEggCostsTheNoEggLostBonus() {
        let result = reward(eggsLost: 1)
        #expect(result.total == 40)
        #expect(result.coins(for: .noEggLost) == 0)
        #expect(!result.lines.contains { $0.kind == .noEggLost })
    }

    @Test func anUnfinishedTimeTrialPaysTheDistanceOnly() {
        let result = reward(finished: false, meters: 72.7, eggsLost: 3)
        #expect(result.lines == [CoinReward.Line(kind: .distance, coins: 14)])
    }

    @Test(arguments: [
        (WeatherOption.off, 55),
        (WeatherOption.fixed(.clear), 55),
        // 55 × 1.2 = 66, × 1.3 = 71.5 rounded half up, × 1.6 = 88, × 1.4 = 77: what the old 150 m course paid.
        (WeatherOption.fixed(.wind), 66),
        (WeatherOption.fixed(.rain), 72),
        (WeatherOption.fixed(.storm), 88),
        (WeatherOption.random, 77),
    ])
    func weatherMultipliesTheSubtotal(weather: WeatherOption, total: Int) {
        #expect(reward(weather: weather).total == total)
    }

    @Test(arguments: [
        // 8 × 1.2 = 9.6, × 1.3 = 10.4, × 1.6 = 12.8, × 1.4 = 11.2.
        (RaceDistance.short, WeatherOption.fixed(.wind), 10),
        (RaceDistance.short, WeatherOption.fixed(.rain), 10),
        (RaceDistance.short, WeatherOption.fixed(.storm), 13),
        (RaceDistance.short, WeatherOption.random, 11),
        // 28 × 1.2 = 33.6, × 1.3 = 36.4, × 1.6 = 44.8, × 1.4 = 39.2.
        (RaceDistance.medium, WeatherOption.fixed(.wind), 34),
        (RaceDistance.medium, WeatherOption.fixed(.rain), 36),
        (RaceDistance.medium, WeatherOption.fixed(.storm), 45),
        (RaceDistance.medium, WeatherOption.random, 39),
    ])
    func weatherMultipliesTheShorterCoursesToo(distance: RaceDistance, weather: WeatherOption, total: Int) {
        #expect(cleanRun(distance, weather: weather).total == total)
    }

    @Test func weatherRoundsHalfUp() {
        // Rain adds 30 %, the only multiplier that can leave half a coin. A clean long run: 55 × 0.3 = 16.5, rounded up
        // to 17 rather than to the even 16 or down, 72 in all.
        let clean = reward(weather: .fixed(.rain))
        #expect(clean.coins(for: .weather) == 17)
        #expect(clean.total == 72)
        // All eggs broken after 25 m: 5 coins, 6.5 with the rain, rounded up to 7 rather than to the even 6 or down.
        // Rounding the line to even passes here (1.5 to 2) and rounding the total to even passes above (71.5 to 72),
        // but each fails the other case.
        let broken = reward(weather: .fixed(.rain), finished: false, meters: 25, eggsLost: 3)
        #expect(broken.coins(for: .weather) == 2)
        #expect(broken.total == 7)
    }

    @Test(arguments: [(1, 13), (4, 3)])
    func scaledBonusesRoundHalfUp(place: Int, bonus: Int) {
        // Over 50 m a place pays half its prize: 12.5 coins to the winner and 2.5 to fourth place, rounded up rather
        // than to the even 12 and 2 or down.
        #expect(cleanRun(.medium, place: place, players: 4).coins(for: .place) == bonus)
    }

    @Test func stormIsItemizedAndBonusesComeOnTop() {
        let result = reward(weather: .fixed(.storm), personalBest: true, place: 1, players: 3)
        // (20 + 20 + 15) × 1.6 = 88, so 33 for the storm; the personal best and the place bonus are not multiplied.
        #expect(result.lines == [
            CoinReward.Line(kind: .distance, coins: 20),
            CoinReward.Line(kind: .finish, coins: 20),
            CoinReward.Line(kind: .noEggLost, coins: 15),
            CoinReward.Line(kind: .weather, coins: 33),
            CoinReward.Line(kind: .personalBest, coins: 20),
            CoinReward.Line(kind: .place, coins: 25),
        ])
        #expect(result.total == 133)
        #expect(result.weatherMultiplier == 1.6)
    }

    @Test func theWeatherMultipliesScaledBonusesLikeFullOnes() {
        let result = cleanRun(.short, weather: .fixed(.storm), personalBest: true, place: 1, players: 3)
        // (3 + 3 + 2) × 1.6 = 12.8, so 5 for the storm; the personal best (3) and the winner's prize (3.75, so 4) come
        // on top without the storm.
        #expect(result.lines == [
            CoinReward.Line(kind: .distance, coins: 3),
            CoinReward.Line(kind: .finish, coins: 3),
            CoinReward.Line(kind: .noEggLost, coins: 2),
            CoinReward.Line(kind: .weather, coins: 5),
            CoinReward.Line(kind: .personalBest, coins: 3),
            CoinReward.Line(kind: .place, coins: 4),
        ])
        #expect(result.total == 20)
    }

    @Test func weatherMultipliers() {
        let course = Course.timeTrial(.medium)
        #expect(CoinRewards.weatherMultiplier(for: .off, on: course) == 1)
        #expect(CoinRewards.weatherMultiplier(for: .fixed(.clear), on: course) == 1)
        #expect(CoinRewards.weatherMultiplier(for: .fixed(.wind), on: course) == 1.2)
        #expect(CoinRewards.weatherMultiplier(for: .fixed(.rain), on: course) == 1.3)
        #expect(CoinRewards.weatherMultiplier(for: .fixed(.storm), on: course) == 1.6)
        #expect(CoinRewards.weatherMultiplier(for: .random, on: course) == 1.4)
    }

    @Test func endlessPaysDistanceWithoutWeatherMultiplier() {
        // Endless weather intensifies every 100 m anyway, and every meter pays.
        let result = endless(meters: 523.9, weather: .fixed(.storm))
        #expect(result.lines == [CoinReward.Line(kind: .distance, coins: 104)])
        #expect(result.weatherMultiplier == 1)
        #expect(CoinRewards.weatherMultiplier(for: .random, on: .endless) == 1)
    }

    @Test func endlessNeverEarnsTheFinishBonuses() {
        // An endless run cannot finish, even when the input claims it did.
        let result = reward(.endless, finished: true, meters: 100, eggsLost: 0)
        #expect(result.lines == [CoinReward.Line(kind: .distance, coins: 20)])
    }

    @Test(arguments: [(RaceDistance.short, 3, 11), (.medium, 10, 38), (.long, 20, 75)])
    func aPersonalBestFollowsTheCourseLength(distance: RaceDistance, bonus: Int, total: Int) {
        // What a new player's first clean run on each course pays: the first finish is always a personal best.
        let result = cleanRun(distance, personalBest: true)
        #expect(result.coins(for: .personalBest) == bonus)
        #expect(result.total == total)
    }

    @Test func anEndlessRecordPaysAFlatTwenty() {
        // Endless runs have no course length, so a record pays the same however far it went.
        #expect(endless(meters: 250, personalBest: true).lines == [
            CoinReward.Line(kind: .distance, coins: 50),
            CoinReward.Line(kind: .personalBest, coins: 20),
        ])
        #expect(endless(meters: 1000, personalBest: true).coins(for: .personalBest) == 20)
    }

    @Test(arguments: [
        // 25, 15, 10 and 5 × 0.15 = 3.75, 2.25, 1.5 and 0.75: second and third place tie after rounding.
        (RaceDistance.short, [4, 2, 2, 1]),
        // × 0.5 = 12.5, 7.5, 5 and 2.5.
        (RaceDistance.medium, [13, 8, 5, 3]),
        (RaceDistance.long, [25, 15, 10, 5]),
    ])
    func placeBonusesFollowTheCourseLength(distance: RaceDistance, bonuses: [Int]) {
        let clean = cleanRun(distance).total
        for (index, bonus) in bonuses.enumerated() {
            let result = cleanRun(distance, place: index + 1, players: 4)
            #expect(result.coins(for: .place) == bonus, "place \(index + 1)")
            #expect(result.total == clean + bonus)
        }
    }

    @Test func placeBonusNeedsAtLeastTwoPlayers() {
        #expect(reward(place: 1, players: 1).coins(for: .place) == 0)
        #expect(reward(place: 1, players: nil).coins(for: .place) == 0)
        #expect(reward(place: nil, players: 3).coins(for: .place) == 0)
        #expect(reward(place: 1, players: 2).coins(for: .place) == 25)
        #expect(reward(place: 2, players: 2).coins(for: .place) == 15)
    }

    @Test func impossiblePlacesPayNothing() {
        #expect(reward(place: 3, players: 2).coins(for: .place) == 0)
        #expect(reward(place: 0, players: 4).coins(for: .place) == 0)
        #expect(reward(place: -1, players: 4).coins(for: .place) == 0)
        #expect(reward(place: 5, players: 6).coins(for: .place) == 0)
    }

    @Test func aLosingRacerStillEarnsDistanceAndPlace() {
        // Last of three over 50 m with all eggs broken after 37 m: half of the 10 coins for third place.
        let result = reward(.timeTrial(.medium), finished: false, meters: 37, eggsLost: 3, place: 3, players: 3)
        #expect(result.lines == [
            CoinReward.Line(kind: .distance, coins: 7),
            CoinReward.Line(kind: .place, coins: 5),
        ])
    }

    @Test func zeroMetersEarnNothing() {
        let result = endless(meters: 0, weather: .fixed(.storm))
        #expect(result.total == 0)
        #expect(result.lines.isEmpty)
        #expect(reward(finished: false, meters: 0, eggsLost: 3).total == 0)
    }

    @Test func distanceRoundsDown() {
        #expect(endless(meters: 4.99).total == 0)
        #expect(endless(meters: 5).total == 1)
        #expect(endless(meters: 9.99).total == 1)
    }

    @Test(arguments: [-50.0, Double.nan, Double.infinity, -Double.infinity, 1e300])
    func corruptDistancesNeitherTrapNorGoNegative(meters: Double) {
        let total = endless(meters: meters).total
        #expect(total >= 0)
        #expect(total <= 200_000)
    }

    @Test func everyLineIsPositive() {
        let courses = RaceDistance.allCases.map(Course.timeTrial) + [.endless]
        let weathers: [WeatherOption] = [.off, .fixed(.clear), .fixed(.wind), .fixed(.rain), .fixed(.storm), .random]
        for course in courses {
            for weather in weathers {
                for meters in [-10.0, 0, 3] + RaceDistance.allCases.map(\.meters) + [600] {
                    for finished in [false, true] {
                        let result = reward(
                            course,
                            weather: weather,
                            finished: finished,
                            meters: meters,
                            eggsLost: finished ? 0 : 3,
                            personalBest: finished,
                            place: 2,
                            players: 3
                        )
                        #expect(result.lines.allSatisfy { $0.coins > 0 })
                        #expect(Set(result.lines.map(\.kind)).count == result.lines.count)
                        #expect(result.total == result.lines.map(\.coins).reduce(0, +))
                    }
                }
            }
        }
    }
}
