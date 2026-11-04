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

    /// German stays the source language of the String Catalogs, but a phone set to neither German nor English (say,
    /// only French) shows the app in English, the language iOS falls back to (`CFBundleDevelopmentRegion`).
    @Test func speaksGermanAndEnglishAndFallsBackToEnglish() {
        #expect(value("CFBundleLocalizations") as? [String] == ["de", "en"])
        #expect(value("CFBundleDevelopmentRegion") as? String == "en")
        #expect(Bundle.main.developmentLocalization == "en")
        #expect(Set(Bundle.main.localizations).isSuperset(of: ["de", "en"]))
    }

    /// The texts of the permission prompts.
    static let promptKeys = ["NSCameraUsageDescription", "NSLocalNetworkUsageDescription"]

    /// A compiled `InfoPlist.strings` of the app, by language.
    private func promptTable(_ language: String) -> NSDictionary? {
        NSDictionary(contentsOf: Bundle.main.bundleURL.appending(path: "\(language).lproj/InfoPlist.strings"))
    }

    /// The permission prompts speak the app's language, and English on a phone in a language the app has no translation
    /// for. A German phone looks for them in the German table and, without one, would take the English table of the
    /// fallback language, so the German texts need a table of their own: the build writes it because the German
    /// entries of InfoPlist.xcstrings are marked translated.
    @Test(arguments: InfoPlistTests.promptKeys)
    func permissionPromptsSpeakTheAppsLanguage(key: String) throws {
        let german = try #require(promptTable("de")?[key] as? String)
        let english = try #require(promptTable("en")?[key] as? String)
        #expect(german == Bundle.main.infoDictionary?[key] as? String, "the German table holds Info.plist's own text")
        #expect(english != german)
        let isGerman = Bundle.main.preferredLocalizations.first == "de"
        #expect(value(key) as? String == (isGerman ? german : english))
    }
}
