import EggscapeCore
import SwiftUI

/// Players, distance and weather for a hot-seat race.
struct HotSeatSetupView: View {
    @Environment(AppServices.self) private var services
    @State private var names: [String] = ["", ""]
    @State private var distance = RaceDistance.short
    @State private var weather = WeatherOption.off

    var body: some View {
        Form {
            Section {
                ForEach(names.indices, id: \.self) { index in
                    TextField(text: $names[index]) {
                        Text("Spieler \(index + 1)")
                    }
                    .textContentType(.nickname)
                    .autocorrectionDisabled()
                    .onChange(of: names[index]) { _, value in
                        if value.count > SettingsStore.maxNameLength {
                            names[index] = String(value.prefix(SettingsStore.maxNameLength))
                        }
                    }
                }
                .onDelete { offsets in
                    if names.count - offsets.count >= HotSeatSession.playerRange.lowerBound {
                        names.remove(atOffsets: offsets)
                    }
                }
                if names.count < HotSeatSession.playerRange.upperBound {
                    Button {
                        names.append("")
                    } label: {
                        Label("Spieler hinzufügen", systemImage: "person.badge.plus")
                    }
                }
            } header: {
                Text("Mitspieler")
            } footer: {
                Text("Alle laufen dieselbe Strecke mit demselben Wetter. Wer am schnellsten ist, gewinnt.")
            }

            Section {
                Picker("Strecke", selection: $distance) {
                    ForEach(RaceDistance.allCases) { distance in
                        Text(distance.title).tag(distance)
                    }
                }
                .pickerStyle(.segmented)
                WeatherPicker(selection: $weather)
            } header: {
                Text("Rennen")
            }

            Section {
                Button {
                    services.launcher.startHotSeat(players: playerNames, distance: distance, weather: weather)
                } label: {
                    Text("Rennen starten")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .primaryActionStyle()
                .listRowInsets(EdgeInsets())
                .accessibilityIdentifier("hotSeat.start")
            }
        }
        .navigationTitle("An einem Handy")
        .onAppear {
            if names[0].isEmpty, !services.settings.playerName.isEmpty {
                names[0] = services.settings.playerName
            }
        }
    }

    /// Empty fields become "Spieler 1", "Spieler 2", ...
    private var playerNames: [String] {
        names.enumerated().map { index, name in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? String(localized: "Spieler \(index + 1)") : trimmed
        }
    }
}

/// Hand-over screens, the runs and the final standings of a hot-seat race.
struct HotSeatFlowView: View {
    let session: HotSeatSession
    @Environment(AppServices.self) private var services

    var body: some View {
        switch session.stage {
        case let .handOver(index):
            PassPhoneView(
                name: session.entries[index].name,
                turn: index + 1,
                total: session.entries.count,
                onReady: session.beginTurn,
                onCancel: services.launcher.close
            )
        case let .playing(run):
            RunView(session: run, onQuit: services.launcher.close) { outcome in
                HotSeatTurnResult(
                    name: session.entries[session.currentIndex ?? 0].name,
                    outcome: outcome,
                    isLastTurn: (session.currentIndex ?? 0) == session.entries.count - 1
                ) {
                    session.finishTurn(with: outcome)
                }
            }
            .id(ObjectIdentifier(run))
        case .standings:
            HotSeatStandingsView(
                entries: session.ranking,
                onAgain: { services.launcher.flow = .hotSeat(session.playAgain()) },
                onDone: services.launcher.close
            )
        }
    }
}

private struct PassPhoneView: View {
    let name: String
    let turn: Int
    let total: Int
    var onReady: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Lauf \(turn) von \(total)")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Gib das Handy an \(name)")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Spacer()
            Button(action: onReady) {
                Text("Ich bin bereit")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .primaryActionStyle()
            .controlSize(.large)
            .accessibilityIdentifier("hotSeat.ready")
            Button("Rennen abbrechen", role: .cancel, action: onCancel)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

private struct HotSeatTurnResult: View {
    let name: String
    let outcome: RunOutcome
    let isLastTurn: Bool
    var onNext: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(name)
                .font(.title.bold())
            if outcome.finished {
                Text("Im Ziel nach \(RaceFormat.time(outcome.time))")
                    .font(.title3)
            } else {
                Text("Alle Eier kaputt nach \(RaceFormat.meters(outcome.meters)) m")
                    .font(.title3)
            }
            Button(action: onNext) {
                Text(isLastTurn ? "Zur Rangliste" : "Nächster Lauf")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .primaryActionStyle()
            .controlSize(.large)
            .accessibilityIdentifier("hotSeat.next")
        }
        .padding(24)
        .frame(maxWidth: 400)
        .floatingPanel()
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.2))
    }
}

private struct HotSeatStandingsView: View {
    let entries: [HotSeatSession.Entry]
    var onAgain: () -> Void
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(entries.enumerated()), id: \.element.id) { place, entry in
                    HStack(spacing: 12) {
                        Text(verbatim: "\(place + 1).")
                            .font(.title2.bold())
                            .monospacedDigit()
                            .frame(width: 40, alignment: .leading)
                        VStack(alignment: .leading) {
                            Text(entry.name).font(.headline)
                            if let outcome = entry.outcome {
                                Text("\(outcome.eggsLost) Eier verloren")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let outcome = entry.outcome {
                            if outcome.finished {
                                Text(verbatim: RaceFormat.time(outcome.time)).monospacedDigit().bold()
                            } else {
                                Text("\(RaceFormat.meters(outcome.meters)) m").monospacedDigit()
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .navigationTitle("Rangliste")
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button(action: onDone) {
                        Text("Fertig").frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .secondaryActionStyle()
                    Button(action: onAgain) {
                        Text("Nochmal").frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .primaryActionStyle()
                }
                .font(.headline)
                .controlSize(.large)
                .padding()
            }
        }
    }
}
