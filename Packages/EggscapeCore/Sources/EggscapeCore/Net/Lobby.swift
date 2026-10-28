/// Identifies a player for a whole multiplayer session.
///
/// A wrapper rather than a bare `String`, so an id cannot be mixed up with a nickname or a skin id. Nicknames can
/// collide, so the app uses something unique per phone, such as a UUID string created on first launch. On the wire
/// the id is a plain JSON string.
public struct PlayerID: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        rawValue = value
    }

    /// Written out so the id stays a bare string on the wire, independent of how Swift would synthesize it.
    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension PlayerID: CustomStringConvertible {
    public var description: String {
        rawValue
    }
}

/// A player as the lobby lists them. The host keeps the list and sends it to everyone as `NetMessage.lobbyState`.
public struct PlayerInfo: Codable, Hashable, Sendable, Identifiable {
    public var id: PlayerID
    public var nickname: String
    /// The equipped egg skin (an id from the skin catalog), so every phone can draw every player's own egg.
    public var eggSkinID: String
    /// Mirrors `LobbyState.hostID`; `LobbyState.join(_:)` keeps the two in sync.
    public var isHost: Bool
    public var isReady: Bool
    /// `false` once the transport lost the player. The entry stays, so the lobby can still show who left.
    public var isConnected: Bool

    public init(
        id: PlayerID,
        nickname: String,
        eggSkinID: String,
        isHost: Bool = false,
        isReady: Bool = false,
        isConnected: Bool = true
    ) {
        self.id = id
        self.nickname = nickname
        self.eggSkinID = eggSkinID
        self.isHost = isHost
        self.isReady = isReady
        self.isConnected = isConnected
    }

    /// The JSON keys are part of the wire format: when renaming a property, keep its key (`case newName = "oldName"`).
    private enum CodingKeys: String, CodingKey {
        case id
        case nickname
        case eggSkinID
        case isHost
        case isReady
        case isConnected
    }
}

/// What the host picked for the next race.
///
/// Multiplayer races are always time trials: everyone runs to the same finish line, which is what makes a finish
/// order meaningful.
public struct RaceSettings: Hashable, Sendable {
    public var distance: RaceDistance
    public var weather: WeatherOption

    public init(distance: RaceDistance = .short, weather: WeatherOption = .off) {
        self.distance = distance
        self.weather = weather
    }

    /// The gentlest race, preselected in a new lobby: the short distance without weather.
    public static let standard = RaceSettings()

    /// The course every player of the race runs.
    public var course: Course {
        .timeTrial(distance)
    }
}

/// Written out instead of relying on the synthesized conformances of `RaceDistance` and `WeatherOption`: synthesized
/// enums with associated values read `{"fixed":{"_0":"wind"}}`, and the wire format must not change when those types
/// change how they are stored elsewhere. Format: `{"distance":"short","weather":{"type":"fixed","kind":"wind"}}`,
/// where the weather `type` is `off`, `fixed` (with a `kind`) or `random`.
extension RaceSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case distance
        case weather
    }

    private enum WeatherKeys: String, CodingKey {
        case type
        case kind
    }

    private enum WeatherType: String {
        case off
        case fixed
        case random
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        distance = try container.decodeWireValue(RaceDistance.self, forKey: .distance)
        let weather = try container.nestedContainer(keyedBy: WeatherKeys.self, forKey: .weather)
        switch try weather.decodeWireValue(WeatherType.self, forKey: .type) {
        case .off:
            self.weather = .off
        case .fixed:
            self.weather = try .fixed(weather.decodeWireValue(WeatherKind.self, forKey: .kind))
        case .random:
            self.weather = .random
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(distance.rawValue, forKey: .distance)
        var weather = container.nestedContainer(keyedBy: WeatherKeys.self, forKey: .weather)
        switch self.weather {
        case .off:
            try weather.encode(WeatherType.off.rawValue, forKey: .type)
        case let .fixed(kind):
            try weather.encode(WeatherType.fixed.rawValue, forKey: .type)
            try weather.encode(kind.rawValue, forKey: .kind)
        case .random:
            try weather.encode(WeatherType.random.rawValue, forKey: .type)
        }
    }
}

/// The lobby as the host keeps it. The host sends it to everyone as `NetMessage.lobbyState` after every change, so
/// joiners only ever display the host's copy.
public struct LobbyState: Codable, Hashable, Sendable {
    /// A race needs at least one opponent.
    public static let minPlayers = 2
    /// The largest race the game offers.
    public static let maxPlayers = 4

    public var hostID: PlayerID
    /// In the order the players joined, the host first.
    public var players: [PlayerInfo]
    public var settings: RaceSettings

    public init(hostID: PlayerID, players: [PlayerInfo], settings: RaceSettings = .standard) {
        self.hostID = hostID
        self.players = players
        self.settings = settings
    }

    /// A new lobby with only the host in it.
    public init(host: PlayerInfo, settings: RaceSettings = .standard) {
        var host = host
        host.isHost = true
        self.init(hostID: host.id, players: [host], settings: settings)
    }

    public var host: PlayerInfo? {
        player(hostID)
    }

    public func player(_ id: PlayerID) -> PlayerInfo? {
        players.first { $0.id == id }
    }

    public var connectedPlayers: [PlayerInfo] {
        players.filter(\.isConnected)
    }

    /// No one else can join until a connected player leaves.
    public var isFull: Bool {
        connectedPlayers.count >= Self.maxPlayers
    }

    /// The host may start: two to four players are connected, the host among them, and every connected joiner is
    /// ready. The host's own `isReady` does not count, because pressing start is the host's way of being ready.
    /// Players who left do not block the start.
    public var canStart: Bool {
        let connected = connectedPlayers
        guard (Self.minPlayers ... Self.maxPlayers).contains(connected.count),
              connected.contains(where: { $0.id == hostID })
        else {
            return false
        }
        return connected.allSatisfy { $0.id == hostID || $0.isReady }
    }

    /// Adds `player`, or replaces the entry with the same id (a player who reconnects or changes their nickname or
    /// skin), and sets `isHost` from `hostID`.
    /// - Returns: `false`, leaving the lobby unchanged, when this would make more than `maxPlayers` connected.
    @discardableResult
    public mutating func join(_ player: PlayerInfo) -> Bool {
        var player = player
        player.isHost = player.id == hostID
        var updated = players
        if let index = updated.firstIndex(where: { $0.id == player.id }) {
            updated[index] = player
        } else {
            updated.append(player)
        }
        guard updated.filter(\.isConnected).count <= Self.maxPlayers else {
            return false
        }
        players = updated
        return true
    }

    public mutating func setReady(_ isReady: Bool, for id: PlayerID) {
        guard let index = players.firstIndex(where: { $0.id == id }) else {
            return
        }
        players[index].isReady = isReady
    }

    /// Keeps the entry so the lobby can show who left; a player who left is no longer ready.
    public mutating func markDisconnected(_ id: PlayerID) {
        guard let index = players.firstIndex(where: { $0.id == id }) else {
            return
        }
        players[index].isConnected = false
        players[index].isReady = false
    }

    public mutating func remove(_ id: PlayerID) {
        players.removeAll { $0.id == id }
    }

    /// Before the next race: players who left mid-race are dropped, so the lobby and the race only show who is still
    /// there, and a player who comes back (with a new id) is not listed twice.
    public mutating func removeDisconnected() {
        players.removeAll { !$0.isConnected }
    }

    /// Back in the lobby after a race, everyone confirms again before the next one.
    public mutating func resetReadiness() {
        for index in players.indices {
            players[index].isReady = false
        }
    }

    /// The JSON keys are part of the wire format: when renaming a property, keep its key (`case newName = "oldName"`).
    private enum CodingKeys: String, CodingKey {
        case hostID
        case players
        case settings
    }
}
