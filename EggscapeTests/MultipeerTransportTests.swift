@testable import Eggscape
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
