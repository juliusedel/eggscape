import EggscapeCore
import SwiftUI

/// Tab "Bestenliste": personal bests now, Game Center leaderboards once connected.
struct LeaderboardView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(RaceDistance.allCases) { distance in
                        LabeledContent {
                            if let best = services.records.bestTime(distance: distance, weather: .off) {
                                Text(verbatim: RaceFormat.time(best)).monospacedDigit()
                            } else {
                                Text(verbatim: "–")
                            }
                        } label: {
                            Text("Zeitrennen \(Text(distance.title))")
                        }
                    }
                    LabeledContent("Endlos") {
                        if let best = services.records.bestEndless {
                            Text("\(RaceFormat.meters(best)) m").monospacedDigit()
                        } else {
                            Text(verbatim: "–")
                        }
                    }
                } header: {
                    Text("Deine Bestleistungen")
                } footer: {
                    Text("Bestzeiten ohne Wetter.")
                }
            }
            .navigationTitle("Bestenliste")
            .toolbar { SettingsToolbarButton() }
        }
    }
}
