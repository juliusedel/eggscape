@testable import EggscapeCore
import Testing

private func player(_ id: PlayerID, ready: Bool = false) -> PlayerInfo {
    PlayerInfo(id: id, nickname: id.rawValue, eggSkinID: "classic", isReady: ready)
}

/// A lobby hosted by "host" with `joiners` joined in order.
private func makeLobby(_ joiners: PlayerInfo...) -> LobbyState {
    var lobby = LobbyState(host: player("host"))
    for joiner in joiners {
        lobby.join(joiner)
    }
    return lobby
}

struct LobbyStateTests {
    @Test func aNewLobbyHasOnlyTheHost() {
        let lobby = makeLobby()
        #expect(lobby.hostID == "host")
        #expect(lobby.players.map(\.id) == ["host"])
        #expect(lobby.host?.isHost == true)
        #expect(lobby.settings == .standard)
    }

    @Test func aRaceNeedsAnOpponent() {
        #expect(!makeLobby().canStart)
        #expect(makeLobby(player("ben", ready: true)).canStart)
    }

    @Test func everyConnectedJoinerMustBeReady() {
        var lobby = makeLobby(player("ben", ready: true), player("cem"))
        #expect(!lobby.canStart)
        lobby.setReady(true, for: "cem")
        #expect(lobby.canStart)
        lobby.setReady(false, for: "ben")
        #expect(!lobby.canStart)
    }

    @Test func theHostStartsWithoutBeingMarkedReady() {
        let lobby = makeLobby(player("ben", ready: true))
        #expect(lobby.host?.isReady == false)
        #expect(lobby.canStart)
    }

    @Test func playersWhoLeftDoNotBlockTheStart() {
        var lobby = makeLobby(player("ben", ready: true), player("cem"))
        lobby.markDisconnected("cem")
        #expect(lobby.canStart)
        #expect(lobby.player("cem")?.isConnected == false)
        // ... but they do not count as opponents either.
        lobby.markDisconnected("ben")
        #expect(!lobby.canStart)
    }

    @Test func withoutTheHostNobodyStarts() {
        var lobby = makeLobby(player("ben", ready: true), player("cem", ready: true))
        lobby.markDisconnected("host")
        #expect(!lobby.canStart)
    }

    @Test func fourPlayersAtMost() {
        var lobby = makeLobby(player("ben", ready: true), player("cem", ready: true), player("dana", ready: true))
        #expect(lobby.isFull)
        #expect(lobby.canStart)
        let joined = lobby.join(player("emil", ready: true))
        #expect(!joined)
        #expect(lobby.players.map(\.id) == ["host", "ben", "cem", "dana"])

        // A lobby that got too crowded some other way cannot start either.
        let crowded = LobbyState(hostID: "host", players: lobby.players + [player("emil", ready: true)])
        #expect(!crowded.canStart)
    }

    @Test func aSeatFreesUpWhenSomeoneLeaves() {
        var lobby = makeLobby(player("ben", ready: true), player("cem", ready: true), player("dana", ready: true))
        lobby.markDisconnected("dana")
        #expect(!lobby.isFull)
        let emilJoined = lobby.join(player("emil", ready: true))
        #expect(emilJoined)
        #expect(lobby.canStart)
        // Now Dana cannot come back: the lobby is full again.
        let danaRejoined = lobby.join(player("dana", ready: true))
        #expect(!danaRejoined)
        #expect(lobby.player("dana")?.isConnected == false)
    }

    @Test func rejoiningReplacesTheEntry() throws {
        var lobby = makeLobby(player("ben", ready: true), player("cem"))
        lobby.markDisconnected("ben")
        var ben = player("ben")
        ben.nickname = "Benni"
        ben.eggSkinID = "pearl"
        // Only `hostID` decides who hosts.
        ben.isHost = true
        let rejoined = lobby.join(ben)
        #expect(rejoined)
        #expect(lobby.players.map(\.id) == ["host", "ben", "cem"])
        let entry = try #require(lobby.player("ben"))
        #expect(entry.nickname == "Benni")
        #expect(entry.eggSkinID == "pearl")
        #expect(entry.isConnected)
        #expect(!entry.isHost)
    }

    @Test func leavingClearsReadiness() {
        var lobby = makeLobby(player("ben", ready: true))
        lobby.markDisconnected("ben")
        #expect(lobby.player("ben")?.isReady == false)
    }

    @Test func everyoneConfirmsAgainAfterARace() {
        var lobby = makeLobby(player("ben", ready: true), player("cem", ready: true))
        lobby.resetReadiness()
        #expect(lobby.players.allSatisfy { !$0.isReady })
        #expect(!lobby.canStart)
    }

    @Test func removingAPlayerDropsTheEntry() {
        var lobby = makeLobby(player("ben", ready: true), player("cem"))
        lobby.remove("cem")
        #expect(lobby.players.map(\.id) == ["host", "ben"])
        #expect(lobby.canStart)
    }

    @Test func unknownPlayersAreIgnored() {
        var lobby = makeLobby(player("ben", ready: true))
        let before = lobby
        lobby.setReady(false, for: "zoe")
        lobby.markDisconnected("zoe")
        lobby.remove("zoe")
        #expect(lobby == before)
    }

    @Test func multiplayerRacesAreTimeTrials() {
        #expect(RaceSettings(distance: .medium, weather: .random).course == .timeTrial(.medium))
        #expect(RaceSettings.standard == RaceSettings(distance: .short, weather: .off))
    }
}
