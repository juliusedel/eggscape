import EggscapeCore
import Foundation
import Observation
import os

/// What a joiner sends along with its invitation, so the host can list it with name and egg.
struct JoinRequest: Codable, Sendable {
    var playerID: String
    var nickname: String
    var eggSkinID: String
}

/// A race room for 2-4 phones. "In der Nähe": one phone hosts, the others join over MultipeerConnectivity. "Online":
/// everybody in a Game Center match, and the player with the lowest id hosts. The host is the referee: it keeps the
/// lobby, answers clock pings, picks the start time and decides the finish order. Every phone simulates its own run.
@MainActor
@Observable
final class NearbySession: Identifiable {
    enum Role {
        case host
        case joiner
    }

    enum Stage: Equatable {
        /// Joiner: looking for rooms.
        case browsing
        /// Joiner: waiting for the host to let us in.
        case connecting(host: String)
        case lobby
        case racing
        case results(RaceResults)
        case failed(String)
    }

    let role: Role
    let me: PlayerInfo
    /// A nearby host advertises the room only while it takes players, which depends on the stage and the lobby.
    private(set) var stage: Stage {
        didSet { nearby?.updateAdvertising() }
    }

    /// The host's lobby; joiners mirror the last `lobbyState` they received.
    private(set) var lobby: LobbyState {
        didSet { nearby?.updateAdvertising() }
    }

    /// Rooms found nearby while browsing.
    private(set) var rooms: [DiscoveredRoom] = []
    /// Joiner: why the last room could not be joined, shown with the room list until the next attempt.
    private(set) var joinFailure: String?
    /// The run of the current race.
    private(set) var run: RunSession?
    /// Coins this player earned in the last race.
    private(set) var reward: CoinReward?

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let transport: any PeerTransport
    /// The nearby transport, for discovery and join requests; `nil` online.
    @ObservationIgnored private let nearby: MultipeerTransport?
    @ObservationIgnored private let codec = NetCodec()
    @ObservationIgnored private var referee = RaceReferee()
    @ObservationIgnored private var clock = ClockSync()
    @ObservationIgnored private let epoch = ContinuousClock.now
    /// Host side: which player each connected phone is.
    @ObservationIgnored private var playersByPeer: [String: PlayerID] = [:]
    /// Joiner side: the phone that hosts the room, and the room we are joining.
    @ObservationIgnored private var hostPeer: RemotePeer?
    @ObservationIgnored private var joiningRoomID: String?
    @ObservationIgnored private var listener: Task<Void, Never>?
    @ObservationIgnored private var pinger: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "de.juliusedel.eggscape", category: "nearby")

    /// - Parameter networking: `false` only for the staged App Store screenshot (no prompt, no radio).
    init(role: Role, services: AppServices, networking: Bool = true) {
        self.role = role
        self.services = services
        me = PlayerInfo(
            id: PlayerID(UUID().uuidString),
            nickname: services.settings.displayName,
            eggSkinID: services.wallet.equippedSkin.id,
            isHost: role == .host,
            isReady: false,
            isConnected: true
        )
        lobby = LobbyState(host: me)
        let multipeer = MultipeerTransport(displayName: services.settings.displayName)
        transport = multipeer
        nearby = multipeer
        stage = role == .host ? .lobby : .browsing
        multipeer.acceptsPlayers = { [weak self] in
            guard let self else { return false }
            return stage == .lobby && !lobby.isFull
        }
        multipeer.onRoomsChanged = { [weak self] rooms in self?.rooms = rooms }
        guard networking else { return }
        listen()
        switch role {
        case .host:
            multipeer.startHosting()
        case .joiner:
            multipeer.startBrowsing()
        }
    }

    /// Online: everybody in the Game Center match races; the player with the lowest id is the referee. Only for a
    /// match with every player connected (`GameKitTransport.waitForAllPlayers`), so all phones agree on the referee.
    init(match: GameKitTransport, services: AppServices) {
        self.services = services
        role = match.refereeID == match.localPlayerID ? .host : .joiner
        me = PlayerInfo(
            id: PlayerID(match.localPlayerID),
            nickname: match.localDisplayName,
            eggSkinID: services.wallet.equippedSkin.id,
            isHost: role == .host,
            isReady: false,
            isConnected: true
        )
        lobby = LobbyState(host: me)
        transport = match
        nearby = nil
        let referee = match.refereePeer
        stage = role == .host ? .lobby : .connecting(host: referee?.displayName ?? "")
        hostPeer = role == .host ? nil : referee
        listen()
        if role == .joiner {
            startPinging()
        }
    }

    /// A staged lobby for App Store screenshots: three friends, no networking.
    static func screenshotLobby(services: AppServices) -> NearbySession {
        let session = NearbySession(role: .host, services: services, networking: false)
        let friends = [("Mia", "sky-blue", true), ("Jonas", "polka-dots", true), ("Lea", "gold-metallic", false)]
        for (name, skin, ready) in friends {
            _ = session.lobby.join(PlayerInfo(
                id: PlayerID(name),
                nickname: name,
                eggSkinID: skin,
                isHost: false,
                isReady: ready,
                isConnected: true
            ))
        }
        session.lobby.settings = RaceSettings(distance: .medium, weather: .random)
        return session
    }

    var isHost: Bool {
        role == .host
    }

    /// A nearby room rather than an online match: joiners pick it from a list.
    var isNearby: Bool {
        nearby != nil
    }

    /// Seconds on this phone's monotonic clock since the session began.
    private var now: Double {
        (ContinuousClock.now - epoch).seconds
    }

    // MARK: Lobby actions

    func join(_ room: DiscoveredRoom) {
        guard stage == .browsing else { return }
        let request = JoinRequest(playerID: me.id.rawValue, nickname: me.nickname, eggSkinID: me.eggSkinID)
        guard let context = try? JSONEncoder().encode(request) else { return }
        joinFailure = nil
        stage = .connecting(host: room.hostName)
        joiningRoomID = room.id
        nearby?.join(room, context: context)
    }

    /// Nearby joiner: stops waiting for the host and goes back to the room list.
    func cancelJoin() {
        guard let nearby, case .connecting = stage else { return }
        nearby.cancelJoin()
        returnToRoomList()
    }

    /// Joiner: gives up on the room because of `reason`. Nearby, the room list shows it; online, there is no list.
    private func leaveRoom(_ reason: String) {
        guard let nearby else {
            leave()
            stage = .failed(reason)
            return
        }
        nearby.cancelJoin()
        returnToRoomList()
        joinFailure = reason
    }

    /// Nearby joiner: looks for rooms again, with a fresh list. The clock round trips go too, because the next host's
    /// clock has a zero point of its own.
    private func returnToRoomList() {
        pinger?.cancel()
        clock.reset()
        hostPeer = nil
        joiningRoomID = nil
        stage = .browsing
        nearby?.startBrowsing()
    }

    /// Host only: distance and weather for the next race.
    func setSettings(_ settings: RaceSettings) {
        guard isHost, stage == .lobby else { return }
        lobby.settings = settings
        broadcast(.setSettings(settings))
        broadcastLobby()
    }

    /// Calibrates the current pose (the race starts from it) and reports "bereit", or takes it back.
    func setReady(_ isReady: Bool) {
        if isReady, let raw = services.motion.tilt {
            services.settings.calibrationZero = raw
        }
        if isHost {
            lobby.setReady(isReady, for: me.id)
            broadcastLobby()
        } else {
            send(.ready(isReady), to: hostPeer.map { [$0] })
            lobby.setReady(isReady, for: me.id)
        }
    }

    var isReady: Bool {
        lobby.player(me.id)?.isReady ?? false
    }

    /// Host only: everybody is ready, start in three seconds.
    func startRace() {
        guard isHost, stage == .lobby, lobby.canStart else { return }
        referee = RaceReferee(lobby: lobby)
        let seed = UInt64.random(in: .min ... .max)
        let startAt = RaceReferee.startAt(hostNow: now)
        broadcast(.startRace(seed: seed, startAt: startAt))
        beginRace(seed: seed, startsIn: startAt - now)
    }

    /// Host only: "Nochmal" with the players who are still there.
    func rematch() {
        guard isHost else { return }
        referee.rematch()
        lobby.removeDisconnected()
        lobby.resetReadiness()
        reward = nil
        run = nil
        stage = .lobby
        broadcastLobby()
    }

    func leave() {
        pinger?.cancel()
        listener?.cancel()
        run?.stop()
        transport.close()
    }

    // MARK: Race

    private func beginRace(seed: UInt64, startsIn seconds: Double) {
        let settings = lobby.settings
        let setup = RunSetup(mode: .timeTrial(settings.distance, settings.weather), raceSeed: seed)
        let hooks = RaceHooks(
            startAt: .now + .seconds(max(seconds, 0.5)),
            onProgress: { [weak self] meters, eggsLeft in
                self?.reportProgress(meters: meters, eggsLeft: eggsLeft)
            },
            onEggDropped: { [weak self] eggsLeft in
                self?.reportEggDropped(eggsLeft: eggsLeft)
            },
            onFinished: { [weak self] outcome in
                self?.reportFinish(outcome)
            }
        )
        let session = RunSession(setup: setup, services: services, rules: .race, race: hooks)
        session.opponents = lobby.connectedPlayers.filter { $0.id != me.id }.map { player in
            OpponentProgress(
                id: player.id.rawValue,
                name: player.nickname,
                meters: 0,
                eggsLeft: GameConfig.standard.eggsPerRun,
                isConnected: player.isConnected,
                isDone: false
            )
        }
        reward = nil
        run = session
        stage = .racing
    }

    private func reportProgress(meters: Double, eggsLeft: Int) {
        broadcast(.progress(meters: meters, eggsLeft: eggsLeft))
        if isHost {
            _ = referee.recordProgress(meters: meters, eggsLeft: eggsLeft, from: me.id)
        }
    }

    private func reportEggDropped(eggsLeft: Int) {
        broadcast(.eggDropped(eggsLeft: eggsLeft))
        if isHost {
            _ = referee.recordEggDropped(eggsLeft: eggsLeft, from: me.id)
        }
    }

    private func reportFinish(_ outcome: RunOutcome) {
        let report = FinishReport(
            completed: outcome.finished,
            time: outcome.time,
            meters: outcome.meters,
            eggsLost: outcome.eggsLost
        )
        broadcast(.finished(report))
        if isHost {
            _ = referee.recordFinished(report, from: me.id)
            finishIfComplete()
        }
    }

    /// Host: once every connected racer has finished or run out of eggs, everybody gets the results.
    private func finishIfComplete() {
        guard isHost, stage == .racing, referee.isComplete else { return }
        let results = referee.results()
        broadcast(.results(results))
        show(results)
    }

    private func show(_ results: RaceResults) {
        if let entry = results.entry(for: me.id), let run {
            let earned = CoinRewards.reward(for: RewardInput(
                course: run.setup.course,
                weather: run.setup.mode.weather,
                finished: {
                    if case .finished = entry.status {
                        true
                    } else {
                        false
                    }
                }(),
                meters: run.hud.meters,
                eggsLost: entry.eggsLost,
                multiplayerPlace: entry.place,
                playerCount: results.entries.count
            ))
            services.wallet.earn(earned)
            reward = earned
        }
        stage = .results(results)
    }

    // MARK: Messages

    private func listen() {
        listener = Task { [weak self, transport] in
            for await event in transport.events {
                self?.handle(event)
            }
        }
    }

    private func handle(_ event: TransportEvent) {
        switch event {
        case let .connected(peer):
            peerConnected(peer)
        case let .disconnected(peer):
            peerDisconnected(peer)
        case let .received(data, peer):
            do {
                let envelope = try codec.decode(data)
                receive(envelope.message, from: envelope.sender, peer: peer)
            } catch {
                logger.error("Dropped a message: \(String(describing: error))")
            }
        case .joinFailed:
            guard case .connecting = stage else { return }
            leaveRoom(String(localized: "Der Raum ist voll oder das Rennen läuft schon."))
        case let .failed(message):
            stage = .failed(message)
        }
    }

    private func peerConnected(_ peer: RemotePeer) {
        switch role {
        case .host:
            let request: JoinRequest
            if let nearby {
                // Nearby joiners announce themselves with their invitation.
                guard let data = nearby.joinContext(for: peer),
                      let decoded = try? JSONDecoder().decode(JoinRequest.self, from: data)
                else { return }
                request = decoded
            } else {
                // Online players are known by their Game Center id and name.
                request = JoinRequest(
                    playerID: peer.id,
                    nickname: peer.displayName,
                    eggSkinID: SkinCatalog.defaultSkinID
                )
            }
            let id = PlayerID(request.playerID)
            let player = PlayerInfo(
                id: id,
                nickname: request.nickname,
                eggSkinID: request.eggSkinID,
                isHost: false,
                isReady: false,
                isConnected: true
            )
            guard lobby.join(player) else {
                // No seat left: a full lobby without the phone in it tells it so, and it leaves.
                send(.lobbyState(lobby), to: [peer])
                return
            }
            playersByPeer[peer.id] = id
            broadcastLobby()
        case .joiner:
            // Other joiners connect too (the session is a mesh); only the room's phone is the host.
            if hostPeer == nil, peer.id == joiningRoomID {
                hostPeer = peer
                nearby?.stopBrowsing()
                startPinging()
            }
        }
    }

    private func peerDisconnected(_ peer: RemotePeer) {
        switch role {
        case .host:
            guard let id = playersByPeer[peer.id] else { return }
            lobby.markDisconnected(id)
            if stage == .racing {
                referee.markDisconnected(id)
                markOpponent(id) { $0.isConnected = false }
                // Before the results that may follow: a later `lobbyState` would end the joiners' results.
                broadcastLobby()
                finishIfComplete()
            } else {
                lobby.remove(id)
                broadcastLobby()
            }
        case .joiner:
            if peer == hostPeer {
                pinger?.cancel()
                stage = .failed(String(localized: "Die Verbindung zum Raum ist abgebrochen."))
            }
        }
    }

    private func receive(_ message: NetMessage, from sender: PlayerID, peer: RemotePeer) {
        // Only the host may change the lobby, start a race, announce results or answer pings.
        if message.isHostOnly {
            guard !isHost, peer == hostPeer else { return }
        }
        switch message {
        case let .lobbyState(state):
            guard state.player(me.id) != nil else {
                // Until the host has added us, only a full lobby means there is no seat; after that, we were dropped.
                if case .connecting = stage, !state.isFull {
                    return
                }
                leaveRoom(String(localized: "Der Raum ist voll."))
                return
            }
            lobby = state
            for player in state.players where player.id != me.id {
                markOpponent(player.id) { $0.isConnected = player.isConnected }
            }
            if case .connecting = stage {
                stage = .lobby
            } else if case .results = stage {
                run = nil
                stage = .lobby
            }
        case let .setSettings(settings):
            lobby.settings = settings
        case let .ready(isReady):
            guard isHost else { return }
            lobby.setReady(isReady, for: sender)
            broadcastLobby()
        case let .startRace(seed, startAt):
            guard !isHost else { return }
            let startsIn = clock.localTime(fromHost: startAt).map { $0 - now } ?? RaceReferee.startDelay
            beginRace(seed: seed, startsIn: startsIn)
        case let .progress(meters, eggsLeft):
            markOpponent(sender) { opponent in
                opponent.meters = meters
                opponent.eggsLeft = eggsLeft
            }
            if isHost {
                _ = referee.recordProgress(meters: meters, eggsLeft: eggsLeft, from: sender)
            }
        case let .eggDropped(eggsLeft):
            markOpponent(sender) { $0.eggsLeft = eggsLeft }
            if let name = lobby.player(sender)?.nickname {
                run?.showToast(String(localized: "\(name) hat ein Ei verloren"))
            }
            if isHost {
                _ = referee.recordEggDropped(eggsLeft: eggsLeft, from: sender)
            }
        case let .finished(report):
            markOpponent(sender) { opponent in
                opponent.isDone = true
                opponent.meters = report.meters
            }
            if isHost {
                _ = referee.recordFinished(report, from: sender)
                finishIfComplete()
            }
        case let .results(results):
            guard !isHost else { return }
            show(results)
        case .ping:
            guard isHost, let reply = ClockSync.reply(to: message, hostTime: now) else { return }
            send(reply, to: [peer])
        case .pong:
            guard !isHost else { return }
            _ = clock.receive(message, receivedAt: now)
        }
    }

    private func markOpponent(_ id: PlayerID, _ change: (inout OpponentProgress) -> Void) {
        guard let run, let index = run.opponents.firstIndex(where: { $0.id == id.rawValue }) else { return }
        change(&run.opponents[index])
    }

    /// Joiners keep measuring the clock offset to the host, so the countdown starts at the same moment everywhere.
    private func startPinging() {
        pinger?.cancel()
        pinger = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let ping = clock.makePing(localNow: now)
                send(ping, to: hostPeer.map { [$0] })
                let interval: Duration = stage == .racing ? .seconds(2) : .milliseconds(400)
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Not while showing results: joiners take the next `lobbyState` as the host's "Nochmal".
    private func broadcastLobby() {
        if case .results = stage {
            return
        }
        broadcast(.lobbyState(lobby))
    }

    private func broadcast(_ message: NetMessage) {
        send(message, to: nil)
    }

    private func send(_ message: NetMessage, to peers: [RemotePeer]?) {
        do {
            let data = try codec.encode(message, from: me.id)
            transport.send(data, to: peers, reliable: message.delivery == .reliable)
        } catch {
            logger.error("Could not encode \(message.kind.rawValue)")
        }
    }
}
