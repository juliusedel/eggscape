@testable import Eggscape
import Foundation
import Testing

/// The player list of the hot-seat setup (`HotSeatSetupView`). Names are typed through `roster[nameOf:]`, the binding
/// the text fields use.
@MainActor
struct HotSeatRosterTests {
    /// Four rows named Ann, Ben, Cara and Dora.
    private func fourPlayers() -> HotSeatRoster {
        var roster = HotSeatRoster()
        roster.addPlayer()
        roster.addPlayer()
        for (player, name) in zip(roster.players, ["Ann", "Ben", "Cara", "Dora"]) {
            roster[nameOf: player.id] = name
        }
        return roster
    }

    /// The placeholder of the row at `number`, as the race names an empty row.
    private func placeholder(_ number: Int) -> String {
        String(localized: "Spieler \(number)")
    }

    @Test func startsWithTheFewestPlayersAndTakesUpToTheMost() {
        var roster = HotSeatRoster()
        #expect(roster.players.count == HotSeatSession.playerRange.lowerBound)
        #expect(roster.players.map(\.name) == ["", ""])
        while roster.canAddPlayer {
            roster.addPlayer()
        }
        #expect(roster.players.count == HotSeatSession.playerRange.upperBound)
        roster.addPlayer()
        #expect(roster.players.count == HotSeatSession.playerRange.upperBound)
        #expect(Set(roster.players.map(\.id)).count == roster.players.count, "every row has an id of its own")
    }

    @Test func neverDropsBelowTheFewestPlayers() {
        var roster = HotSeatRoster()
        #expect(!roster.canRemovePlayer)
        roster.removePlayers(atOffsets: [1])
        #expect(roster.players.count == 2)

        roster.addPlayer()
        #expect(roster.canRemovePlayer)
        // Two at once would leave one player.
        roster.removePlayers(atOffsets: [0, 1])
        #expect(roster.players.count == 3)
        roster.removePlayers(atOffsets: [3])
        #expect(roster.players.count == 3, "a position that does not exist changes nothing")
        roster.removePlayers(atOffsets: [0])
        #expect(roster.players.count == 2)
        #expect(!roster.canRemovePlayer)
    }

    /// The steps of the audit: four players, type in the third, delete it while its keyboard is up, delete the second,
    /// start the race.
    @Test func deletingRowsKeepsTheOtherNames() {
        var roster = fourPlayers()
        let dora = roster.players[3].id
        roster.removePlayers(atOffsets: [2])
        roster.removePlayers(atOffsets: [1])
        #expect(roster.players.map(\.name) == ["Ann", "Dora"])
        #expect(roster.players[1].id == dora, "a row keeps its id when rows before it go")
        #expect(roster.playerNames == ["Ann", "Dora"])
        let numbers = roster.players.map { roster.number(of: $0) }
        #expect(numbers == [1, 2])
    }

    @Test func aDeletedRowNeitherReadsNorWritesAnotherRowsName() {
        var roster = fourPlayers()
        let cara = roster.players[2].id
        let dora = roster.players[3].id
        roster.removePlayers(atOffsets: [2])
        // What the text field of a row that is going away would do while it is still being edited.
        #expect(roster[nameOf: cara].isEmpty)
        roster[nameOf: cara] = "Carla"
        #expect(roster.players.map(\.name) == ["Ann", "Ben", "Dora"])

        // The last row: by position its field would point past the end of the list.
        roster.removePlayers(atOffsets: [2])
        #expect(roster[nameOf: dora].isEmpty)
        roster[nameOf: dora] = "Dorothea"
        #expect(roster.players.map(\.name) == ["Ann", "Ben"])
    }

    @Test func namesAreCutToTheLengthOfANickname() {
        var roster = HotSeatRoster()
        roster[nameOf: roster.players[0].id] = String(repeating: "x", count: 40)
        // Characters, not bytes: 20 eggs are 80 bytes.
        roster[nameOf: roster.players[1].id] = String(repeating: "🥚", count: 20)
        roster.limitNames()
        #expect(roster.players[0].name == String(repeating: "x", count: SettingsStore.maxNameLength))
        #expect(roster.players[1].name == String(repeating: "🥚", count: SettingsStore.maxNameLength))
    }

    @Test func emptyRowsAreNumberedByTheirPlace() {
        var roster = HotSeatRoster()
        roster.addPlayer()
        roster.addPlayer()
        roster[nameOf: roster.players[1].id] = " Ben "
        roster[nameOf: roster.players[3].id] = "  "
        #expect(roster.playerNames == [placeholder(1), "Ben", placeholder(3), placeholder(4)])

        // The placeholders follow the rows' new places.
        roster.removePlayers(atOffsets: [0])
        #expect(roster.playerNames == ["Ben", placeholder(2), placeholder(3)])
        let numbers = roster.players.map { roster.number(of: $0) }
        #expect(numbers == [1, 2, 3])
    }

    @Test func theFirstRowGetsThePlayersOwnNameUnlessSomethingWasTyped() {
        var roster = HotSeatRoster()
        roster.prefillFirstName("")
        #expect(roster.players[0].name.isEmpty)
        roster.prefillFirstName("Julius")
        #expect(roster.players.map(\.name) == ["Julius", ""])
        roster[nameOf: roster.players[0].id] = "Mia"
        roster.prefillFirstName("Julius")
        #expect(roster.players[0].name == "Mia")
    }
}
