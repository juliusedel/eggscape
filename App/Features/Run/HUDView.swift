import SwiftUI

/// In-race heads-up display: distance, time, eggs left, pause and sprint.
struct HUDView: View {
    @Bindable var session: RunSession

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                stats
                Spacer(minLength: 0)
                Button {
                    session.pause()
                } label: {
                    Image(systemName: "pause.fill")
                        .font(.title2.weight(.semibold))
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.plain)
                .floatingPanel(cornerRadius: 26)
                .accessibilityLabel(Text("Pause"))
                .accessibilityIdentifier("hud.pause")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                SprintButton(isSprinting: $session.isSprinting)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
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
            EggCounter(left: hud.eggsLeft, total: hud.eggsTotal)
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
                .onChanged { _ in isSprinting = true }
                .onEnded { _ in isSprinting = false }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Sprinten"))
        .accessibilityHint(Text("Gedrückt halten, um schneller zu laufen. Das Ei wackelt dann stärker."))
        .accessibilityValue(isSprinting ? Text("An") : Text("Aus"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { isSprinting.toggle() }
        .accessibilityIdentifier("hud.sprint")
    }
}
