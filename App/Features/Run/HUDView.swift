import SwiftUI

/// In-race heads-up display: distance, time, eggs left, pause and sprint.
struct HUDView: View {
    @Bindable var session: RunSession
    /// Leaves a multiplayer race from its menu; single runs are quit from the pause menu.
    var onQuit: () -> Void
    @State private var showsRaceMenu = false

    var body: some View {
        VStack(spacing: 0) {
            if !session.opponents.isEmpty {
                RaceProgressBar(session: session)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }
            HStack(alignment: .top, spacing: 12) {
                stats
                Spacer(minLength: 0)
                Button {
                    if session.allowsPause {
                        session.pause()
                    } else {
                        showsRaceMenu = true
                    }
                } label: {
                    Image(systemName: "pause.fill")
                        .font(.title2.weight(.semibold))
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.plain)
                .floatingPanel(cornerRadius: 26)
                // The run is over; only its results are still to come.
                .disabled(session.hasEnded)
                .accessibilityLabel(Text("Pause"))
                .accessibilityShowsLargeContentViewer()
                .accessibilityIdentifier("hud.pause")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if let toast = session.toast {
                Text(toast)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .floatingPanel(cornerRadius: 18)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                SprintButton(isSprinting: $session.isSprinting)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .animation(.snappy, value: session.toast)
        .overlay {
            if showsRaceMenu {
                RaceMenu(session: session, onLeave: onQuit) { showsRaceMenu = false }
            }
        }
        // The spoon needs most of the screen, so the HUD grows only so far; the stats shrink to fit beside the button.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var stats: some View {
        let hud = session.hud
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                Label {
                    if let length = hud.courseLength {
                        Text("\(RaceFormat.meters(hud.meters)) / \(RaceFormat.meters(length)) m")
                    } else {
                        Text("\(RaceFormat.meters(hud.meters)) m")
                    }
                } icon: {
                    Image(systemName: "flag.checkered")
                }
                .accessibilityIdentifier("hud.meters")
                Label {
                    Text(verbatim: RaceFormat.time(hud.elapsed))
                } icon: {
                    Image(systemName: "stopwatch")
                }
                .accessibilityLabel(Text("Zeit \(RaceFormat.time(hud.elapsed))"))
            }
            .font(.headline.monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            HStack(spacing: 14) {
                EggCounter(left: hud.eggsLeft, total: hud.eggsTotal)
                if hud.weather.kind != .clear {
                    WeatherBadge(hud: hud)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .floatingPanel(cornerRadius: 20)
    }
}

/// Remaining eggs as small egg icons; broken ones are drawn hollow.
struct EggCounter: View {
    let left: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< total, id: \.self) { index in
                let intact = index < left
                EggShape()
                    .fill(intact ? Color(red: 1, green: 0.97, blue: 0.9) : .clear)
                    .overlay(EggShape().stroke(Color.primary.opacity(intact ? 0.35 : 0.25), lineWidth: 1.5))
                    .frame(width: 16, height: 21)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Noch \(left) von \(total) Eiern"))
        .accessibilityIdentifier("hud.eggs")
    }
}

/// Hold to sprint: faster, but the egg wobbles more.
struct SprintButton: View {
    @Binding var isSprinting: Bool
    /// Unlike an `onEnded` callback this also resets when the system cancels the touch (a call, Control Center).
    @GestureState private var isPressed = false

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "figure.run")
                .font(.title.weight(.bold))
            Text("Sprint")
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(.white)
        .frame(width: 92, height: 92)
        .background(Circle().fill(Color.accentColor.gradient))
        .scaleEffect(isSprinting ? 0.92 : 1)
        .animation(.spring(duration: 0.2), value: isSprinting)
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, pressed, _ in pressed = true }
        )
        .onChange(of: isPressed) { _, pressed in
            isSprinting = pressed
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Sprinten"))
        .accessibilityHint(Text("Gedrückt halten, um schneller zu laufen. Das Ei wackelt dann stärker."))
        .accessibilityValue(isSprinting ? Text("An") : Text("Aus"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { isSprinting.toggle() }
        .accessibilityIdentifier("hud.sprint")
    }
}

/// Every racer's position along the course, shown during multiplayer races.
struct RaceProgressBar: View {
    let session: RunSession

    var body: some View {
        let length = session.hud.courseLength ?? 1
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    ForEach(session.opponents) { opponent in
                        marker(name: opponent.name, isSelf: false, isConnected: opponent.isConnected)
                            .offset(x: offset(opponent.meters, length: length, width: proxy.size.width))
                    }
                    marker(name: String(localized: "Du"), isSelf: true, isConnected: true)
                        .offset(x: offset(session.hud.meters, length: length, width: proxy.size.width))
                }
            }
            .frame(height: 30)
        }
        .padding(10)
        .floatingPanel(cornerRadius: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Rennstand"))
        .accessibilityValue(Text(accessibilitySummary))
    }

    private func offset(_ meters: Double, length: Double, width: CGFloat) -> CGFloat {
        CGFloat(min(max(meters / length, 0), 1)) * (width - 28)
    }

    private func marker(name: String, isSelf: Bool, isConnected: Bool) -> some View {
        VStack(spacing: 0) {
            Circle()
                .fill(isSelf ? Color.accentColor : (isConnected ? Color.blue : Color.gray))
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(.white, lineWidth: 2))
            Text(name)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
        }
        .frame(width: 28)
    }

    private var accessibilitySummary: String {
        let others = session.opponents.map { "\($0.name) \(RaceFormat.meters($0.meters)) m" }
        return ([String(localized: "Du \(RaceFormat.meters(session.hud.meters)) m")] + others).joined(separator: ", ")
    }
}

/// The menu behind the pause button during a multiplayer race: the race keeps running.
private struct RaceMenu: View {
    let session: RunSession
    var onLeave: () -> Void
    var onClose: () -> Void
    @Environment(AppServices.self) private var services
    @State private var confirmsLeave = false

    var body: some View {
        @Bindable var settings = services.settings
        VStack(spacing: 14) {
            Text("Das Rennen läuft weiter")
                .font(.headline)
            Button {
                session.calibrateInPlace()
                onClose()
            } label: {
                Label("Neu kalibrieren", systemImage: "scope")
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .secondaryActionStyle()
            Toggle(isOn: $settings.isSoundOn) {
                Label("Ton", systemImage: settings.isSoundOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
            }
            .padding(.horizontal, 6)
            Button(role: .destructive) {
                confirmsLeave = true
            } label: {
                Label("Rennen verlassen", systemImage: "xmark")
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .secondaryActionStyle()
            .confirmationDialog("Rennen verlassen?", isPresented: $confirmsLeave, titleVisibility: .visible) {
                Button("Verlassen", role: .destructive, action: onLeave)
            } message: {
                session.race?.isReferee == true
                    ? Text("Die anderen laufen noch. Wenn du als Host gehst, endet das Rennen auch für sie.")
                    : Text("Die anderen laufen ohne dich weiter.")
            }
            Button("Zurück zum Rennen", action: onClose)
                .primaryActionStyle()
        }
        .font(.headline)
        .controlSize(.large)
        .padding(24)
        .frame(maxWidth: 360)
        .floatingPanel()
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The current weather: icon, strength in three steps and, with wind, an arrow that shows the gust.
struct WeatherBadge: View {
    let hud: HUDSnapshot

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: hud.weather.kind.symbolName)
                .symbolRenderingMode(.multicolor)
            HStack(spacing: 2) {
                ForEach(0 ..< 3, id: \.self) { step in
                    Capsule()
                        .fill(Double(step) < level ? Color.primary : Color.primary.opacity(0.2))
                        .frame(width: 4, height: 8 + CGFloat(step) * 3)
                }
            }
            if hud.weather.kind == .wind || hud.weather.kind == .storm {
                Image(systemName: hud.wind >= 0 ? "arrow.right" : "arrow.left")
                    .font(.subheadline.weight(.bold))
                    .opacity(0.35 + 0.65 * hud.gust)
                    .scaleEffect(0.8 + 0.4 * hud.gust)
                    .animation(.easeOut(duration: 0.3), value: hud.gust)
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(hud.weather.kind.title))
        .accessibilityValue(Text("Stärke \(Int(level)) von 3"))
        .accessibilityIdentifier("hud.weather")
    }

    private var level: Double {
        max(1, (hud.weather.intensity * 3).rounded(.up))
    }
}
