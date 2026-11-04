import SwiftUI

/// Sound, vibration, sensitivity, calibration, player name, background, data reset, and the help and legal pages.
struct SettingsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsReset = false
    @State private var showsCameraDenied = false
    @State private var showsCalibration = false

    var body: some View {
        @Bindable var settings = services.settings
        NavigationStack {
            Form {
                Section {
                    TextField("Spielername", text: $settings.playerName)
                        .textContentType(.nickname)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("settings.name")
                } header: {
                    Text("Spieler")
                } footer: {
                    Text("Andere Spieler sehen diesen Namen im Mehrspieler-Modus.")
                }

                Section {
                    Toggle("Ton", isOn: $settings.isSoundOn)
                    Toggle("Vibration", isOn: $settings.isHapticsOn)
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Empfindlichkeit") {
                            Text(settings.sensitivity, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                        }
                        Slider(value: $settings.sensitivity, in: 0.7 ... 1.3, step: 0.05) {
                            Text("Empfindlichkeit")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise.fill").accessibilityLabel(Text("Weniger"))
                        } maximumValueLabel: {
                            Image(systemName: "hare.fill").accessibilityLabel(Text("Mehr"))
                        }
                    }
                    Button("Neu kalibrieren") {
                        showsCalibration = true
                    }
                } header: {
                    Text("Spiel")
                }

                Section {
                    Picker("Hintergrund", selection: backgroundSelection) {
                        ForEach(BackgroundMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Hintergrund")
                } footer: {
                    Text(
                        "Mit „Kamera“ siehst du durch dein Handy hindurch auf den Boden. Das Bild wird nicht gespeichert."
                    )
                }

                Section {
                    Button("Anleitung anzeigen") {
                        dismiss()
                        services.navigation.showsTutorial = true
                    }
                }

                Section {
                    Button("Daten zurücksetzen", role: .destructive) {
                        confirmsReset = true
                    }
                } footer: {
                    Text("Löscht Einstellungen, Bestzeiten, Münzen und gekaufte Eier auf diesem Gerät.")
                }

                // App Review asks for the privacy policy and a way to contact the developer inside the app (guidelines
                // 5.1.1 and 1.5), and German law for a legal notice that is easy to reach (§ 5 DDG).
                Section {
                    if let url = WebPages.url(of: .privacyPolicy) {
                        Link("Datenschutz", destination: url)
                            .accessibilityIdentifier("settings.privacy")
                    }
                    if let url = WebPages.url(of: .support) {
                        Link("Support & Impressum", destination: url)
                            .accessibilityIdentifier("settings.support")
                    }
                    LabeledContent("Version", value: Self.version)
                } header: {
                    Text("Hilfe & Rechtliches")
                }
            }
            .navigationTitle("Einstellungen")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .confirmationDialog("Alle Daten zurücksetzen?", isPresented: $confirmsReset, titleVisibility: .visible) {
                Button("Zurücksetzen", role: .destructive) {
                    services.resetAllData()
                }
            } message: {
                Text("Das kann nicht rückgängig gemacht werden.")
            }
            .alert("Kein Kamerazugriff", isPresented: $showsCameraDenied) {
                Button("Einstellungen öffnen") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text(
                    "Erlaube Eggscape den Kamerazugriff in den iOS-Einstellungen, um den Kamera-Hintergrund zu nutzen."
                )
            }
            .sheet(isPresented: $showsCalibration) {
                CalibrationSheet()
            }
        }
    }

    /// Switching to the camera asks for permission first and falls back to white if it is declined.
    private var backgroundSelection: Binding<BackgroundMode> {
        Binding {
            services.settings.background
        } set: { mode in
            guard mode == .camera else {
                services.settings.background = mode
                return
            }
            Task {
                if await services.camera.requestAccess() {
                    services.settings.background = .camera
                } else {
                    services.settings.background = .white
                    showsCameraDenied = true
                }
            }
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

/// "Neu kalibrieren" outside a run: stores the current pose as level for the next runs.
private struct CalibrationSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    /// Holds the motion sensors while the sheet is open.
    @State private var owner = LeaseOwner()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text(
                        "Halte dein Handy so, wie du beim Laufen den Löffel halten willst, und tippe auf „Kalibrieren“."
                    )
                    .multilineTextAlignment(.center)
                    if services.motion.isAvailable {
                        SpiritLevelView(tilt: { services.motion.tilt })
                    } else {
                        Text("Dieses Gerät hat keinen Bewegungssensor.")
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        services.settings.calibrationZero = services.motion.tilt
                        dismiss()
                    } label: {
                        Text("Kalibrieren")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .primaryActionStyle()
                    .disabled(!services.motion.isAvailable)
                }
                .padding(24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Kalibrieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .onAppear { services.motion.start(for: owner) }
            .onDisappear { services.motion.stop(for: owner) }
        }
        // Large text needs more than half the screen.
        .presentationDetents([.medium, .large])
    }
}

/// The app's pages on the web, published with GitHub Pages from the repository's `site/` folder: the privacy policy,
/// and support with the legal notice (Impressum). Each page exists in German and in English. App Store Connect and the
/// store metadata name the same addresses.
enum WebPages {
    enum Page: CaseIterable {
        case privacyPolicy
        /// Contact, help and the legal notice.
        case support
    }

    enum Language: CaseIterable {
        case german
        case english

        /// The German pages for an app that runs in German, the English ones for any other language.
        init(appLanguage: String?) {
            let code = appLanguage.flatMap { Locale.Language(identifier: $0).languageCode }
            self = code == .german ? .german : .english
        }

        /// The language the app runs in: the localization iOS picked from the player's preferred languages.
        static var current: Language {
            Language(appLanguage: Bundle.main.preferredLocalizations.first)
        }
    }

    static func address(of page: Page, in language: Language) -> String {
        switch (page, language) {
        case (.privacyPolicy, .german): "https://juliusedel.github.io/eggscape/de/datenschutz/"
        case (.privacyPolicy, .english): "https://juliusedel.github.io/eggscape/en/privacy/"
        case (.support, .german): "https://juliusedel.github.io/eggscape/de/support/"
        case (.support, .english): "https://juliusedel.github.io/eggscape/en/support/"
        }
    }

    /// `nil` only for an address that is not a URL, which the unit tests rule out.
    static func url(of page: Page, in language: Language = .current) -> URL? {
        URL(string: address(of: page, in: language))
    }
}
