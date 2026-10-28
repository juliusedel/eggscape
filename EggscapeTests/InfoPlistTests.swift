import Foundation
import Testing

/// Guards the App Store relevant Info.plist settings against accidental changes.
struct InfoPlistTests {
    private func value(_ key: String) -> Any? {
        Bundle.main.object(forInfoDictionaryKey: key)
    }

    @Test func portraitOnly() {
        #expect(value("UISupportedInterfaceOrientations") as? [String] == ["UIInterfaceOrientationPortrait"])
    }

    @Test func requiresMotionSensors() {
        let capabilities = value("UIRequiredDeviceCapabilities") as? [String] ?? []
        #expect(capabilities.contains("accelerometer"))
        #expect(capabilities.contains("gyroscope"))
    }

    @Test func doesNotAskForMotionPermission() {
        #expect(value("NSMotionUsageDescription") == nil)
    }

    @Test func declaresNearbyPlayServices() {
        #expect(value("NSBonjourServices") as? [String] == ["_eggscape._tcp", "_eggscape._udp"])
        #expect(value("NSLocalNetworkUsageDescription") is String)
    }

    @Test func declaresExportCompliance() {
        #expect(value("ITSAppUsesNonExemptEncryption") as? Bool == false)
    }
}
