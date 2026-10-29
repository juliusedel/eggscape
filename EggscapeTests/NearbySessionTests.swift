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
