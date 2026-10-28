import EggscapeCore
import SwiftUI

/// Tab "Bestenliste": the player's own bests and the Game Center leaderboards (global or friends).
struct LeaderboardView: View {
    @Environment(AppServices.self) private var services
    @State private var leaderboard = LeaderboardID.shortTimeTrial
    @State private var scope = GameCenterService.Scope.global
    @State private var state = LoadState.idle

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(GameCenterService.Board)
        case failed
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Bestenliste", selection: $leaderboard) {
                        ForEach(LeaderboardID.allCases, id: \.self) { board in
                            Text(board.title).tag(board)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                    LabeledContent("Deine Bestleistung") {
                        Text(verbatim: personalBest ?? "–").monospacedDigit()
                    }
                }

                Section {
                    Picker("Wer", selection: $scope) {
                        Text("Alle").tag(GameCenterService.Scope.global)
                        Text("Freunde").tag(GameCenterService.Scope.friends)
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                    gameCenterContent
                } header: {
                    Text("Game Center")
                }
            }
            .navigationTitle("Bestenliste")
            .toolbar { SettingsToolbarButton() }
            .onAppear { services.gameCenter.signIn() }
            .task(id: LoadKey(leaderboard: leaderboard, scope: scope, status: services.gameCenter.status)) {
                await load()
            }
            .refreshable { await load() }
        }
    }

    @ViewBuilder
    private var gameCenterContent: some View {
        switch services.gameCenter.status {
        case .signedOut, .signingIn:
            HStack(spacing: 10) {
                ProgressView()
                Text("Anmeldung bei Game Center …")
            }
            .foregroundStyle(.secondary)
        case let .unavailable(message):
            VStack(alignment: .leading, spacing: 8) {
                Text("Game Center ist nicht verfügbar.")
                    .font(.headline)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Erneut versuchen") { services.gameCenter.signIn() }
            }
            .padding(.vertical, 4)
        case .signedIn:
            switch state {
            case .idle, .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Lade Bestenliste …")
                }
                .foregroundStyle(.secondary)
            case .failed:
                Text("Die Bestenliste konnte nicht geladen werden.")
                    .foregroundStyle(.secondary)
            case let .loaded(board) where board.entries.isEmpty:
                Text(scope == .friends ? "Noch keine Zeiten von Freunden." : "Noch keine Einträge. Sei der Erste!")
                    .foregroundStyle(.secondary)
            case let .loaded(board):
                ForEach(board.entries) { entry in
                    EntryRow(entry: entry)
                }
                if let local = board.localEntry, !board.entries.contains(local) {
                    EntryRow(entry: local)
                }
                Button {
                    services.gameCenter.showGameCenter()
                } label: {
                    Label("In Game Center öffnen", systemImage: "gamecontroller")
                }
            }
        }
    }

    private struct LoadKey: Equatable {
        let leaderboard: LeaderboardID
        let scope: GameCenterService.Scope
        let status: GameCenterService.Status
    }

    private func load() async {
        guard services.gameCenter.isSignedIn else { return }
        state = .loading
        do {
            state = try await .loaded(services.gameCenter.loadBoard(leaderboard.rawValue, scope: scope))
        } catch {
            state = .failed
        }
    }

    private var personalBest: String? {
        switch leaderboard.course {
        case let .timeTrial(distance):
            let times = WeatherOption.choices.compactMap { services.records.bestTime(distance: distance, weather: $0) }
            return times.min().map(RaceFormat.time)
        case .endless:
            return services.records.bestEndless.map { "\(RaceFormat.meters($0)) m" }
        }
    }
}

private struct EntryRow: View {
    let entry: GameCenterService.Entry

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: "\(entry.rank).")
                .font(.headline.monospacedDigit())
                .frame(minWidth: 36, alignment: .leading)
            Text(entry.name)
                .fontWeight(entry.isLocalPlayer ? .bold : .regular)
                .lineLimit(1)
            Spacer()
            Text(entry.score)
                .monospacedDigit()
        }
        .listRowBackground(entry.isLocalPlayer ? Color.accentColor.opacity(0.12) : nil)
        .accessibilityElement(children: .combine)
    }
}

extension LeaderboardID {
    var title: LocalizedStringResource {
        switch self {
        case .shortTimeTrial: "Kurz"
        case .mediumTimeTrial: "Mittel"
        case .longTimeTrial: "Lang"
        case .endless: "Endlos"
        }
    }
}
