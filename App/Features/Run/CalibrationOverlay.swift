import SwiftUI

/// The camera prompt that a run's calibration screen leads up to (see `RunView`).
struct CameraQuestion {
    /// The prompt is up.
    var isAsking: Bool
    /// Brings up the prompt.
    var ask: () -> Void
}

/// Asks the player to hold the phone like a spoon and stores that pose as level. While iOS has not asked for the camera
/// the run wants, it first says what the camera is for and then brings up the prompt.
struct CalibrationOverlay: View {
    let session: RunSession
    var cameraQuestion: CameraQuestion?
    var onCancel: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Scrolls only when large text does not fit.
        ScrollView {
            VStack(spacing: 12) {
                VStack(spacing: 16) {
                    if let cameraQuestion {
                        cameraNotice(cameraQuestion)
                    } else {
                        calibration
                    }
                }
                .padding(24)
                .floatingPanel()
                // Large text needs the whole screen for the panel, so the note follows it and scrolls along.
                if showsSafetyNote, dynamicTypeSize.isAccessibilitySize {
                    safetyNote
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Otherwise it stays down over the spoon's handle, so the panel stays short and the egg in the bowl in view.
        .safeAreaInset(edge: .bottom) {
            if showsSafetyNote, !dynamicTypeSize.isAccessibilitySize {
                safetyNote
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
        }
    }

    /// With the calibration itself. The camera notice keeps to its one point, and finger steering means a device
    /// without motion sensors, such as the Simulator, which nobody carries around.
    private var showsSafetyNote: Bool {
        cameraQuestion == nil && !session.showsFingerHint
    }

    private var safetyNote: some View {
        SafetyNote()
            .font(.footnote)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .floatingPanel(cornerRadius: 20)
    }

    /// Apple's guidance for a screen shown before a permission prompt: a single button, named so that it leads on to
    /// the prompt, and no way around it. So "Abbrechen" waits until the player has answered; either answer goes on to
    /// the calibration.
    @ViewBuilder
    private func cameraNotice(_ question: CameraQuestion) -> some View {
        Text("Gleich fragt iOS nach der Kamera")
            .font(.title2.bold())
            .multilineTextAlignment(.center)
        Text("Mit ihr siehst du durch dein Handy hindurch auf den Boden. Ohne Kamera spielst du auf Weiß.")
            .multilineTextAlignment(.center)
        Button(action: question.ask) {
            Text("Weiter")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .primaryActionStyle()
        .controlSize(.large)
        .disabled(question.isAsking)
        .accessibilityIdentifier("calibration.camera")
    }

    @ViewBuilder
    private var calibration: some View {
        Text("Halte dein Handy wie einen Löffel")
            .font(.title2.bold())
            .multilineTextAlignment(.center)
        if session.showsFingerHint {
            Text("Kein Bewegungssensor gefunden: Ziehe das Ei mit dem Finger, um es im Löffel zu halten.")
                .multilineTextAlignment(.center)
        } else {
            Text(
                "Halte es so, wie du gleich spielen willst, und tippe auf „Kalibrieren“. Diese Haltung gilt dann als gerade."
            )
            .multilineTextAlignment(.center)
            SpiritLevelView(tilt: { session.rawTilt })
        }
        Button {
            session.calibrate()
        } label: {
            Text(session.showsFingerHint ? "Los geht’s" : "Kalibrieren")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .primaryActionStyle()
        .controlSize(.large)
        .accessibilityIdentifier("calibration.calibrate")
        // Says where it leads: back to the pause menu, or out of a run that has not begun yet.
        Button(role: .cancel, action: onCancel) {
            Text(session.isRecalibrating ? "Zurück" : "Abbrechen")
        }
        .accessibilityIdentifier("calibration.cancel")
    }
}

/// The run moves by itself, so nobody has to run while looking at the phone, and whoever does should watch where they
/// go (App Review guideline 1.4.5). Shown where players get ready to hold the phone: on the tutorial's first page, on
/// the calibration screen and in the race lobby. Each place sets its own font.
struct SafetyNote: View {
    var body: some View {
        Text(
            "Im Spiel läufst du von selbst, du kannst also auch im Stehen spielen. Wenn du mitläufst, dann nur, wo Platz ist, und achte auf deine Umgebung."
        )
    }
}

/// A bubble that shows how the phone is currently held.
struct SpiritLevelView: View {
    /// Raw device tilt in radians, read every frame.
    var tilt: () -> SIMD2<Double>?

    var body: some View {
        TimelineView(.animation) { _ in
            let current = tilt() ?? .zero
            let limit = Double.pi / 6
            let offset = CGSize(
                width: CGFloat(max(-1, min(1, current.x / limit))) * 34,
                height: CGFloat(max(-1, min(1, -current.y / limit))) * 34
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
