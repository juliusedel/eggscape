import EggscapeCore
import Foundation
import Observation

/// The single-player modes.
enum RunMode: Hashable {
    case timeTrial(RaceDistance, WeatherOption)
    case endless

    var course: Course {
        switch self {
        case let .timeTrial(distance, _): .timeTrial(distance)
        case .endless: .endless
        }
    }

    var weather: WeatherOption {
        switch self {
        case let .timeTrial(_, weather): weather
        case .endless: .random
        }
    }
}

/// A single-player run; "Nochmal" swaps in a fresh session without closing the full-screen cover.
@MainActor
@Observable
final class SingleRunFlow {
    var session: RunSession

    init(session: RunSession) {
        self.session = session
    }
}

/// What is currently playing full screen on top of the tabs.
enum GameFlow: Identifiable {
    case single(SingleRunFlow)
    case hotSeat(HotSeatSession)

    var id: ObjectIdentifier {
        switch self {
        case let .single(flow): ObjectIdentifier(flow)
        case let .hotSeat(session): ObjectIdentifier(session)
        }
    }
}

/// Starts runs from any tab and presents them full screen.
@MainActor
@Observable
final class GameLauncher {
    var flow: GameFlow?
    @ObservationIgnored private unowned let services: AppServices

    init(services: AppServices) {
        self.services = services
    }

    func start(_ mode: RunMode) {
        flow = .single(SingleRunFlow(session: makeSession(Self.newSetup(mode), countsAsRecord: true)))
    }

    /// "Nochmal": same mode, new weather and footsteps.
    func restart() {
        guard case let .single(single) = flow else { return }
        single.session = makeSession(Self.newSetup(single.session.setup.mode), countsAsRecord: true)
    }

    func startHotSeat(players: [String], distance: RaceDistance, weather: WeatherOption) {
        let setup = Self.newSetup(.timeTrial(distance, weather))
        flow = .hotSeat(HotSeatSession(players: players, setup: setup) { [unowned self] setup in
            makeSession(setup, countsAsRecord: false)
        })
    }

    func close() {
        flow = nil
    }

    private func makeSession(_ setup: RunSetup, countsAsRecord: Bool) -> RunSession {
        RunSession(
            setup: setup,
            motion: services.motion,
            settings: services.settings,
            records: countsAsRecord ? services.records : nil,
            haptics: services.haptics,
            sounds: services.sounds
        )
    }

    private static func newSetup(_ mode: RunMode) -> RunSetup {
        RunSetup(mode: mode, raceSeed: .random(in: .min ... .max))
    }
}
