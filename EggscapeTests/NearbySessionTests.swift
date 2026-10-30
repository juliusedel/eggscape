@testable import Eggscape
import EggscapeCore
import Foundation
import Testing
import UIKit

/// A phone in a race room must not lock while it waits for the others: it would be suspended and drop out, and a host
/// would take the room down for everybody. Rooms without networking, so nothing is advertised or browsed.
@MainActor
struct NearbySessionTests {
    private func makeServices() -> AppServices {
        let suite = "eggscape.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return AppServices(
            settings: SettingsStore(defaults: defaults),
            records: RecordsStore(defaults: defaults),
            wallet: WalletStore(defaults: defaults)
        )
    }

    @Test func theRoomKeepsTheScreenAwakeUntilThePlayerLeaves() {
        let room = NearbySession(role: .host, services: makeServices(), networking: false)
        #expect(UIApplication.shared.isIdleTimerDisabled)
        room.leave()
        #expect(!UIApplication.shared.isIdleTimerDisabled)
        // Like a message that was already on its way: the stage of a room that was left changes once more.
        room.rematch()
        #expect(!UIApplication.shared.isIdleTimerDisabled)
    }

    @Test func lookingForARoomLetsTheScreenLock() {
        let joiner = NearbySession(role: .joiner, services: makeServices(), networking: false)
        defer { joiner.leave() }
        #expect(!UIApplication.shared.isIdleTimerDisabled)
        joiner.join(DiscoveredRoom(id: "mia", hostName: "Mia", playerCount: nil))
        #expect(joiner.stage == .connecting(host: "Mia"))
        #expect(!UIApplication.shared.isIdleTimerDisabled)
    }

    @Test func onlyTheRoomItselfKeepsTheScreenAwake() {
        #expect(NearbySession.Stage.lobby.keepsScreenAwake)
        #expect(NearbySession.Stage.racing.keepsScreenAwake)
        #expect(NearbySession.Stage.results(RaceResults(entries: [])).keepsScreenAwake)
        #expect(!NearbySession.Stage.browsing.keepsScreenAwake)
        #expect(!NearbySession.Stage.connecting(host: "Mia").keepsScreenAwake)
        #expect(!NearbySession.Stage.failed("Die Verbindung zum Raum ist abgebrochen.").keepsScreenAwake)
    }
}

/// Stands in for MultipeerConnectivity: records what the room asks of it, and the tests hand the room its events.
@MainActor
private final class FakeNearbyTransport: NearbyTransport {
    let events: AsyncStream<TransportEvent>
    private let continuation: AsyncStream<TransportEvent>.Continuation
    var connectedPeers: [RemotePeer] = []
    var onRoomsChanged: ([DiscoveredRoom]) -> Void = { _ in }
    var acceptsPlayers: () -> Bool = { true }
    /// What joiners sent with their invitations, by peer id.
    var joinContexts: [String: Data] = [:]
    private(set) var joinedRooms: [DiscoveredRoom] = []
    private(set) var cancelledJoins = 0
    private(set) var browsingStarts = 0
    private(set) var sent: [NetMessage] = []

    init() {
        (events, continuation) = AsyncStream.makeStream(of: TransportEvent.self)
    }

    func send(_ data: Data, to _: [RemotePeer]?, reliable _: Bool) {
        if let envelope = try? NetCodec().decode(data) {
            sent.append(envelope.message)
        }
    }

    func close() {
        continuation.finish()
    }

    func startHosting() {}
    func updateAdvertising() {}

    func startBrowsing() {
        browsingStarts += 1
    }

    func stopBrowsing() {}

    func join(_ room: DiscoveredRoom, context _: Data) {
        joinedRooms.append(room)
    }

    func cancelJoin() {
        cancelledJoins += 1
    }

    func joinContext(for peer: RemotePeer) -> Data? {
        joinContexts[peer.id]
    }
}

/// Joining a nearby room with a fake transport. The events are handed over one at a time, so no test waits while its
/// room holds the screen awake (`NearbySessionTests` checks that lease).
@MainActor
struct NearbyJoinTests {
    private let host = RemotePeer(id: "peer-mia", displayName: "Mia")

    private var room: DiscoveredRoom {
        DiscoveredRoom(id: host.id, hostName: host.displayName, playerCount: nil)
    }

    private func makeServices() -> AppServices {
        let suite = "eggscape.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return AppServices(
            settings: SettingsStore(defaults: defaults),
            records: RecordsStore(defaults: defaults),
            wallet: WalletStore(defaults: defaults)
        )
    }

    private func player(_ name: String, isHost: Bool = false) -> PlayerInfo {
        PlayerInfo(id: PlayerID(name), nickname: name, eggSkinID: SkinCatalog.defaultSkinID, isHost: isHost)
    }

    private func lobbyMessage(_ lobby: LobbyState) throws -> TransportEvent {
        try .received(NetCodec().encode(.lobbyState(lobby), from: PlayerID("Mia")), from: host)
    }

    @Test func aFailedJoinGoesBackToTheListAndSaysWhatHelps() {
        let fake = FakeNearbyTransport()
        let joiner = NearbySession(role: .joiner, services: makeServices(), nearby: fake)
        defer { joiner.leave() }
        joiner.join(room)
        #expect(joiner.stage == .connecting(host: "Mia"))
        #expect(fake.joinedRooms == [room])

        joiner.handle(.joinFailed(.declinedOrFailed))
        #expect(joiner.stage == .browsing)
        #expect(joiner.joinFailure == NearbySession.joinFailedMessage)
        #expect(fake.cancelledJoins == 1)
        // The init started browsing once; the room list starts over.
        #expect(fake.browsingStarts == 2)
    }

    @Test func aJoinFailureAfterGivingUpIsIgnored() {
        let fake = FakeNearbyTransport()
        let joiner = NearbySession(role: .joiner, services: makeServices(), nearby: fake)
        defer { joiner.leave() }
        joiner.join(room)
        joiner.cancelJoin()
        joiner.handle(.joinFailed(.expired))
        #expect(joiner.stage == .browsing)
        #expect(joiner.joinFailure == nil)
    }

    @Test func aHostThatDropsBeforeTheLobbyLeadsBackToTheList() {
        let fake = FakeNearbyTransport()
        let joiner = NearbySession(role: .joiner, services: makeServices(), nearby: fake)
        defer { joiner.leave() }
        joiner.join(room)
        joiner.handle(.connected(host))
        #expect(joiner.stage == .connecting(host: "Mia"))

        joiner.handle(.disconnected(host))
        // Not the dead end of "Verbindung verloren": joining again is one tap away.
        #expect(joiner.stage == .browsing)
        #expect(joiner.joinFailure == NearbySession.joinFailedMessage)
        #expect(fake.cancelledJoins == 1)
    }

    @Test func aLobbyThatNeverComesEndsTheJoin() async {
        let fake = FakeNearbyTransport()
        let joiner = NearbySession(role: .joiner, services: makeServices(), nearby: fake)
        defer { joiner.leave() }
        joiner.lobbyTimeout = .milliseconds(50)
        joiner.join(room)
        joiner.handle(.connected(host))

        // Waiting is safe here: neither "Verbinde …" nor the room list keeps the screen awake.
        let deadline = ContinuousClock.now + .seconds(5)
        while joiner.stage != .browsing, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(joiner.stage == .browsing)
        #expect(joiner.joinFailure == NearbySession.joinFailedMessage)
    }

    @Test func theLobbyLetsTheJoinerIn() throws {
        let fake = FakeNearbyTransport()
        let joiner = NearbySession(role: .joiner, services: makeServices(), nearby: fake)
        defer { joiner.leave() }
        joiner.join(room)
        joiner.handle(.connected(host))
        var lobby = LobbyState(host: player("Mia", isHost: true))
        lobby.join(joiner.me)

        try joiner.handle(lobbyMessage(lobby))
        #expect(joiner.stage == .lobby)
        #expect(joiner.joinFailure == nil)
    }

    @Test func aFullLobbySaysSo() throws {
        let fake = FakeNearbyTransport()
        let joiner = NearbySession(role: .joiner, services: makeServices(), nearby: fake)
        defer { joiner.leave() }
        joiner.join(room)
        joiner.handle(.connected(host))
        var lobby = LobbyState(host: player("Mia", isHost: true))
        for name in ["Jonas", "Lea", "Tom"] {
            lobby.join(player(name))
        }
        #expect(lobby.isFull)

        try joiner.handle(lobbyMessage(lobby))
        #expect(joiner.stage == .browsing)
        #expect(joiner.joinFailure == String(localized: "Der Raum ist voll."))
    }

    @Test func theHostSeatsAJoinerThatSentItsRequest() throws {
        let fake = FakeNearbyTransport()
        let room = NearbySession(role: .host, services: makeServices(), nearby: fake)
        defer { room.leave() }
        let joiner = RemotePeer(id: "peer-jonas", displayName: "Jonas")
        let request = JoinRequest(playerID: "jonas", nickname: "Jonas", eggSkinID: SkinCatalog.defaultSkinID)
        fake.joinContexts[joiner.id] = try JSONEncoder().encode(request)

        room.handle(.connected(joiner))
        #expect(room.lobby.player(PlayerID("jonas"))?.nickname == "Jonas")
        let lobbies = fake.sent.compactMap { message -> LobbyState? in
            if case let .lobbyState(state) = message {
                state
            } else {
                nil
            }
        }
        #expect(lobbies.last?.player(PlayerID("jonas")) != nil)
    }
}
