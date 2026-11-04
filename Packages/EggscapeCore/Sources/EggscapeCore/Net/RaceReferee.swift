/// The host's bookkeeping for one race: who runs, how far everyone got, and in which order the runs ended.
///
/// Every phone simulates its own run, so the referee only collects what the phones report. Completed runs are ranked
/// by the order in which their `finished` reports reach the host, not by the reported times: a phone that hitches
/// loses simulated time (`FixedTimestep` clamps long frames) and would report a faster time than it really ran,
/// while the arrival order is what the host actually observed. The host records its own report the moment its run
/// ends, which gives it an edge of one network latency over the joiners.
///
/// A plain value: the app feeds it messages and disconnects, and sends `results()` once `isComplete` is true.
public struct RaceReferee: Sendable, Equatable {
    /// Seconds from `startRace` to the start signal: time for the message to reach every phone and for a countdown.
    public static let startDelay = 3.0

    /// The waits for the start signal a joiner accepts, in seconds: a moment for its countdown at least, and at most a
    /// few seconds more than `startDelay`, so a wrong clock estimate cannot hold a phone back for long.
    public static let startDelays = 0.5 ... 10.0

    /// One player's race as the host knows it.
    public struct Runner: Sendable, Equatable, Identifiable {
        public let id: PlayerID
        public fileprivate(set) var nickname: String
        /// The furthest distance reported so far.
        public fileprivate(set) var meters = 0.0
        public fileprivate(set) var eggsLeft: Int
        /// The `finished` report, once it arrived.
        public fileprivate(set) var report: FinishReport?
        public fileprivate(set) var isConnected = true

        fileprivate init(id: PlayerID, nickname: String, eggsLeft: Int) {
            self.id = id
            self.nickname = nickname
            self.eggsLeft = eggsLeft
        }

        /// Nothing more to wait for: the run is over or the player left.
        public var isDone: Bool {
            report != nil || !isConnected
        }
    }

    public let eggsPerRun: Int
    /// In registration order.
    public private(set) var runners: [Runner] = []
    /// The players whose `finished` reports arrived, in arrival order.
    public private(set) var arrivals: [PlayerID] = []

    public init(eggsPerRun: Int = GameConfig.standard.eggsPerRun) {
        precondition(eggsPerRun > 0, "eggsPerRun must be positive")
        self.eggsPerRun = eggsPerRun
    }

    /// A referee for the lobby's connected players.
    public init(lobby: LobbyState, eggsPerRun: Int = GameConfig.standard.eggsPerRun) {
        self.init(eggsPerRun: eggsPerRun)
        for player in lobby.connectedPlayers {
            register(player.id, nickname: player.nickname)
        }
    }

    /// The `startAt` of a race the host starts at `hostNow` (host clock seconds).
    public static func startAt(hostNow: Double) -> Double {
        hostNow + startDelay
    }

    /// How long a joiner waits for the start signal when the host's `startAt`, converted with its clock estimate
    /// (`ClockSync`), lies `seconds` ahead: within `startDelays`, and `startDelay` when the conversion gave no number.
    /// The estimate rests on the host's pongs, whose clock readings may be any finite number, so a far-off result
    /// would otherwise become a wait no phone can count down (`Duration.seconds(1e300)` traps).
    public static func startDelay(clamping seconds: Double) -> Double {
        guard seconds.isFinite else {
            return startDelay
        }
        return min(max(seconds, startDelays.lowerBound), startDelays.upperBound)
    }

    public func runner(_ id: PlayerID) -> Runner? {
        runners.first { $0.id == id }
    }

    /// Every connected player has finished or run out of eggs; players who left are not waited for. A race without
    /// players is never complete.
    public var isComplete: Bool {
        !runners.isEmpty && runners.allSatisfy(\.isDone)
    }

    /// Adds a player to the race. Registering a known player again only updates the nickname.
    public mutating func register(_ id: PlayerID, nickname: String) {
        if let index = runners.firstIndex(where: { $0.id == id }) {
            runners[index].nickname = nickname
        } else {
            runners.append(Runner(id: id, nickname: nickname, eggsLeft: eggsPerRun))
        }
    }

    /// Feeds a race message from `id` to the matching `record` method; lobby and clock messages are ignored.
    /// - Returns: whether the message was recorded.
    @discardableResult
    public mutating func receive(_ message: NetMessage, from id: PlayerID) -> Bool {
        switch message {
        case let .progress(meters, eggsLeft):
            recordProgress(meters: meters, eggsLeft: eggsLeft, from: id)
        case let .eggDropped(eggsLeft):
            recordEggDropped(eggsLeft: eggsLeft, from: id)
        case let .finished(report):
            recordFinished(report, from: id)
        case .lobbyState, .setSettings, .ready, .startRace, .results, .ping, .pong:
            false
        }
    }

    /// - Returns: `false`, ignoring the update, for unknown players, players whose run is over or who left, and
    ///   numbers no run can produce (see `NetMessage.isPlausible(eggsPerRun:)`).
    @discardableResult
    public mutating func recordProgress(meters: Double, eggsLeft: Int, from id: PlayerID) -> Bool {
        guard let index = racingIndex(id), NetMessage.plausibleMeters.contains(meters),
              NetMessage.isEggCount(eggsLeft, of: eggsPerRun)
        else {
            return false
        }
        // Progress travels unreliably and can arrive out of order, but a run never loses meters or regains eggs.
        runners[index].meters = max(runners[index].meters, meters)
        runners[index].eggsLeft = min(runners[index].eggsLeft, eggsLeft)
        return true
    }

    /// - Returns: `false`, ignoring the update, for unknown players, players whose run is over or who left, and egg
    ///   counts no run can have.
    @discardableResult
    public mutating func recordEggDropped(eggsLeft: Int, from id: PlayerID) -> Bool {
        guard let index = racingIndex(id), NetMessage.isEggCount(eggsLeft, of: eggsPerRun) else {
            return false
        }
        runners[index].eggsLeft = min(runners[index].eggsLeft, eggsLeft)
        return true
    }

    /// Records the end of a run. The order of these calls is the finish order of the completed runs.
    /// - Returns: `false`, ignoring the report, for unknown players, a second report, players who left, and reports
    ///   no run can produce (`FinishReport.isPlausible(eggsPerRun:)`): a time of 1e300 seconds would otherwise be
    ///   ranked and sent to everybody in the results.
    @discardableResult
    public mutating func recordFinished(_ report: FinishReport, from id: PlayerID) -> Bool {
        guard let index = racingIndex(id), report.isPlausible(eggsPerRun: eggsPerRun) else {
            return false
        }
        runners[index].report = report
        runners[index].meters = report.meters
        runners[index].eggsLeft = eggsPerRun - report.eggsLost
        arrivals.append(id)
        return true
    }

    /// The race goes on without the player. A player who already reported keeps their result.
    public mutating func markDisconnected(_ id: PlayerID) {
        guard let index = runners.firstIndex(where: { $0.id == id }) else {
            return
        }
        runners[index].isConnected = false
    }

    /// The ranking: completed runs in arrival order, then players who ran out of eggs by distance, then players who
    /// left by their last known distance. Equal distances keep arrival or registration order.
    ///
    /// Meant for a complete race. Called earlier, players still running are ranked and listed like players who
    /// left, which is what ending a race early means for them.
    public func results() -> RaceResults {
        let reported = arrivals.compactMap { runner($0) }
        let completed = reported.filter { $0.report?.completed == true }
        let outOfEggs = reported.filter { $0.report?.completed == false }
        let unreported = runners.filter { $0.report == nil }
        let ranked = completed + Self.furthestFirst(outOfEggs) + Self.furthestFirst(unreported)
        return RaceResults(entries: ranked.enumerated().map { index, runner in
            entry(for: runner, place: index + 1)
        })
    }

    /// "Nochmal": the same players race again from zero. Players who left are dropped; the host then sends a new
    /// `startRace`.
    public mutating func rematch() {
        runners = runners.filter(\.isConnected).map { Runner(id: $0.id, nickname: $0.nickname, eggsLeft: eggsPerRun) }
        arrivals = []
    }

    /// A runner who may still report: registered, connected and without a report.
    private func racingIndex(_ id: PlayerID) -> Int? {
        runners.firstIndex { $0.id == id && !$0.isDone }
    }

    /// Sorted by distance, furthest first. Equal distances keep their order, because `sorted` is not guaranteed to be
    /// stable.
    private static func furthestFirst(_ runners: [Runner]) -> [Runner] {
        runners.enumerated()
            .sorted { lhs, rhs in
                lhs.element.meters == rhs.element.meters
                    ? lhs.offset < rhs.offset
                    : lhs.element.meters > rhs.element.meters
            }
            .map(\.element)
    }

    private func entry(for runner: Runner, place: Int) -> RaceResultEntry {
        let status: RaceResultEntry.Status
        let eggsLost: Int
        if let report = runner.report {
            status = report.completed ? .finished(time: report.time) : .outOfEggs(meters: report.meters)
            eggsLost = report.eggsLost
        } else {
            status = .disconnected(meters: runner.meters)
            eggsLost = eggsPerRun - runner.eggsLeft
        }
        return RaceResultEntry(
            place: place,
            playerID: runner.id,
            nickname: runner.nickname,
            status: status,
            eggsLost: eggsLost
        )
    }
}
