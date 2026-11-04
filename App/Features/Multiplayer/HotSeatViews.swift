import EggscapeCore
import SwiftUI

/// Players, distance and weather for a hot-seat race.
struct HotSeatSetupView: View {
    @Environment(AppServices.self) private var services
    @State private var roster = HotSeatRoster()
    @State private var distance = RaceDistance.short
    @State private var weather = WeatherOption.off

    var body: some View {
        Form {
            Section {
                // Rows by the player's id, and each field bound to its player's name by that id, not by position: see
                // `HotSeatRoster`.
                ForEach(roster.players) { player in
                    TextField(text: $roster[nameOf: player.id]) {
                        Text("Spieler \(roster.number(of: player))")
                    }
                    .textContentType(.nickname)
                    .autocorrectionDisabled()
                    .onChange(of: player.name) {
                        roster.limitNames()
                    }
                    // With the fewest players a race takes, a swipe would offer a delete that does nothing.
                    .deleteDisabled(!roster.canRemovePlayer)
                    .accessibilityIdentifier("hotSeat.name")
                }
                .onDelete { offsets in
                    roster.removePlayers(atOffsets: offsets)
                }
                if roster.canAddPlayer {
                    Button {
                        roster.addPlayer()
                    } label: {
                        Label("Spieler hinzufügen", systemImage: "person.badge.plus")
                    }
                    .accessibilityIdentifier("hotSeat.addPlayer")
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
                    services.launcher.startHotSeat(players: roster.playerNames, distance: distance, weather: weather)
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
            roster.prefillFirstName(services.settings.playerName)
        }
    }
}

/// The players of the hot-seat setup before the race, in running order: two to four (`HotSeatSession.playerRange`).
///
/// Every row has an id of its own, and its text field reads and writes the name by that id. The setup used to bind each
/// field to `names[index]`: deleting a row then removed the last row's cell instead of the deleted one, and a deleted
/// row keeps its binding while it animates out, so a field still being edited could read or write through it. By
/// position that binding points at the next row's name, or after deleting the last row past the end of the list, which
/// crashes ("Index out of range"). `ForEach($players)` would not help, as it also binds each row by position. Here a
/// field whose row is gone reads an empty name and changes nothing.
@MainActor
struct HotSeatRoster {
    struct Player: Identifiable {
        let id = UUID()
        var name = ""
    }

    /// Changes only through `addPlayer()` and `removePlayers(atOffsets:)`, which keep the count in range.
    private(set) var players: [Player]

    init() {
        players = (0 ..< HotSeatSession.playerRange.lowerBound).map { _ in Player() }
    }

    /// The name typed for the player with `id`, for a text field. A player who is no longer on the list has an empty
    /// name, and setting it changes nothing.
    subscript(nameOf id: Player.ID) -> String {
        get {
            players.first { $0.id == id }?.name ?? ""
        }
        set {
            if let index = players.firstIndex(where: { $0.id == id }) {
                players[index].name = newValue
            }
        }
    }

    var canAddPlayer: Bool {
        players.count < HotSeatSession.playerRange.upperBound
    }

    var canRemovePlayer: Bool {
        players.count > HotSeatSession.playerRange.lowerBound
    }

    mutating func addPlayer() {
        guard canAddPlayer else { return }
        players.append(Player())
    }

    /// Deletes the rows at `offsets`, positions as a list's swipe to delete reports them, unless that would leave fewer
    /// players than a race takes. Positions that do not exist leave the list as it is.
    mutating func removePlayers(atOffsets offsets: IndexSet) {
        guard offsets.allSatisfy(players.indices.contains),
              players.count - offsets.count >= HotSeatSession.playerRange.lowerBound
        else { return }
        players.remove(atOffsets: offsets)
    }

    /// Cuts every name to `SettingsStore.maxNameLength` characters, the length of the settings' player name. The setup
    /// calls this after every change instead of limiting the name in its setter: a setter that keeps the old value
    /// leaves the extra character in the text field.
    mutating func limitNames() {
        for index in players.indices where players[index].name.count > SettingsStore.maxNameLength {
            players[index].name = String(players[index].name.prefix(SettingsStore.maxNameLength))
        }
    }

    /// Puts `name`, the player's own name from the settings, in the first row unless something was typed there.
    mutating func prefillFirstName(_ name: String) {
        guard !name.isEmpty, players.first?.name.isEmpty == true else { return }
        players[0].name = String(name.prefix(SettingsStore.maxNameLength))
    }

    /// The player's place in the running order, from 1, as in the placeholder "Spieler 2". A row that is being deleted
    /// counts as the last.
    func number(of player: Player) -> Int {
        (players.firstIndex { $0.id == player.id } ?? players.count) + 1
    }

    /// The names the race starts with, in running order: what was typed, without the spaces around it, and for an empty
    /// row its placeholder, "Spieler 1", "Spieler 2" and so on by its place in the list.
    var playerNames: [String] {
        players.enumerated().map { index, player in
            let trimmed = player.name.trimmingCharacters(in: .whitespacesAndNewlines)
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
