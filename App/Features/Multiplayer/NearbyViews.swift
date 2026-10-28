import EggscapeCore
import SwiftUI

/// "In der Nähe": create a room or join one. The Local Network prompt appears only once a choice is made.
struct NearbyView: View {
    @Environment(AppServices.self) private var services
    @State private var session: NearbySession?

    init(initialSession: NearbySession? = nil) {
        _session = State(initialValue: initialSession)
    }

    var body: some View {
        Group {
            if let session {
                NearbyRoomView(session: session) {
                    session.leave()
                    self.session = nil
                }
            } else {
                chooser
            }
        }
        .navigationTitle("In der Nähe")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            session?.leave()
            session = nil
        }
    }

    private var chooser: some View {
        VStack(spacing: 24) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Lauft mit bis zu 4 Handys im selben Raum gegeneinander, ganz ohne Internet.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            VStack(spacing: 12) {
                Button {
                    session = NearbySession(role: .host, services: services)
                } label: {
                    Label("Raum erstellen", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .primaryActionStyle()
                .accessibilityIdentifier("nearby.host")
                Button {
                    session = NearbySession(role: .joiner, services: services)
                } label: {
                    Label("Beitreten", systemImage: "person.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .secondaryActionStyle()
                .accessibilityIdentifier("nearby.join")
            }
            .controlSize(.large)
            Text("Du spielst als \(services.settings.displayName). Den Namen änderst du in den Einstellungen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Everything after the choice: room list, lobby, race and results.
private struct NearbyRoomView: View {
    let session: NearbySession
    var onLeave: () -> Void
    @Environment(AppServices.self) private var services

    var body: some View {
        content
            .fullScreenCover(isPresented: isRacing) {
                if let run = session.run {
                    RunView(session: run, onQuit: onLeave) { _ in
                        NearbyResultsOverlay(session: session, onLeave: onLeave)
                    }
                    .id(ObjectIdentifier(run))
                }
            }
            .onAppear { services.motion.start() }
            .onDisappear { services.motion.stop() }
    }

    @ViewBuilder
    private var content: some View {
        switch session.stage {
        case .browsing:
            RoomList(session: session)
        case let .connecting(host):
            VStack(spacing: 16) {
                ProgressView()
                Text("Verbinde mit \(host) …")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .lobby, .racing, .results:
            LobbyView(session: session)
        case let .failed(message):
            ContentUnavailableView {
                Label("Verbindung verloren", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Zurück", action: onLeave)
                    .primaryActionStyle()
            }
        }
    }

    private var isRacing: Binding<Bool> {
        Binding {
            switch session.stage {
            case .racing, .results: session.run != nil
            default: false
            }
        } set: { _ in }
    }
}

private struct RoomList: View {
    let session: NearbySession

    var body: some View {
        List {
            Section {
                if session.rooms.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Suche Räume in der Nähe …")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(session.rooms) { room in
                        Button {
                            session.join(room)
                        } label: {
                            Label {
                                Text("Raum von \(room.hostName)")
                            } icon: {
                                Image(systemName: "house.fill")
                            }
                        }
                        .accessibilityIdentifier("nearby.room")
                    }
                }
            } header: {
                Text("Räume")
            } footer: {
                Text("Bitte den Host, auf „Raum erstellen“ zu tippen. Ihr müsst nah beieinander sein.")
            }
        }
    }
}

/// Players, race settings and the ready/start buttons.
private struct LobbyView: View {
    let session: NearbySession

    var body: some View {
        List {
            Section {
                ForEach(session.lobby.players) { player in
                    PlayerRow(player: player, isMe: player.id == session.me.id)
                }
            } header: {
                Text("Spieler (\(session.lobby.connectedPlayers.count) von 4)")
            }

            Section {
                if session.isHost {
                    Picker("Strecke", selection: distance) {
                        ForEach(RaceDistance.allCases) { distance in
                            Text(distance.title).tag(distance)
                        }
                    }
                    .pickerStyle(.segmented)
                    WeatherPicker(selection: weather)
                } else {
                    LabeledContent("Strecke") { Text(session.lobby.settings.distance.title) }
                    LabeledContent("Wetter") { Text(session.lobby.settings.weather.title) }
                }
            } header: {
                Text("Rennen")
            } footer: {
                if !session.isHost {
                    Text("Strecke und Wetter wählt der Host.")
                }
            }

            Section {
                Button {
                    session.setReady(!session.isReady)
                } label: {
                    Label(
                        session.isReady ? "Doch nicht bereit" : "Kalibrieren und bereit",
                        systemImage: session.isReady ? "xmark.circle" : "checkmark.circle.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 36)
                }
                .secondaryActionStyle()
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .accessibilityIdentifier("nearby.ready")
                if session.isHost {
                    Button {
                        session.startRace()
                    } label: {
                        Text("Rennen starten")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .primaryActionStyle()
                    .disabled(!session.lobby.canStart)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .accessibilityIdentifier("nearby.start")
                }
            } footer: {
                Text(
                    "Halte dein Handy so, wie du laufen willst, wenn du auf „Bereit“ tippst: Diese Haltung gilt als gerade."
                )
            }
        }
    }

    private var distance: Binding<RaceDistance> {
        Binding {
            session.lobby.settings.distance
        } set: { value in
            var settings = session.lobby.settings
            settings.distance = value
            session.setSettings(settings)
        }
    }

    private var weather: Binding<WeatherOption> {
        Binding {
            session.lobby.settings.weather
        } set: { value in
            var settings = session.lobby.settings
            settings.weather = value
            session.setSettings(settings)
        }
    }
}

private struct PlayerRow: View {
    let player: PlayerInfo
    let isMe: Bool

    var body: some View {
        HStack(spacing: 12) {
            EggThumbnail(
                appearance: (SkinCatalog.skin(id: player.eggSkinID) ?? SkinCatalog.defaultSkin).appearance,
                width: 24
            )
            .frame(width: 30, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(player.nickname).font(.headline)
                    if isMe {
                        Text("Du").font(.caption.bold()).foregroundStyle(.secondary)
                    }
                    if player.isHost {
                        Text("Host")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.15), in: .capsule)
                    }
                }
                if !player.isConnected {
                    Text("Verbindung verloren")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            Image(systemName: player.isReady ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(player.isReady ? Color.green : Color.secondary)
                .accessibilityLabel(player.isReady ? Text("Bereit") : Text("Nicht bereit"))
        }
        .accessibilityElement(children: .combine)
    }
}

/// Shown over the finished run: waiting for the others, then the standings.
private struct NearbyResultsOverlay: View {
    let session: NearbySession
    var onLeave: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            if case let .results(results) = session.stage {
                Text("Ergebnis")
                    .font(.largeTitle.bold())
                ForEach(results.entries) { entry in
                    HStack(spacing: 12) {
                        Text(verbatim: "\(entry.place).")
                            .font(.title3.bold().monospacedDigit())
                            .frame(width: 36, alignment: .leading)
                        Text(entry.nickname)
                            .fontWeight(entry.playerID == session.me.id ? .bold : .regular)
                        Spacer()
                        statusText(entry)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
                if let reward = session.reward, reward.total > 0 {
                    HStack(spacing: 8) {
                        CoinIcon(size: 24)
                        Text("+\(reward.total) Münzen").font(.headline)
                    }
                }
                HStack(spacing: 12) {
                    Button(action: onLeave) {
                        Text("Verlassen").frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .secondaryActionStyle()
                    if session.isHost {
                        Button(action: session.rematch) {
                            Text("Nochmal").frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .primaryActionStyle()
                    }
                }
                .font(.headline)
                .controlSize(.large)
                if !session.isHost {
                    Text("Der Host kann eine neue Runde starten.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
                Text("Warte auf die anderen …")
                    .font(.headline)
            }
        }
        .padding(24)
        .frame(maxWidth: 420)
        .floatingPanel()
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.2))
    }

    @ViewBuilder
    private func statusText(_ entry: RaceResultEntry) -> some View {
        switch entry.status {
        case let .finished(time):
            Text(verbatim: RaceFormat.time(time))
        case let .outOfEggs(meters):
            Text("\(RaceFormat.meters(meters)) m, alle Eier kaputt")
        case .disconnected:
            Text("Verbindung verloren").foregroundStyle(.secondary)
        }
    }
}
