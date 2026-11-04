@testable import Eggscape
import Foundation
import Testing

/// `MCPeerID` raises an uncatchable exception for names over 63 bytes of UTF-8, so nicknames are trimmed to fit.
@MainActor
struct PeerNameTests {
    @Test func namesThatFitStayAsTheyAre() {
        #expect(MultipeerTransport.peerName(for: "Julius") == "Julius")
        let longest = String(repeating: "a", count: 63)
        #expect(MultipeerTransport.peerName(for: longest) == longest)
    }

    @Test func anEmptyNameBecomesTheAppName() {
        #expect(MultipeerTransport.peerName(for: "") == "Eggscape")
    }

    @Test func aFullNicknameOfEggsIsTrimmedToTheByteLimit() {
        // 16 characters are a valid nickname, but 16 eggs are 64 bytes.
        let eggs = String(repeating: "🥚", count: SettingsStore.maxNameLength)
        let name = MultipeerTransport.peerName(for: eggs)
        #expect(name == String(repeating: "🥚", count: SettingsStore.maxNameLength - 1))
        #expect(name.utf8.count <= 63)
    }

    @Test func composedEmojiAreNeverCutInHalf() {
        // One character of 25 bytes: man, woman, girl and boy joined.
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
        #expect(MultipeerTransport.peerName(for: String(repeating: family, count: 3)) == family + family)
    }

    @Test func aSingleCharacterOverTheLimitBecomesTheAppName() {
        let stacked = "e" + String(repeating: "\u{301}", count: 40)
        #expect(stacked.count == 1)
        #expect(MultipeerTransport.peerName(for: stacked) == "Eggscape")
    }
}

/// A peer id is stored for every name played under nearby, so "Daten zurücksetzen" has to forget them as well.
@MainActor
struct StoredPeerIDTests {
    /// A fresh, isolated defaults domain per test.
    private func makeDefaults() -> UserDefaults {
        let suite = "eggscape.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func aNameKeepsItsPeerIDFromRoomToRoom() {
        let defaults = makeDefaults()
        let first = MultipeerTransport.peerID(for: "Julius", in: defaults)
        #expect(MultipeerTransport.peerID(for: "Julius", in: defaults) == first)
        #expect(MultipeerTransport.peerID(for: "Mia", in: defaults) != first)
        #expect(defaults.object(forKey: "nearby.peerID.Julius") != nil)
    }

    @Test func resetForgetsThePeerIDOfEveryName() {
        let defaults = makeDefaults()
        let julius = MultipeerTransport.peerID(for: "Julius", in: defaults)
        _ = MultipeerTransport.peerID(for: "Mia", in: defaults)
        // A name from an earlier build, and data that is not nearby's.
        defaults.set(Data([1]), forKey: "nearby.peerID.Spieler 1")
        defaults.set(false, forKey: "settings.sound")

        MultipeerTransport.resetStoredPeerIDs(in: defaults)
        for name in ["Julius", "Mia", "Spieler 1"] {
            #expect(defaults.object(forKey: "nearby.peerID.\(name)") == nil, "\(name) is still stored")
        }
        #expect(defaults.object(forKey: "settings.sound") != nil, "the reset leaves other data alone")
        #expect(MultipeerTransport.peerID(for: "Julius", in: defaults) != julius, "the name gets a new peer id")
    }

    @Test func resettingAllDataForgetsTheNamesPlayedNearby() {
        // Nearby rooms store their peer ids in the standard defaults, whatever defaults the stores use.
        let key = "nearby.peerID.Reset \(UUID().uuidString)"
        UserDefaults.standard.set(Data([1]), forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let defaults = makeDefaults()
        let services = AppServices(
            settings: SettingsStore(defaults: defaults),
            records: RecordsStore(defaults: defaults),
            wallet: WalletStore(defaults: defaults)
        )
        services.resetAllData()
        #expect(UserDefaults.standard.object(forKey: key) == nil)
    }
}
