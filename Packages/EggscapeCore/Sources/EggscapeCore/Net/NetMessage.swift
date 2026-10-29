/// Everything the phones of a multiplayer session say to each other. Nearby (MultipeerConnectivity) and online
/// (GameKit) play share these messages; the app's transport only moves the bytes `NetCodec` makes of them.
///
/// The host is the referee: it keeps the lobby, starts the race and decides the finish order. Every phone simulates
/// its own run and tells the others how far it got.
///
/// ## Flow
///
/// - Lobby: joiners send `ready` and keep pinging the host (about twice a second) so `ClockSync` has round trips to
///   work with; the host answers every `ping` with a `pong` and sends `lobbyState` after every change.
/// - Start: the host sends `startRace` with the seed of the shared weather and `startAt`, three seconds ahead on the
///   host's clock (`RaceReferee.startAt(hostNow:)`); joiners convert it with `ClockSync.localTime(fromHost:)`.
/// - Race: every phone sends `progress` ten times a second, `eggDropped` when an egg breaks and `finished` once
///   when its run is over.
/// - End: the host's `RaceReferee` collects the reports and the host sends `results` once the race is complete.
///
/// ## Wire format
///
/// A message is a JSON object whose `type` names the case; the associated values follow under fixed keys. They are
/// shown here with `type` first for readability; `NetCodec` writes keys sorted.
///
///     {"type":"lobbyState","lobby":{"hostID":"A","players":[{"id":"A","nickname":"Anna","eggSkinID":"classic",
///       "isHost":true,"isReady":false,"isConnected":true}],"settings":{"distance":"short","weather":{"type":"off"}}}}
///     {"type":"setSettings","settings":{"distance":"long","weather":{"type":"fixed","kind":"rain"}}}
///     {"type":"ready","isReady":true}
///     {"type":"startRace","seed":"9876543210123456789","startAt":5003.25}
///     {"type":"progress","meters":12.5,"eggsLeft":2}
///     {"type":"eggDropped","eggsLeft":1}
///     {"type":"finished","report":{"completed":true,"time":35.83,"meters":100,"eggsLost":1}}
///     {"type":"results","results":{"entries":[{"place":1,"playerID":"A","nickname":"Anna",
///       "status":{"type":"finished","time":35.83},"eggsLost":1}]}}
///     {"type":"ping","id":7,"sentAt":102.5}
///     {"type":"pong","id":7,"pingSentAt":102.5,"hostTime":5000.75}
///
/// - `distance` is `short`, `medium` or `long`. The weather `type` is `off`, `random` or `fixed` with a `kind`
///   (`clear`, `wind`, `rain`, `storm`). A result `status` is `finished` with a `time`, or `outOfEggs` or
///   `disconnected` with `meters`.
/// - The seed travels as a decimal string: many JSON tools read numbers as doubles, which would lose its low bits.
/// - Times are seconds of the sender's own monotonic clock (for example `ProcessInfo.processInfo.systemUptime`),
///   except `startAt` and `hostTime`, which are always on the host's clock.
///
/// `NetEnvelope` explains which changes need a new protocol version.
public enum NetMessage: Equatable, Sendable {
    /// Host to everyone: the whole lobby, after every change and to every player who joins.
    case lobbyState(LobbyState)
    /// Host to everyone: new race settings. The next `lobbyState` contains them too.
    case setSettings(RaceSettings)
    /// Joiner to host: the player is ready to race, or no longer is.
    case ready(Bool)
    /// Host to everyone: the race starts at `startAt` (host clock seconds); `seed` derives the shared weather.
    case startRace(seed: UInt64, startAt: Double)
    /// Everyone to everyone, `progressRate` times a second while running: drives the opponents' markers.
    case progress(meters: Double, eggsLeft: Int)
    /// Everyone to everyone: an egg broke; `eggsLeft` already counts the loss.
    case eggDropped(eggsLeft: Int)
    /// Everyone to everyone, once: the run is over. The order in which these reach the host decides the race.
    case finished(FinishReport)
    /// Host to everyone: the final ranking.
    case results(RaceResults)
    /// Joiner to host: `sentAt` is the joiner's clock; the host echoes it in the `pong`.
    case ping(id: UInt32, sentAt: Double)
    /// Host to the joiner who pinged: the host's clock when it answered (see `ClockSync`).
    case pong(id: UInt32, pingSentAt: Double, hostTime: Double)

    /// How often a running phone sends `progress`, in Hz: smooth enough for the opponents' markers at roughly a
    /// kilobyte per second and peer.
    public static let progressRate = 10.0

    /// The `type` of a message on the wire.
    public enum Kind: String, CaseIterable, Sendable {
        case lobbyState
        case setSettings
        case ready
        case startRace
        case progress
        case eggDropped
        case finished
        case results
        case ping
        case pong
    }

    /// How the transport should send a message.
    public enum Delivery: Sendable {
        /// Retransmitted until it arrives, in order with the other reliable messages.
        case reliable
        /// Sent once and possibly lost or reordered.
        case unreliable
    }

    public var kind: Kind {
        switch self {
        case .lobbyState: .lobbyState
        case .setSettings: .setSettings
        case .ready: .ready
        case .startRace: .startRace
        case .progress: .progress
        case .eggDropped: .eggDropped
        case .finished: .finished
        case .results: .results
        case .ping: .ping
        case .pong: .pong
        }
    }

    /// `progress` is superseded a tenth of a second later anyway, and a retransmitted `ping` or `pong` would only add
    /// a round trip that waited for the retransmission, so those go unreliable. Everything else must arrive.
    public var delivery: Delivery {
        switch self {
        case .progress, .ping, .pong:
            .unreliable
        case .lobbyState, .setSettings, .ready, .startRace, .eggDropped, .finished, .results:
            .reliable
        }
    }

    /// Messages only the referee may send. The app drops them from anyone else, so a confused phone cannot start a
    /// race or announce results.
    public var isHostOnly: Bool {
        switch self {
        case .lobbyState, .setSettings, .startRace, .results, .pong:
            true
        case .ready, .progress, .eggDropped, .finished, .ping:
            false
        }
    }
}

/// Written out, because the synthesized format (`{"progress":{"meters":12.5,"eggsLeft":2}}`, `{"ready":{"_0":true}}`)
/// would tie the wire to Swift's encoding of enums. See the format in the documentation of `NetMessage`.
extension NetMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case lobby
        case settings
        case isReady
        case seed
        case startAt
        case meters
        case eggsLeft
        case report
        case results
        case id
        case sentAt
        case pingSentAt
        case hostTime
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decodeWireValue(Kind.self, forKey: .type) {
        case .lobbyState:
            self = try .lobbyState(container.decode(LobbyState.self, forKey: .lobby))
        case .setSettings:
            self = try .setSettings(container.decode(RaceSettings.self, forKey: .settings))
        case .ready:
            self = try .ready(container.decode(Bool.self, forKey: .isReady))
        case .startRace:
            let seed = try container.decode(String.self, forKey: .seed)
            guard let value = UInt64(seed) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .seed,
                    in: container,
                    debugDescription: "The seed \"\(seed)\" is not a decimal UInt64"
                )
            }
            self = try .startRace(seed: value, startAt: container.decode(Double.self, forKey: .startAt))
        case .progress:
            self = try .progress(
                meters: container.decode(Double.self, forKey: .meters),
                eggsLeft: container.decode(Int.self, forKey: .eggsLeft)
            )
        case .eggDropped:
            self = try .eggDropped(eggsLeft: container.decode(Int.self, forKey: .eggsLeft))
        case .finished:
            self = try .finished(container.decode(FinishReport.self, forKey: .report))
        case .results:
            self = try .results(container.decode(RaceResults.self, forKey: .results))
        case .ping:
            self = try .ping(
                id: container.decode(UInt32.self, forKey: .id),
                sentAt: container.decode(Double.self, forKey: .sentAt)
            )
        case .pong:
            self = try .pong(
                id: container.decode(UInt32.self, forKey: .id),
                pingSentAt: container.decode(Double.self, forKey: .pingSentAt),
                hostTime: container.decode(Double.self, forKey: .hostTime)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind.rawValue, forKey: .type)
        switch self {
        case let .lobbyState(lobby):
            try container.encode(lobby, forKey: .lobby)
        case let .setSettings(settings):
            try container.encode(settings, forKey: .settings)
        case let .ready(isReady):
            try container.encode(isReady, forKey: .isReady)
        case let .startRace(seed, startAt):
            try container.encode(String(seed), forKey: .seed)
            try container.encode(startAt, forKey: .startAt)
        case let .progress(meters, eggsLeft):
            try container.encode(meters, forKey: .meters)
            try container.encode(eggsLeft, forKey: .eggsLeft)
        case let .eggDropped(eggsLeft):
            try container.encode(eggsLeft, forKey: .eggsLeft)
        case let .finished(report):
            try container.encode(report, forKey: .report)
        case let .results(results):
            try container.encode(results, forKey: .results)
        case let .ping(id, sentAt):
            try container.encode(id, forKey: .id)
            try container.encode(sentAt, forKey: .sentAt)
        case let .pong(id, pingSentAt, hostTime):
            try container.encode(id, forKey: .id)
            try container.encode(pingSentAt, forKey: .pingSentAt)
            try container.encode(hostTime, forKey: .hostTime)
        }
    }
}
