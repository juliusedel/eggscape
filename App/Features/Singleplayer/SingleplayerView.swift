import EggscapeCore
import SwiftUI

/// Tab "Einzelspieler": time trial and endless run.
struct SingleplayerView: View {
    @Environment(AppServices.self) private var services
    @State private var distance = RaceDistance.short
    @State private var weather = WeatherOption.off

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Strecke", selection: $distance) {
                        ForEach(RaceDistance.allCases) { distance in
                            Text(distance.title).tag(distance)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("timeTrial.distance")
                    Text("\(Int(distance.meters)) m bis ins Ziel, drei Eier.")
                        .foregroundStyle(.secondary)
                    WeatherPicker(selection: $weather)
                    LabeledContent("Bestzeit") {
                        if let best = services.records.bestTime(distance: distance, weather: weather) {
                            Text(verbatim: RaceFormat.time(best)).monospacedDigit()
                        } else {
                            Text("Noch keine")
                        }
                    }
                    Button {
                        services.launcher.start(.timeTrial(distance, weather))
                    } label: {
                        Label("Zeitrennen starten", systemImage: "stopwatch.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .primaryActionStyle()
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                    .accessibilityIdentifier("timeTrial.start")
                } header: {
                    Text("Zeitrennen")
                }

                Section {
                    Text("Lauf, so weit du kommst. Alle 100 m wird das Wetter rauer.")
                        .foregroundStyle(.secondary)
                    LabeledContent("Rekord") {
                        if let best = services.records.bestEndless {
                            Text("\(RaceFormat.meters(best)) m").monospacedDigit()
                        } else {
                            Text("Noch keiner")
                        }
                    }
                    Button {
                        services.launcher.start(.endless)
                    } label: {
                        Label("Endlos starten", systemImage: "infinity")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .primaryActionStyle()
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                    .accessibilityIdentifier("endless.start")
                } header: {
                    Text("Endlos")
                }
            }
            .navigationTitle("Einzelspieler")
            .toolbar { SettingsToolbarButton() }
        }
    }
}

/// Weather choice for time trials and multiplayer races.
struct WeatherPicker: View {
    @Binding var selection: WeatherOption

    var body: some View {
        Picker(selection: $selection) {
            ForEach(WeatherOption.choices) { option in
                Label {
                    Text(option.title)
                } icon: {
                    Image(systemName: option.symbolName)
                }
                .tag(option)
            }
        } label: {
            Text("Wetter")
        }
        .accessibilityIdentifier("weather.picker")
    }
}
