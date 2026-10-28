@testable import EggscapeCore
import Testing

private func completed(_ time: Double, eggsLost: Int = 0) -> FinishReport {
    FinishReport(completed: true, time: time, meters: 150, eggsLost: eggsLost)
}

private func outOfEggs(at meters: Double) -> FinishReport {
    FinishReport(completed: false, time: meters / 3, meters: meters, eggsLost: 3)
}

/// A race of the given players, each nicknamed like their id.
private func race(_ ids: PlayerID...) -> RaceReferee {
    var referee = RaceReferee()
    for id in ids {
        referee.register(id, nickname: id.rawValue)
    }
    return referee
}

struct RaceRefereeTests {
    @Test func finishOrderFollowsArrivalNotTheReportedTimes() {
        var referee = race("anna", "ben", "cem")
        // Ben's phone hitched, so it reports a faster time, but Anna's report reached the host first.
        let accepted = [
            referee.recordFinished(completed(50.9), from: "anna"),
            referee.recordFinished(completed(49.8), from: "ben"),
            referee.recordFinished(completed(52.4), from: "cem"),
        ]
        #expect(accepted == [true, true, true])
        #expect(referee.arrivals == ["anna", "ben", "cem"])
        let entries = referee.results().entries
        #expect(entries.map(\.playerID) == ["anna", "ben", "cem"])
        #expect(entries.map(\.place) == [1, 2, 3])
        #expect(entries.map(\.status) == [.finished(time: 50.9), .finished(time: 49.8), .finished(time: 52.4)])
    }

    @Test func outOfEggsRankByDistanceBehindCompletedRuns() {
        var referee = race("anna", "ben", "cem", "dana")
        referee.recordFinished(outOfEggs(at: 80), from: "anna")
        referee.recordFinished(outOfEggs(at: 120), from: "ben")
        referee.recordProgress(meters: 140, eggsLeft: 1, from: "cem")
        referee.markDisconnected("cem")
        referee.recordFinished(completed(55, eggsLost: 2), from: "dana")
        #expect(referee.isComplete)

        let entries = referee.results().entries
        // Cem got furthest but left, so Cem ranks last.
        #expect(entries.map(\.playerID) == ["dana", "ben", "anna", "cem"])
        #expect(entries.map(\.status) == [
            .finished(time: 55),
            .outOfEggs(meters: 120),
            .outOfEggs(meters: 80),
            .disconnected(meters: 140),
        ])
        #expect(entries.map(\.eggsLost) == [2, 3, 3, 2])
        #expect(entries.map(\.place) == [1, 2, 3, 4])
    }

    @Test func playersWhoLeftRankByTheirLastDistance() {
        var referee = race("anna", "ben", "cem", "dana")
        referee.recordProgress(meters: 60, eggsLeft: 3, from: "anna")
        referee.recordProgress(meters: 90, eggsLeft: 2, from: "ben")
        referee.recordProgress(meters: 60, eggsLeft: 1, from: "cem")
        for id: PlayerID in ["anna", "ben", "cem"] {
            referee.markDisconnected(id)
        }
        referee.recordFinished(completed(50), from: "dana")
        // Anna and Cem left at the same distance and keep their registration order.
        #expect(referee.results().entries.map(\.playerID) == ["dana", "ben", "anna", "cem"])
    }

    @Test func equalDistancesKeepTheArrivalOrder() {
        var referee = race("anna", "ben", "cem")
        referee.recordFinished(outOfEggs(at: 75), from: "cem")
        referee.recordFinished(outOfEggs(at: 75), from: "anna")
        referee.recordFinished(outOfEggs(at: 90), from: "ben")
        #expect(referee.results().entries.map(\.playerID) == ["ben", "cem", "anna"])
    }

    @Test func completesWhenTheLastConnectedPlayerReports() {
        var referee = race("anna", "ben", "cem")
        referee.markDisconnected("cem")
        #expect(!referee.isComplete)
        referee.recordFinished(completed(50), from: "anna")
        #expect(!referee.isComplete)
        referee.recordFinished(outOfEggs(at: 70), from: "ben")
        #expect(referee.isComplete)
    }

    @Test func losingTheLastRunnerCompletesTheRace() {
        var referee = race("anna", "ben")
        referee.recordFinished(completed(50), from: "anna")
        referee.recordProgress(meters: 42, eggsLeft: 1, from: "ben")
        #expect(!referee.isComplete)
        referee.markDisconnected("ben")
        #expect(referee.isComplete)
        #expect(referee.results().entries == [
            RaceResultEntry(place: 1, playerID: "anna", nickname: "anna", status: .finished(time: 50), eggsLost: 0),
            RaceResultEntry(place: 2, playerID: "ben", nickname: "ben", status: .disconnected(meters: 42), eggsLost: 2),
        ])
    }

    @Test func leavingAfterTheFinishKeepsThePlace() {
        var referee = race("anna", "ben")
        referee.recordFinished(completed(50), from: "anna")
        referee.markDisconnected("anna")
        referee.recordFinished(completed(53), from: "ben")
        #expect(referee.isComplete)
        #expect(referee.results().entries.map(\.status) == [.finished(time: 50), .finished(time: 53)])
    }

    @Test func anEmptyRaceIsNeverComplete() {
        #expect(!RaceReferee().isComplete)
        #expect(RaceReferee().results().entries.isEmpty)
    }

    @Test func ignoresReportsThatCannotCount() {
        var referee = race("anna", "ben")
        let first = referee.recordFinished(completed(50), from: "anna")
        let second = referee.recordFinished(completed(40), from: "anna")
        let stranger = referee.recordFinished(completed(45), from: "zoe")
        referee.markDisconnected("ben")
        let afterLeaving = referee.recordFinished(completed(51), from: "ben")
        let progressAfterFinish = referee.recordProgress(meters: 10, eggsLeft: 3, from: "anna")
        let eggAfterLeaving = referee.recordEggDropped(eggsLeft: 2, from: "ben")
        #expect(first)
        #expect(!second, "a second report")
        #expect(!stranger, "a player who never registered")
        #expect(!afterLeaving, "a report after leaving")
        #expect(!progressAfterFinish, "progress after the finish")
        #expect(!eggAfterLeaving, "a broken egg after leaving")
        #expect(referee.arrivals == ["anna"])
        #expect(referee.results().entries.map(\.status) == [.finished(time: 50), .disconnected(meters: 0)])
    }

    @Test func rejectsReportsNoRunCanProduce() {
        var referee = race("anna")
        let impossible = [
            FinishReport(completed: true, time: .nan, meters: 150, eggsLost: 0),
            FinishReport(completed: true, time: -2, meters: 150, eggsLost: 0),
            FinishReport(completed: false, time: 9, meters: -1, eggsLost: 3),
            FinishReport(completed: true, time: 9, meters: 150, eggsLost: -1),
        ]
        for report in impossible {
            let accepted = referee.recordFinished(report, from: "anna")
            #expect(!accepted, "\(report)")
        }
        let infiniteProgress = referee.recordProgress(meters: .infinity, eggsLeft: 1, from: "anna")
        let negativeProgress = referee.recordProgress(meters: -5, eggsLeft: 1, from: "anna")
        #expect(!infiniteProgress)
        #expect(!negativeProgress)
        #expect(!referee.isComplete)
        #expect(referee.arrivals.isEmpty)
    }

    @Test func progressNeverGoesBackwards() throws {
        var referee = race("anna")
        referee.recordProgress(meters: 30, eggsLeft: 2, from: "anna")
        // An older packet arriving late.
        referee.recordProgress(meters: 25, eggsLeft: 3, from: "anna")
        let afterLatePacket = try #require(referee.runner("anna"))
        #expect(afterLatePacket.meters == 30)
        #expect(afterLatePacket.eggsLeft == 2)
        referee.recordEggDropped(eggsLeft: 1, from: "anna")
        #expect(try #require(referee.runner("anna")).eggsLeft == 1)
    }

    @Test func receiveRoutesRaceMessages() throws {
        var referee = race("anna", "ben")
        let recorded = [
            referee.receive(.progress(meters: 12.5, eggsLeft: 3), from: "ben"),
            referee.receive(.eggDropped(eggsLeft: 2), from: "ben"),
            referee.receive(.ready(true), from: "ben"),
            referee.receive(.ping(id: 1, sentAt: 3), from: "ben"),
        ]
        #expect(recorded == [true, true, false, false])
        let ben = try #require(referee.runner("ben"))
        #expect(ben.meters == 12.5)
        #expect(ben.eggsLeft == 2)
        let finished = referee.receive(.finished(completed(48)), from: "ben")
        #expect(finished)
        #expect(referee.arrivals == ["ben"])
    }

    @Test func rematchKeepsThePlayers() {
        var referee = race("anna", "ben", "cem")
        referee.recordFinished(completed(50), from: "anna")
        referee.recordProgress(meters: 33, eggsLeft: 1, from: "ben")
        referee.markDisconnected("cem")
        referee.recordFinished(outOfEggs(at: 70), from: "ben")
        #expect(referee.isComplete)

        referee.rematch()
        #expect(referee.runners.map(\.id) == ["anna", "ben"])
        #expect(referee.runners.allSatisfy { $0.meters == 0 && $0.eggsLeft == 3 && $0.report == nil })
        let everyoneConnected = referee.runners.allSatisfy(\.isConnected)
        #expect(everyoneConnected)
        #expect(referee.arrivals.isEmpty)
        #expect(!referee.isComplete)
        let accepted = referee.recordFinished(completed(47), from: "ben")
        #expect(accepted)
    }

    @Test func registeringAgainOnlyRenames() throws {
        var referee = race("anna")
        referee.recordProgress(meters: 20, eggsLeft: 2, from: "anna")
        referee.register("anna", nickname: "Anna B.")
        #expect(referee.runners.count == 1)
        let anna = try #require(referee.runner("anna"))
        #expect(anna.nickname == "Anna B.")
        #expect(anna.meters == 20)
    }

    @Test func refereesTheConnectedPlayersOfTheLobby() {
        var lobby = LobbyState(host: PlayerInfo(id: "anna", nickname: "Anna", eggSkinID: "classic"))
        lobby.join(PlayerInfo(id: "ben", nickname: "Ben", eggSkinID: "gold", isReady: true))
        lobby.join(PlayerInfo(id: "cem", nickname: "Cem", eggSkinID: "pearl", isReady: true))
        lobby.markDisconnected("cem")
        let referee = RaceReferee(lobby: lobby)
        #expect(referee.runners.map(\.id) == ["anna", "ben"])
        #expect(referee.runners.map(\.nickname) == ["Anna", "Ben"])
    }

    @Test func startsThreeSecondsAhead() {
        #expect(RaceReferee.startAt(hostNow: 1234.5) == 1237.5)
    }

    @Test func reportsAFinishedRun() throws {
        var run = RunEngine(course: RaceSettings(distance: .short).course, weather: .clear, localSeed: 7)
        var events: [RunEvent] = []
        #expect(FinishReport(run: run) == nil)
        for _ in 0 ..< 120 * 120 where !run.isOver {
            run.step(.level, events: &events)
        }
        let report = try #require(FinishReport(run: run))
        #expect(report == FinishReport(completed: true, time: run.elapsed, meters: 150, eggsLost: 0))
    }

    @Test func reportsARunOutOfEggs() throws {
        var run = RunEngine(course: .timeTrial(.long), weather: .clear, localSeed: 7)
        var events: [RunEvent] = []
        // Tilted 25° to the right, every egg rolls off.
        let steepTilt = RunEngine.Input(tilt: SIMD2(25 * Double.pi / 180, 0))
        for _ in 0 ..< 120 * 60 where !run.isOver {
            run.step(steepTilt, events: &events)
        }
        let report = try #require(FinishReport(run: run))
        #expect(!report.completed)
        #expect(report.eggsLost == 3)
        #expect(report.meters == run.meters)
        #expect(report.meters < 600)
    }
}
