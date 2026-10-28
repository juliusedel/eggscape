import SpriteKit
import SwiftUI

/// Full-screen game: the SpriteKit scene with calibration, countdown, HUD and pause menu on top. What appears when the
/// run is over is up to the caller (single-player results, hot-seat hand-over, multiplayer standings).
struct RunView<Results: View>: View {
    let session: RunSession
    var onQuit: () -> Void
    @ViewBuilder var results: (RunOutcome) -> Results

    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppServices.self) private var services
    @State private var showsGo = false

    var body: some View {
        ZStack {
            if session.background == .camera {
                CameraBackgroundView(feed: services.camera)
                    .ignoresSafeArea()
            }
            SpriteView(
                scene: session.scene,
                isPaused: session.phase == .paused,
                preferredFramesPerSecond: 60,
                options: session
                    .background == .camera ? [.ignoresSiblingOrder, .allowsTransparency] : [.ignoresSiblingOrder]
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
            CalibrationOverlay(session: session, onCancel: onQuit)
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
                PauseMenu(session: session, onQuit: onQuit)
            }
        case let .finished(outcome):
            results(outcome)
        }
    }
}
