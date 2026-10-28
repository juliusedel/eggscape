import EggscapeCore
import Foundation
import Observation

/// "Gemeinsam an einem Handy": 2-4 players run the same course with the same weather and footsteps one after another.
@MainActor
@Observable
final class HotSeatSession {
    struct Entry: Identifiable, Equatable {
        let id: Int
        let name: String
        var outcome: RunOutcome?
    }

    enum Stage {
        /// "Gib das Handy an …"
        case handOver(Int)
        case playing(RunSession)
        case standings
    }

    static let playerRange = 2 ... 4

    let setup: RunSetup
    private(set) var entries: [Entry]
    private(set) var stage = Stage.handOver(0)
    @ObservationIgnored private let makeSession: (RunSetup) -> RunSession

    init(players: [String], setup: RunSetup, makeSession: @escaping (RunSetup) -> RunSession) {
        self.setup = setup
        self.makeSession = makeSession
        entries = players.enumerated().map { Entry(id: $0.offset, name: $0.element, outcome: nil) }
    }

    var currentIndex: Int? {
        switch stage {
        case let .handOver(index): index
        case .playing: entries.firstIndex { $0.outcome == nil }
        case .standings: nil
        }
    }

    func beginTurn() {
        stage = .playing(makeSession(setup))
    }

    func finishTurn(with outcome: RunOutcome) {
        guard let index = currentIndex else { return }
        entries[index].outcome = outcome
        let next = index + 1
        stage = next < entries.count ? .handOver(next) : .standings
    }

    /// "Nochmal": same players, new course seed.
    func playAgain() -> HotSeatSession {
        let fresh = RunSetup(mode: setup.mode, raceSeed: .random(in: .min ... .max))
        return HotSeatSession(players: entries.map(\.name), setup: fresh, makeSession: makeSession)
    }

    /// Finished runs by time first, then runs that ran out of eggs by distance.
    var ranking: [Entry] {
        entries.sorted { lhs, rhs in
            guard let left = lhs.outcome, let right = rhs.outcome else { return lhs.outcome != nil }
            switch (left.finished, right.finished) {
            case (true, true): return left.time < right.time
            case (true, false): return true
            case (false, true): return false
            case (false, false): return left.meters > right.meters
            }
        }
    }
}
