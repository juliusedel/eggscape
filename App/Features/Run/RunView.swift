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
            if wantsCamera {
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
        .onAppear {
            session.start()
            // An accepted invitation waits until the run and its results are gone (see `RootView`).
            services.navigation.setBusy(true, for: session)
            // Never asks for access here; a run that may ask does so from its calibration screen (`cameraQuestion`).
            if wantsCamera {
                services.camera.start(for: session)
            }
            session.scene.showsCamera = showsCamera
        }
        .onDisappear {
            session.stop()
            services.navigation.setBusy(false, for: session)
            services.camera.stop(for: session)
        }
        .onChange(of: services.camera.status) {
            session.scene.showsCamera = showsCamera
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                services.haptics.resume()
            } else {
                session.pause()
            }
        }
        .onChange(of: session.phase) { oldPhase, newPhase in
            if case .countdown = oldPhase, newPhase == .running {
                showsGo = true
            }
            // A paused run may wait for a long time, maybe in the background; it does not need the camera meanwhile.
            if newPhase == .paused {
                services.camera.stop(for: session)
            } else if oldPhase == .paused, wantsCamera {
                services.camera.start(for: session)
            }
        }
    }

    /// The player chose the camera and it is not known to be unavailable.
    private var wantsCamera: Bool {
        session.background == .camera && services.camera.isUsable
    }

    /// A run that starts on its calibration screen may ask for the camera there, which on a fresh install, where the
    /// camera is the default, is the first moment the camera is needed. A race starts with the shared countdown
    /// instead, which the prompt would cover while the others run on; it keeps the white surface, and the next single
    /// or hot-seat run asks.
    private var mayAskForCamera: Bool {
        session.race == nil
    }

    /// While iOS has not asked for the camera, the calibration screen of a run that may ask first says what the camera
    /// is for, and its "Weiter" brings up the prompt; either answer goes on to the calibration.
    private var cameraQuestion: CameraQuestion? {
        guard wantsCamera, mayAskForCamera else { return nil }
        switch services.camera.status {
        case .notAsked, .asking:
            return CameraQuestion(isAsking: services.camera.status == .asking) {
                services.camera.askForAccess(for: session)
            }
        case .idle, .running, .unavailable, .denied:
            return nil
        }
    }

    /// The scene turns transparent only once the camera really delivers pictures; until then it stays white.
    private var showsCamera: Bool {
        session.background == .camera && services.camera.status == .running
    }

    @ViewBuilder
    private var overlay: some View {
        switch session.phase {
        case .calibrating:
            // A recalibration from the pause menu goes back there instead of ending the run.
            CalibrationOverlay(
                session: session,
                cameraQuestion: cameraQuestion,
                onCancel: session.isRecalibrating ? session.cancelRecalibration : onQuit
            )
        case let .countdown(count):
            CountdownOverlay(count: count)
        case .running:
            HUDView(session: session, onQuit: onQuit)
                .overlay {
                    if showsGo {
                        GoBanner { showsGo = false }
                    }
                }
        case .paused:
            ZStack {
                HUDView(session: session, onQuit: onQuit)
                    .allowsHitTesting(false)
                PauseMenu(session: session, onQuit: onQuit)
            }
        case let .finished(outcome):
            results(outcome)
        }
    }
}
