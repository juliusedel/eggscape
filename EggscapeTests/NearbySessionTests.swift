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
    private(set) var hostingStarts = 0
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

    func startHosting() {
        hostingStarts += 1
    }

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

/// Finding each other nearby: the help after a while without a room or a player, and a fresh search when iOS turned
/// one down, for example while its Local Network prompt was up. Only joiners wait in these tests: a host's room keeps
/// the screen awake (see `NearbyJoinTests`), so its wait is ended by hand.
@MainActor
struct NearbyDiscoveryTests {
    private let mia = DiscoveredRoom(id: "peer-mia", hostName: "Mia", playerCount: nil)
    private let jonas = RemotePeer(id: "peer-jonas", displayName: "Jonas")

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

    /// A host room with nobody in it yet; `fake` lets Jonas in once he connects.
    private func makeHost(_ fake: FakeNearbyTransport) throws -> NearbySession {
        let request = JoinRequest(playerID: "jonas", nickname: "Jonas", eggSkinID: SkinCatalog.defaultSkinID)
        fake.joinContexts[jonas.id] = try JSONEncoder().encode(request)
        return NearbySession(role: .host, services: makeServices(), nearby: fake)
    }

    /// Waits up to five seconds for `condition`.
    private func wait(until condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func aJoinerWithoutRoomsGetsHelpAfterAWhile() async {
        let fake = FakeNearbyTransport()
        let joiner = NearbySession(role: .joiner, services: makeServices(), nearby: fake)
        defer { joiner.leave() }
        joiner.helpDelay = .milliseconds(50)
        #expect(joiner.isWaitingForOthers)
        #expect(!joiner.isWaitingLong)

        await wait { joiner.isWaitingLong }
        #expect(joiner.isWaitingLong)

        // A room turns up: the list shows it, and the help goes.
        fake.onRoomsChanged([mia])
        #expect(!joiner.isWaitingForOthers)
        #expect(!joiner.isWaitingLong)
    }

    @Test func aListWithARoomNeedsNoHelp() async {
        let fake = FakeNearbyTransport()
        let joiner = NearbySession(role: .joiner, services: makeServices(), nearby: fake)
        defer { joiner.leave() }
        fake.onRoomsChanged([mia])
        joiner.helpDelay = .milliseconds(20)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(!joiner.isWaitingLong)
    }

    @Test func aHostAloneWaitsForPlayersAndGetsHelp() throws {
        let fake = FakeNearbyTransport()
        let room = try makeHost(fake)
        defer { room.leave() }
        // "Warte auf Mitspieler …", and the help once the wait is over.
        #expect(room.isWaitingForOthers)
        #expect(!room.isWaitingLong)
        room.helpDelayElapsed()
        #expect(room.isWaitingLong)

        room.handle(.connected(jonas))
        #expect(!room.isWaitingForOthers)
        #expect(!room.isWaitingLong)
        room.helpDelayElapsed()
        #expect(!room.isWaitingLong, "a room with a player needs no help")

        // Alone again: the help takes its time anew.
        room.handle(.disconnected(jonas))
        #expect(room.isWaitingForOthers)
        #expect(!room.isWaitingLong)
    }

    @Test func aSearchIOSTurnedDownStartsOverInsteadOfEndingTheRoom() async {
        let fake = FakeNearbyTransport()
        let joiner = NearbySession(role: .joiner, services: makeServices(), nearby: fake)
        defer { joiner.leave() }
        joiner.discoveryRetryDelay = .milliseconds(20)
        #expect(fake.browsingStarts == 1)

        joiner.handle(.discoveryFailed("denied while the prompt was up"))
        // Not the dead end of "Verbindung verloren".
        #expect(joiner.stage == .browsing)
        #expect(joiner.joinFailure == nil)
        await wait { fake.browsingStarts == 2 }
        #expect(fake.browsingStarts == 2)
    }

    @Test func aRoomIOSTurnedDownStaysOpenAndIsAdvertisedAnew() throws {
        let fake = FakeNearbyTransport()
        let room = try makeHost(fake)
        defer { room.leave() }
        room.handle(.connected(jonas))
        #expect(fake.hostingStarts == 1)

        room.handle(.discoveryFailed("denied while the prompt was up"))
        #expect(room.stage == .lobby)
        #expect(room.lobby.player(PlayerID("jonas")) != nil)
        // Back from the prompt the room does not wait out the pause, although it has a player.
        room.appBecameActive()
        #expect(fake.hostingStarts == 2)
        room.appBecameActive()
        #expect(fake.hostingStarts == 2, "nothing was due anymore")
    }

    @Test func comingBackStartsOverWhatFoundNobody() throws {
        let fake = FakeNearbyTransport()
        let joiner = NearbySession(role: .joiner, services: makeServices(), nearby: fake)
        defer { joiner.leave() }
        joiner.appBecameActive()
        #expect(fake.browsingStarts == 2, "an empty list looks again")
        fake.onRoomsChanged([mia])
        joiner.appBecameActive()
        #expect(fake.browsingStarts == 2, "a list with rooms works")
        joiner.join(mia)
        fake.onRoomsChanged([])
        joiner.appBecameActive()
        #expect(fake.browsingStarts == 2, "a joiner on its way into a room does not look again")

        let hostFake = FakeNearbyTransport()
        let room = try makeHost(hostFake)
        defer { room.leave() }
        room.appBecameActive()
        #expect(hostFake.hostingStarts == 2, "a room nobody found is advertised anew")
        room.handle(.connected(jonas))
        room.appBecameActive()
        #expect(hostFake.hostingStarts == 2, "a room with a player works")
    }

    @Test func retriesWaitLongerAfterEveryFailure() {
        let delays = (1 ... 6).map { NearbySession.retryDelay(afterFailures: $0, first: .seconds(2)) }
        #expect(delays == [.seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(30), .seconds(30)])
        #expect(NearbySession.retryDelay(afterFailures: 1000, first: .seconds(2)) == .seconds(30))
    }
}

/// Numbers from other phones: JSON carries any finite number, and a modified phone could send one that crashes the
/// others when they show it. A joiner in a lobby or a race keeps the screen awake, so these tests never wait.
@MainActor
struct NearbyNumbersTests {
    private let mia = RemotePeer(id: "peer-mia", displayName: "Mia")

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

    /// `message` as Mia's phone, the host, sends it.
    private func fromMia(_ message: NetMessage) throws -> TransportEvent {
        try .received(NetCodec().encode(message, from: PlayerID("Mia")), from: mia)
    }

    /// A joiner in Mia's lobby.
    private func makeJoiner() throws -> NearbySession {
        let joiner = NearbySession(role: .joiner, services: makeServices(), nearby: FakeNearbyTransport())
        joiner.join(DiscoveredRoom(id: mia.id, hostName: mia.displayName, playerCount: nil))
        joiner.handle(.connected(mia))
        var lobby = LobbyState(host: PlayerInfo(id: PlayerID("Mia"), nickname: "Mia", eggSkinID: "classic"))
        lobby.join(joiner.me)
        try joiner.handle(fromMia(.lobbyState(lobby)))
        return joiner
    }

    /// Mia won in `time` seconds.
    private func results(_ time: Double) -> RaceResults {
        let entry = RaceResultEntry(
            place: 1,
            playerID: PlayerID("Mia"),
            nickname: "Mia",
            status: .finished(time: time),
            eggsLost: 0
        )
        return RaceResults(entries: [entry])
    }

    @Test func resultsNoRaceCanProduceAreDropped() throws {
        let joiner = try makeJoiner()
        defer { joiner.leave() }
        #expect(joiner.stage == .lobby)
        try joiner.handle(fromMia(.results(results(1e300))))
        #expect(joiner.stage == .lobby)
        try joiner.handle(fromMia(.results(results(35.8))))
        #expect(joiner.stage == .results(results(35.8)))
    }

    @Test func progressNoRunCanProduceIsDropped() throws {
        let joiner = try makeJoiner()
        defer { joiner.leave() }
        try joiner.handle(fromMia(.startRace(seed: 7, startAt: 5)))
        let run = try #require(joiner.run)
        #expect(run.opponents.map(\.meters) == [0])
        for (meters, eggsLeft) in [(1e300, 2), (-1, 2), (12.5, 7), (12.5, -1)] {
            try joiner.handle(fromMia(.progress(meters: meters, eggsLeft: eggsLeft)))
        }
        try joiner.handle(fromMia(.finished(FinishReport(completed: true, time: 1e300, meters: 15, eggsLost: 0))))
        #expect(run.opponents.map(\.meters) == [0])
        #expect(run.opponents.map(\.eggsLeft) == [GameConfig.standard.eggsPerRun])
        #expect(run.opponents.map(\.isDone) == [false])

        try joiner.handle(fromMia(.progress(meters: 12.5, eggsLeft: 2)))
        #expect(run.opponents.map(\.meters) == [12.5])
        #expect(run.opponents.map(\.eggsLeft) == [2])
    }

    @Test(arguments: [-1e300, 1e300])
    func aFarOffStartStillStartsWithinSeconds(hostTime: Double) throws {
        let joiner = try makeJoiner()
        defer { joiner.leave() }
        // A pong whose clock reading puts the host's clock 1e300 seconds away: `startAt` then converts to a start
        // 1e300 seconds ahead or behind.
        try joiner.handle(fromMia(.pong(id: 0, pingSentAt: 0, hostTime: hostTime)))
        let before = ContinuousClock.now
        try joiner.handle(fromMia(.startRace(seed: 7, startAt: 5)))
        let startAt = try #require(joiner.run?.race?.startAt)
        #expect(startAt >= before + .seconds(RaceReferee.startDelays.lowerBound))
        #expect(startAt <= .now + .seconds(RaceReferee.startDelays.upperBound))
    }

    /// A host whose app was suspended mid-race for over an hour, during a call or with the phone locked: its race
    /// clock ran on (`RunSession.end()`), and MultipeerConnectivity dropped the joiners meanwhile. Its own finish has
    /// to count, or it waits for the others forever.
    @Test func aHostBackAfterAnHourStillGetsTheResults() throws {
        let fake = FakeNearbyTransport()
        let jonas = RemotePeer(id: "peer-jonas", displayName: "Jonas")
        let request = JoinRequest(playerID: "jonas", nickname: "Jonas", eggSkinID: SkinCatalog.defaultSkinID)
        fake.joinContexts[jonas.id] = try JSONEncoder().encode(request)
        let room = NearbySession(role: .host, services: makeServices(), nearby: fake)
        defer { room.leave() }
        room.handle(.connected(jonas))
        try room.handle(.received(NetCodec().encode(.ready(true), from: PlayerID("jonas")), from: jonas))
        room.startRace()
        let run = try #require(room.run)

        room.handle(.disconnected(jonas))
        run.race?.onFinished(RunOutcome(
            mode: run.setup.mode,
            finished: true,
            time: 3700,
            meters: run.setup.course.length ?? 0,
            eggsLost: 0,
            isPersonalBest: false,
            reward: nil
        ))
        guard case let .results(results) = room.stage else {
            Issue.record("The host still waits for the others")
            return
        }
        #expect(results.entry(for: room.me.id)?.status == .finished(time: NetMessage.plausibleSeconds.upperBound))
    }
}
