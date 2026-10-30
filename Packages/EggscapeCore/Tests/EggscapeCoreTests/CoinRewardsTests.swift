@testable import EggscapeCore
import Testing

/// A clean, finished short time trial (15 m) in calm weather unless told otherwise.
private func reward(
    _ course: Course = .timeTrial(.short),
    weather: WeatherOption = .off,
    finished: Bool = true,
    meters: Double = RaceDistance.short.meters,
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

/// An endless run that ended when the last egg broke.
private func endless(meters: Double, weather: WeatherOption = .off, personalBest: Bool = false) -> CoinReward {
    reward(.endless, weather: weather, finished: false, meters: meters, eggsLost: 3, personalBest: personalBest)
}

struct CoinRewardsTests {
    @Test func cleanShortRunInCalmWeatherPays28() {
        let result = reward()
        // 15 m / 5 m = 3, +15 for the finish, +10 for losing no egg.
        #expect(result.lines == [
            CoinReward.Line(kind: .distance, coins: 3),
            CoinReward.Line(kind: .finish, coins: 15),
            CoinReward.Line(kind: .noEggLost, coins: 10),
        ])
        #expect(result.total == 28)
        #expect(result.weatherMultiplier == 1)
    }

    @Test(arguments: [(RaceDistance.short, 28), (.medium, 35), (.long, 45)])
    func cleanRunsInCalmWeatherPayByDistance(distance: RaceDistance, total: Int) {
        // The 25 coins for finishing without a broken egg are the same on every course.
        #expect(reward(.timeTrial(distance), meters: distance.meters).total == total)
    }

    @Test func aBrokenEggCostsTheNoEggLostBonus() {
        let result = reward(eggsLost: 1)
        #expect(result.total == 18)
        #expect(result.coins(for: .noEggLost) == 0)
        #expect(!result.lines.contains { $0.kind == .noEggLost })
    }

    @Test func anUnfinishedTimeTrialPaysTheDistanceOnly() {
        let result = reward(.timeTrial(.long), finished: false, meters: 72.7, eggsLost: 3)
        #expect(result.lines == [CoinReward.Line(kind: .distance, coins: 14)])
    }

    @Test(arguments: [
        (WeatherOption.off, 28),
        (WeatherOption.fixed(.clear), 28),
        // 28 × 1.2 = 33.6, rounded to the nearest coin.
        (WeatherOption.fixed(.wind), 34),
        (WeatherOption.fixed(.rain), 36),
        (WeatherOption.fixed(.storm), 45),
        (WeatherOption.random, 39),
    ])
    func weatherMultipliesTheSubtotal(weather: WeatherOption, total: Int) {
        #expect(reward(weather: weather).total == total)
    }

    @Test(arguments: [(RaceDistance.medium, 11, 46), (.long, 14, 59)])
    func weatherRoundsHalfUp(distance: RaceDistance, weather: Int, total: Int) {
        // Rain adds 30 %: 10.5 coins to a clean medium run, rounded up to 11 rather than to the even 10, and 13.5 to a
        // clean long run, 58.5 in all, rounded up to 59 rather than to the even 58.
        let result = reward(.timeTrial(distance), weather: .fixed(.rain), meters: distance.meters)
        #expect(result.coins(for: .weather) == weather)
        #expect(result.total == total)
    }

    @Test func stormIsItemizedAndBonusesComeOnTop() {
        let result = reward(weather: .fixed(.storm), personalBest: true, place: 1, players: 3)
        // (3 + 15 + 10) × 1.6 = 44.8, so 17 for the storm; the personal best and the place bonus are not multiplied.
        #expect(result.lines == [
            CoinReward.Line(kind: .distance, coins: 3),
            CoinReward.Line(kind: .finish, coins: 15),
            CoinReward.Line(kind: .noEggLost, coins: 10),
            CoinReward.Line(kind: .weather, coins: 17),
            CoinReward.Line(kind: .personalBest, coins: 20),
            CoinReward.Line(kind: .place, coins: 25),
        ])
        #expect(result.total == 90)
        #expect(result.weatherMultiplier == 1.6)
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

    @Test func personalBestPaysTwenty() {
        #expect(endless(meters: 250, personalBest: true).total == 70)
        #expect(reward(personalBest: true).total == 48)
    }

    @Test(arguments: [(1, 25), (2, 15), (3, 10), (4, 5)])
    func placeBonusInARaceOfFour(place: Int, bonus: Int) {
        let result = reward(place: place, players: 4)
        #expect(result.coins(for: .place) == bonus)
        #expect(result.total == 28 + bonus)
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
        let result = reward(.timeTrial(.medium), finished: false, meters: 37, eggsLost: 3, place: 3, players: 3)
        #expect(result.lines == [
            CoinReward.Line(kind: .distance, coins: 7),
            CoinReward.Line(kind: .place, coins: 10),
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
