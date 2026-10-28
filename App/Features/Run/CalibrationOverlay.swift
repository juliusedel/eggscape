import SwiftUI

/// Asks the player to hold the phone like a spoon and stores that pose as level.
struct CalibrationOverlay: View {
    let session: RunSession
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Text("Halte dein Handy wie einen Löffel")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                if session.usesTouchSteering {
                    Text("Kein Bewegungssensor gefunden: Ziehe das Ei mit dem Finger, um es im Löffel zu halten.")
                        .multilineTextAlignment(.center)
                } else {
                    Text(
                        "Halte es so, wie du gleich laufen willst, und tippe auf „Kalibrieren“. Diese Haltung gilt dann als gerade."
                    )
                    .multilineTextAlignment(.center)
                    SpiritLevel(session: session)
                }
                Button {
                    session.calibrate()
                } label: {
                    Text(session.usesTouchSteering ? "Los geht’s" : "Kalibrieren")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .primaryActionStyle()
                .controlSize(.large)
                .accessibilityIdentifier("calibration.calibrate")
                Button("Abbrechen", role: .cancel, action: onCancel)
                    .accessibilityIdentifier("calibration.cancel")
            }
            .padding(24)
            .floatingPanel()
            .padding(.horizontal, 20)
            .padding(.top, 12)
            Spacer()
        }
    }
}

/// A bubble that shows how the phone is currently held.
private struct SpiritLevel: View {
    let session: RunSession

    var body: some View {
        TimelineView(.animation) { _ in
            let tilt = session.rawTilt ?? .zero
            let limit = Double.pi / 6
            let offset = CGSize(
                width: CGFloat(max(-1, min(1, tilt.x / limit))) * 34,
                height: CGFloat(max(-1, min(1, -tilt.y / limit))) * 34
            )
            ZStack {
                Circle().stroke(.secondary, lineWidth: 2)
                Circle().stroke(.secondary.opacity(0.5), lineWidth: 1).frame(width: 22, height: 22)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 18, height: 18)
                    .offset(offset)
            }
            .frame(width: 88, height: 88)
        }
        .accessibilityHidden(true)
    }
}
