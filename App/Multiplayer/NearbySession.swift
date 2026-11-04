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

        /// The host's name while joining its room.
        var connectingHost: String? {
            if case let .connecting(host) = self {
                host
            } else {
                nil
            }
        }

        /// In the room the players wait for each other: in the lobby, for the others to finish and over the results. A
        /// phone that locks meanwhile is suspended and drops out, and a host takes the room down for everybody.
        var keepsScreenAwake: Bool {
            switch self {
            case .lobby, .racing, .results: true
            case .browsing, .connecting, .failed: false
            }
        }
    }

    let role: Role
    let me: PlayerInfo
    /// A nearby host advertises the room only while it takes players, which depends on the stage and the lobby.
    private(set) var stage: Stage {
        didSet {
            nearby?.updateAdvertising()
            updateIdleTimer()
            updateWaitingHelp()
        }
    }

    /// The host's lobby; joiners mirror the last `lobbyState` they received.
    private(set) var lobby: LobbyState {
        didSet {
            nearby?.updateAdvertising()
            updateWaitingHelp()
        }
    }

    /// Rooms found nearby while browsing.
    private(set) var rooms: [DiscoveredRoom] = [] {
        didSet { updateWaitingHelp() }
    }

    /// Nearby: the phone has waited `helpDelay` for others (see `isWaitingForOthers`), long enough that the other phone
    /// may not have done its part yet, or that iOS keeps Eggscape off the local network. The app cannot ask iOS which
    /// (TN3179), so the screen explains both and offers the settings.
    private(set) var isWaitingLong = false
    /// Joiner: why the last room could not be joined, shown with the room list until the next attempt.
    private(set) var joinFailure: String?
    /// The run of the current race.
    private(set) var run: RunSession?
    /// Coins this player earned in the last race.
    private(set) var reward: CoinReward?

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let transport: any PeerTransport
    /// The nearby transport, for discovery and join requests; `nil` online.
    @ObservationIgnored private let nearby: (any NearbyTransport)?
    @ObservationIgnored private let codec = NetCodec()
    @ObservationIgnored private var referee = RaceReferee()
    @ObservationIgnored private var clock = ClockSync()
    @ObservationIgnored private let epoch = ContinuousClock.now
    /// Host side: which player each connected phone is.
    @ObservationIgnored private var playersByPeer: [String: PlayerID] = [:]
    /// Joiner side: the phone that hosts the room, and the room we are joining.
    @ObservationIgnored private var hostPeer: RemotePeer?
    @ObservationIgnored private var joiningRoomID: String?
    /// Nearby joiner: when the current join began, for the log.
    @ObservationIgnored private var joinStartedAt: ContinuousClock.Instant?
    /// Nearby joiner: how long the host may take to send the lobby once it has let us in. It sends it right away, so
    /// this only ends a join that would otherwise wait on "Verbinde …" forever (the transport's invitation deadline is
    /// over by then). Settable for tests.
    @ObservationIgnored var lobbyTimeout: Duration = .seconds(10)
    @ObservationIgnored private var lobbyDeadline: Task<Void, Never>?
    /// Nearby: how long a phone waits for others before the screen explains what else may be needed
    /// (`isWaitingLong`). Settable for tests; a wait that is under way starts over.
    @ObservationIgnored var helpDelay: Duration = .seconds(10) {
        didSet {
            helpTimer?.cancel()
            helpTimer = nil
            updateWaitingHelp()
        }
    }

    @ObservationIgnored private var helpTimer: Task<Void, Never>?
    /// Nearby: the first pause before advertising or browsing again when iOS turned it down (see
    /// `retryDiscovery(after:)`). Settable for tests.
    @ObservationIgnored var discoveryRetryDelay: Duration = .seconds(2)
    /// Turned-down attempts in a row since the app was last active again.
    @ObservationIgnored private var discoveryFailures = 0
    @ObservationIgnored private var discoveryRetry: Task<Void, Never>?
    @ObservationIgnored private var listener: Task<Void, Never>?
    @ObservationIgnored private var pinger: Task<Void, Never>?
    /// Set by `leave()`. Messages that were already on their way can still change the stage afterwards.
    @ObservationIgnored private var hasLeft = false
    @ObservationIgnored private let logger = Logger(subsystem: "de.juliusedel.eggscape", category: "nearby")

    /// - Parameter networking: `false` only for the staged App Store screenshot (no prompt, no radio).
    convenience init(role: Role, services: AppServices, networking: Bool = true) {
        let multipeer = MultipeerTransport(displayName: services.settings.displayName)
        self.init(role: role, services: services, nearby: multipeer, networking: networking)
    }

    /// A nearby room over `nearby`; the app passes MultipeerConnectivity, the tests a fake.
    init(role: Role, services: AppServices, nearby multipeer: any NearbyTransport, networking: Bool = true) {
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
        transport = multipeer
        nearby = multipeer
        stage = role == .host ? .lobby : .browsing
        multipeer.acceptsPlayers = { [weak self] in
            guard let self else { return false }
            return stage == .lobby && !lobby.isFull
        }
        multipeer.onRoomsChanged = { [weak self] rooms in self?.rooms = rooms }
        // `didSet` does not run in an initializer, and a host starts in its lobby.
        updateIdleTimer()
        guard networking else { return }
        listen()
        // Likewise: either side starts out waiting for the others.
        updateWaitingHelp()
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
        updateIdleTimer()
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

    /// The race's run is on screen: during the race and over its results.
    var showsRun: Bool {
        switch stage {
        case .racing, .results: run != nil
        case .browsing, .connecting, .lobby, .failed: false
        }
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
        joinStartedAt = .now
        nearby?.join(room, context: context)
    }

    /// Shown with the room list when a join did not work out. The joiner cannot tell a host that turned it down (the
    /// room filled up or started a race since it was listed) from a connection that could not be set up, which is
    /// the more likely reason for a listed room, so the message covers both and says what helps.
    static var joinFailedMessage: String {
        String(
            localized: "Beitreten hat nicht geklappt. Vielleicht ist der Raum gerade voll oder im Rennen, oder die Verbindung kam nicht zustande. Bleib in der Nähe des Hosts, lass WLAN und Bluetooth an und versuch es noch einmal."
        )
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

    /// Nearby joiner: the join did not work out. The player reads why it may have failed and what helps; the log keeps
    /// the reason and how long it took, so the Xcode console (or Console.app) shows the cause.
    private func failJoin(_ failure: JoinFailure) {
        let host = stage.connectingHost ?? ""
        let seconds = joinStartedAt.map { (ContinuousClock.now - $0).seconds } ?? 0
        let reason = failure.logDescription
        logger.notice(
            "Join of \(host) failed after \(seconds, format: .fixed(precision: 1)) s: \(reason, privacy: .public)"
        )
        leaveRoom(Self.joinFailedMessage)
    }

    /// Nearby joiner: looks for rooms again, with a fresh list. The clock round trips go too, because the next host's
    /// clock has a zero point of its own.
    private func returnToRoomList() {
        pinger?.cancel()
        lobbyDeadline?.cancel()
        clock.reset()
        hostPeer = nil
        joiningRoomID = nil
        joinStartedAt = nil
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
        hasLeft = true
        pinger?.cancel()
        lobbyDeadline?.cancel()
        discoveryRetry?.cancel()
        listener?.cancel()
        run?.stop()
        transport.close()
        updateIdleTimer()
        updateWaitingHelp()
    }

    /// Keeps the screen awake while the player is in the room, never after `leave()`. `IdleTimer` only recomputes when
    /// asked, so the lease has to be given back here: a session that just goes away would keep the screen on.
    private func updateIdleTimer() {
        IdleTimer.setDisabled(stage.keepsScreenAwake && !hasLeft, for: self)
    }

    // MARK: Finding each other

    /// Nearby: nobody to race with yet. The joiner's room list is empty, or the host is alone in its room, which is why
    /// "Rennen starten" stays disabled.
    var isWaitingForOthers: Bool {
        guard isNearby else { return false }
        switch role {
        case .host:
            return stage == .lobby && lobby.connectedPlayers.count < LobbyState.minPlayers
        case .joiner:
            return stage == .browsing && rooms.isEmpty
        }
    }

    /// Nearby: the app is active again, for example after the Local Network prompt or the Settings app. iOS may have
    /// turned down advertising or browsing while its prompt was up, and leaves trying again to the app (TN3179), so
    /// what has found nobody yet starts over at once: the search while the room list is empty, the advertising while
    /// the host is alone, and an attempt that is due to be tried again anyway. A list with rooms or a room with
    /// players works, and stays as it is.
    func appBecameActive() {
        guard isNearby, !hasLeft else { return }
        discoveryFailures = 0
        if isWaitingForOthers || discoveryRetry != nil {
            restartDiscovery()
        }
    }

    /// Nearby: iOS turned down advertising the room or looking for rooms. It may do so while its Local Network prompt
    /// is up, and leaves trying again to the app (TN3179), so this ends neither the room nor the search: the phone
    /// tries again after a pause that grows with every failure in a row, so that a phone without Local Network access
    /// does not keep trying every moment. `appBecameActive()` tries again at once.
    private func retryDiscovery(after reason: String) {
        guard isNearby, !hasLeft else { return }
        discoveryFailures += 1
        let delay = Self.retryDelay(afterFailures: discoveryFailures, first: discoveryRetryDelay)
        let attempt = isHost ? "advertise the room" : "look for rooms"
        let pause = delay.seconds
        logger.notice("Could not \(attempt, privacy: .public): \(reason, privacy: .public)")
        logger.notice("Trying to \(attempt, privacy: .public) again in \(pause, format: .fixed(precision: 1)) s")
        discoveryRetry?.cancel()
        discoveryRetry = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.restartDiscovery()
        }
    }

    /// The pause before trying again after `failures` turned-down attempts in a row: `first` after one, twice as long
    /// after every further one, and never more than half a minute.
    static func retryDelay(afterFailures failures: Int, first: Duration) -> Duration {
        let doublings = min(max(failures - 1, 0), 10)
        return min(first * (1 << doublings), .seconds(30))
    }

    /// Advertises the room anew (host), or looks for rooms anew while the joiner has not picked one.
    private func restartDiscovery() {
        discoveryRetry?.cancel()
        discoveryRetry = nil
        guard let nearby, !hasLeft else { return }
        switch role {
        case .host:
            nearby.startHosting()
        case .joiner:
            if stage == .browsing {
                nearby.startBrowsing()
            }
        }
    }

    /// Starts the wait for help when the phone begins to wait for others, and ends it, together with the help, once a
    /// room or a player turns up.
    private func updateWaitingHelp() {
        guard isWaitingForOthers, !hasLeft else {
            helpTimer?.cancel()
            helpTimer = nil
            if isWaitingLong {
                isWaitingLong = false
            }
            return
        }
        guard helpTimer == nil, !isWaitingLong else { return }
        helpTimer = Task { [weak self, helpDelay] in
            try? await Task.sleep(for: helpDelay)
            guard !Task.isCancelled else { return }
            self?.helpDelayElapsed()
        }
    }

    /// The phone has waited `helpDelay` for others. Internal rather than private so the tests can end a host's wait
    /// without waiting, which they must not do while its room keeps the screen awake (see `NearbyJoinTests`).
    func helpDelayElapsed() {
        helpTimer?.cancel()
        helpTimer = nil
        guard isWaitingForOthers, !hasLeft else { return }
        isWaitingLong = true
    }

    // MARK: Race

    private func beginRace(seed: UInt64, startsIn seconds: Double) {
        let settings = lobby.settings
        let setup = RunSetup(mode: .timeTrial(settings.distance, settings.weather), raceSeed: seed)
        let hooks = RaceHooks(
            startAt: .now + .seconds(RaceReferee.startDelay(clamping: seconds)),
            isReferee: isHost,
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

    /// Internal rather than private so the tests can feed a transport's events one at a time.
    func handle(_ event: TransportEvent) {
        switch event {
        case let .connected(peer):
            peerConnected(peer)
        case let .disconnected(peer):
            peerDisconnected(peer)
        case let .received(data, peer):
            do {
                let envelope = try codec.decode(data)
                // JSON carries numbers like 1e300 meters, which would crash this phone as it shows them; a real phone
                // never sends them.
                guard envelope.message.isPlausible(eggsPerRun: GameConfig.standard.eggsPerRun) else {
                    let kind = envelope.message.kind.rawValue
                    logger.error("Dropped a \(kind, privacy: .public) message with numbers no race can produce")
                    return
                }
                receive(envelope.message, from: envelope.sender, peer: peer)
            } catch {
                logger.error("Dropped a message: \(String(describing: error))")
            }
        case let .joinFailed(failure):
            guard case .connecting = stage else { return }
            failJoin(failure)
        case let .discoveryFailed(reason):
            retryDiscovery(after: reason)
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
                else {
                    // The joiner waits for a lobby that never comes and gives up; this line on the host says why.
                    logger.notice("Could not seat \(peer.displayName): no readable join request")
                    return
                }
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
                logger.notice("No seat for \(request.nickname): the lobby is full")
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
                awaitLobby()
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
            guard peer == hostPeer else { return }
            if isNearby, case .connecting = stage {
                // Not in the room yet: back to the list, where joining again is one tap away.
                failJoin(.droppedWhileConnecting)
            } else {
                pinger?.cancel()
                stage = .failed(String(localized: "Die Verbindung zum Raum ist abgebrochen."))
            }
        }
    }

    /// Nearby joiner: the host let us in and is about to send the lobby. Without it the join is over after
    /// `lobbyTimeout`: the host may not have understood our join request, or the lobby never got through.
    private func awaitLobby() {
        lobbyDeadline?.cancel()
        lobbyDeadline = Task { [weak self, lobbyTimeout] in
            try? await Task.sleep(for: lobbyTimeout)
            guard !Task.isCancelled, let self, case .connecting = stage else { return }
            failJoin(.noLobby)
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
                logger.notice("Left the room of \(state.host?.nickname ?? ""): its lobby has no seat for us")
                leaveRoom(String(localized: "Der Raum ist voll."))
                return
            }
            lobby = state
            for player in state.players where player.id != me.id {
                markOpponent(player.id) { $0.isConnected = player.isConnected }
            }
            if case .connecting = stage {
                lobbyDeadline?.cancel()
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
