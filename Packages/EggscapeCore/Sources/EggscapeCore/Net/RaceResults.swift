/// What a player's phone reports, once, when their run is over (`NetMessage.finished`).
public struct FinishReport: Codable, Hashable, Sendable {
    /// `true` when the runner crossed the finish line, `false` when the last egg broke first.
    public var completed: Bool
    /// Race seconds from the start signal to the finish line, or to the moment the last egg broke. Measured by the
    /// runner's own simulation, which loses time when the phone hitches, so the players see it but it does not decide
    /// the finish order (see `RaceReferee`).
    public var time: Double
    /// Meters run; the course length for a completed run.
    public var meters: Double
    public var eggsLost: Int

    public init(completed: Bool, time: Double, meters: Double, eggsLost: Int) {
        self.completed = completed
        self.time = time
        self.meters = meters
        self.eggsLost = eggsLost
    }

    /// The report for a run that is over, `nil` while it is still going.
    public init?(run: RunEngine) {
        switch run.phase {
        case .finished:
            self.init(completed: true, time: run.elapsed, meters: run.meters, eggsLost: run.eggsLost)
        case .over:
            self.init(completed: false, time: run.elapsed, meters: run.meters, eggsLost: run.eggsLost)
        case .running, .recovering:
            return nil
        }
    }

    /// The JSON keys are part of the wire format: when renaming a property, keep its key (`case newName = "oldName"`).
    private enum CodingKeys: String, CodingKey {
        case completed
        case time
        case meters
        case eggsLost
    }
}

/// The host's verdict on a race, sent to everyone as `NetMessage.results`.
public struct RaceResults: Codable, Hashable, Sendable {
    /// Best first; the first entry has `place` 1.
    public var entries: [RaceResultEntry]

    public init(entries: [RaceResultEntry]) {
        self.entries = entries
    }

    public func entry(for id: PlayerID) -> RaceResultEntry? {
        entries.first { $0.playerID == id }
    }

    /// The JSON keys are part of the wire format: when renaming a property, keep its key (`case newName = "oldName"`).
    private enum CodingKeys: String, CodingKey {
        case entries
    }
}

/// One line of the results table.
public struct RaceResultEntry: Codable, Hashable, Sendable, Identifiable {
    /// How the player's race ended.
    public enum Status: Hashable, Sendable {
        /// Crossed the finish line after `time` race seconds, as the player's phone measured it.
        case finished(time: Double)
        /// The last egg broke after `meters` meters.
        case outOfEggs(meters: Double)
        /// The connection was lost before the run ended; `meters` is the last distance the host heard of.
        case disconnected(meters: Double)
    }

    /// 1 for the winner. Places are consecutive; there are no ties.
    public var place: Int
    public var playerID: PlayerID
    public var nickname: String
    public var status: Status
    public var eggsLost: Int

    public init(place: Int, playerID: PlayerID, nickname: String, status: Status, eggsLost: Int) {
        self.place = place
        self.playerID = playerID
        self.nickname = nickname
        self.status = status
        self.eggsLost = eggsLost
    }

    public var id: PlayerID {
        playerID
    }

    /// The JSON keys are part of the wire format: when renaming a property, keep its key (`case newName = "oldName"`).
    private enum CodingKeys: String, CodingKey {
        case place
        case playerID
        case nickname
        case status
        case eggsLost
    }
}

/// Written out because the synthesized format (`{"finished":{"time":51.2}}`) would tie the wire to Swift's encoding
/// of enums. Format: `{"type":"finished","time":51.2}`, `{"type":"outOfEggs","meters":120}` or
/// `{"type":"disconnected","meters":80}`.
extension RaceResultEntry.Status: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case time
        case meters
    }

    private enum StatusType: String {
        case finished
        case outOfEggs
        case disconnected
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decodeWireValue(StatusType.self, forKey: .type) {
        case .finished:
            self = try .finished(time: container.decode(Double.self, forKey: .time))
        case .outOfEggs:
            self = try .outOfEggs(meters: container.decode(Double.self, forKey: .meters))
        case .disconnected:
            self = try .disconnected(meters: container.decode(Double.self, forKey: .meters))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .finished(time):
            try container.encode(StatusType.finished.rawValue, forKey: .type)
            try container.encode(time, forKey: .time)
        case let .outOfEggs(meters):
            try container.encode(StatusType.outOfEggs.rawValue, forKey: .type)
            try container.encode(meters, forKey: .meters)
        case let .disconnected(meters):
            try container.encode(StatusType.disconnected.rawValue, forKey: .type)
            try container.encode(meters, forKey: .meters)
        }
    }
}
