@testable import EggscapeCore
import Testing

struct LeaderboardTests {
    @Test func idsMatchAppStoreConnect() {
        #expect(LeaderboardID.allCases.map(\.rawValue) == [
            "de.juliusedel.eggscape.time.short",
            "de.juliusedel.eggscape.time.medium",
            "de.juliusedel.eggscape.time.long",
            "de.juliusedel.eggscape.endless",
        ])
    }

    @Test func everyCourseHasItsOwnLeaderboard() {
        let courses = RaceDistance.allCases.map(Course.timeTrial) + [.endless]
        #expect(courses.map(LeaderboardID.init(course:)) == LeaderboardID.allCases)
        for leaderboard in LeaderboardID.allCases {
            #expect(LeaderboardID(course: leaderboard.course) == leaderboard)
        }
    }

    @Test func timesRankLowestFirstAndDistancesHighestFirst() {
        #expect(LeaderboardID.shortTimeTrial.lowerIsBetter)
        #expect(LeaderboardID.mediumTimeTrial.lowerIsBetter)
        #expect(LeaderboardID.longTimeTrial.lowerIsBetter)
        #expect(!LeaderboardID.endless.lowerIsBetter)
    }

    @Test(arguments: [
        (42.0, 4200),
        (42.001, 4201),
        (42.009, 4201),
        (42.01, 4201),
        (42.011, 4202),
        // 1.1 * 100 is 110.00000000000001, and 0.07 * 100 is 7.000000000000001, in floating point.
        (1.1, 110),
        (0.07, 7),
        (50.25, 5025),
        (0.0, 0),
    ])
    func timesRoundUpToTheHundredth(seconds: Double, hundredths: Int) {
        #expect(LeaderboardScore.hundredths(seconds: seconds) == hundredths)
    }

    @Test func reportedTimesAreNeverBetterThanTheRealOnes() {
        var rng = SplitMix64(seed: 2026)
        for _ in 0 ..< 10000 {
            let seconds = rng.uniform(20 ... 400)
            let reported = LeaderboardScore.seconds(hundredths: LeaderboardScore.hundredths(seconds: seconds))
            // At most the documented floating-point tolerance faster, and less than a hundredth slower.
            #expect(reported >= seconds - 1e-7)
            #expect(reported < seconds + 0.01)
        }
    }

    @Test(arguments: [
        (0.0, 0),
        (0.99, 0),
        (1.0, 1),
        (99.999, 99),
        (100.0, 100),
        (523.9, 523),
        (-5.0, 0),
    ])
    func distancesRoundDownToTheMeter(meters: Double, score: Int) {
        #expect(LeaderboardScore.wholeMeters(meters) == score)
    }

    @Test func corruptValuesAreClampedInsteadOfTrapping() {
        // NaN must never turn into a record: the slowest time, no distance.
        #expect(LeaderboardScore.hundredths(seconds: .nan) == LeaderboardScore.limit)
        #expect(LeaderboardScore.hundredths(seconds: .infinity) == LeaderboardScore.limit)
        #expect(LeaderboardScore.hundredths(seconds: 1e300) == LeaderboardScore.limit)
        #expect(LeaderboardScore.hundredths(seconds: -3) == 0)
        #expect(LeaderboardScore.wholeMeters(.nan) == 0)
        #expect(LeaderboardScore.wholeMeters(.infinity) == LeaderboardScore.limit)
        #expect(LeaderboardScore.wholeMeters(-.infinity) == 0)
    }

    @Test func aFinishedTimeTrialSubmitsItsTime() throws {
        let score = try #require(LeaderboardScore(
            course: .timeTrial(.medium),
            finished: true,
            time: 101.234,
            meters: 300
        ))
        #expect(score == LeaderboardScore(leaderboard: .mediumTimeTrial, value: 10124))
        #expect(LeaderboardScore.seconds(hundredths: score.value) == 101.24)
    }

    @Test func aTimeTrialWithoutAFinishSubmitsNothing() {
        // Lower is better, so the short time of a run that ended early would top the leaderboard.
        #expect(LeaderboardScore(course: .timeTrial(.short), finished: false, time: 12.5, meters: 40) == nil)
        #expect(LeaderboardScore(course: .timeTrial(.short), finished: true, time: 0, meters: 150) == nil)
        #expect(LeaderboardScore(course: .timeTrial(.short), finished: true, time: -1, meters: 150) == nil)
        #expect(LeaderboardScore(course: .timeTrial(.short), finished: true, time: .nan, meters: 150) == nil)
        #expect(LeaderboardScore(course: .timeTrial(.long), finished: true, time: .infinity, meters: 600) == nil)
    }

    @Test func anEndlessRunSubmitsWholeMeters() throws {
        let score = try #require(LeaderboardScore(course: .endless, finished: false, time: 180, meters: 523.9))
        #expect(score == LeaderboardScore(leaderboard: .endless, value: 523))
        #expect(LeaderboardScore(course: .endless, finished: false, time: 3, meters: 0.6) == nil)
        #expect(LeaderboardScore(course: .endless, finished: false, time: 3, meters: .nan) == nil)
    }
}
