import SwiftUI

/// Sound, vibration, sensitivity, calibration, player name, background and data reset.
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

                Section {
                    LabeledContent("Version", value: Self.version)
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Halte dein Handy so, wie du beim Laufen den Löffel halten willst, und tippe auf „Kalibrieren“.")
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
            .navigationTitle("Kalibrieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .onAppear { services.motion.start() }
            .onDisappear { services.motion.stop() }
        }
        .presentationDetents([.medium])
    }
}
