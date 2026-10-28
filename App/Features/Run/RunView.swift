import SpriteKit
import SwiftUI

/// Full-screen game: the SpriteKit scene with calibration, countdown, HUD, pause menu and results on top.
struct RunView: View {
    let session: RunSession
    var onRestart: () -> Void
    var onExit: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var showsGo = false

    var body: some View {
        ZStack {
            SpriteView(
                scene: session.scene,
                isPaused: session.phase == .paused,
                preferredFramesPerSecond: 60,
                options: [.ignoresSiblingOrder]
            )
            .ignoresSafeArea()
            .accessibilityLabel(Text("Löffel mit Ei"))

            overlay
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { session.start() }
        .onDisappear { session.stop() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                session.pause()
            }
        }
        .onChange(of: session.phase) { oldPhase, newPhase in
            if case .countdown = oldPhase, newPhase == .running {
                showsGo = true
            }
        }
    }

    @ViewBuilder
    private var overlay: some View {
        switch session.phase {
        case .calibrating:
            CalibrationOverlay(session: session, onCancel: onExit)
        case let .countdown(count):
            CountdownOverlay(count: count)
        case .running:
            HUDView(session: session)
                .overlay {
                    if showsGo {
                        GoBanner { showsGo = false }
                    }
                }
        case .paused:
            ZStack {
                HUDView(session: session)
                    .allowsHitTesting(false)
                PauseMenu(session: session, onQuit: onExit)
            }
        case let .finished(outcome):
            RunResultsView(outcome: outcome, onRestart: onRestart, onDone: onExit)
        }
    }
}
