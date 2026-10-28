import EggscapeCore
import Observation
import UIKit

/// Everything needed to start a run.
struct RunSetup: Equatable {
    var course: Course
    var weather: WeatherSchedule
    /// Seed for this player's own randomness (footsteps); the weather has its own seed.
    var seed: UInt64
}

/// How a run ended.
struct RunOutcome: Equatable {
    var course: Course
    /// `true` if the finish line was reached, `false` if the last egg broke first.
    var finished: Bool
    var time: Double
    var meters: Double
    var eggsLost: Int
}

/// Drives one run from calibration to results and connects the game scene with the SwiftUI overlays.
@MainActor
@Observable
final class RunSession: Identifiable {
    enum Phase: Equatable {
        case calibrating
        case countdown(Int)
        case running
        case paused
        case finished(RunOutcome)

        /// The screen must not dim while the player is busy holding the spoon.
        var keepsScreenAwake: Bool {
            if case .finished = self {
                false
            } else {
                true
            }
        }
    }

    let id = UUID()
    let setup: RunSetup
    let scene: GameScene
    /// No motion sensors (Simulator): the player drags the egg with a finger instead.
    let usesTouchSteering: Bool
    private(set) var phase = Phase.calibrating {
        didSet { UIApplication.shared.isIdleTimerDisabled = phase.keepsScreenAwake }
    }

    private(set) var hud: HUDSnapshot
    /// Held down via the sprint button.
    var isSprinting = false

    @ObservationIgnored private let motion: MotionInput
    @ObservationIgnored private var calibration: TiltCalibration
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var endTask: Task<Void, Never>?

    init(setup: RunSetup, motion: MotionInput, sensitivity: Double = 1) {
        self.setup = setup
        self.motion = motion
        calibration = TiltCalibration(sensitivity: sensitivity)
        usesTouchSteering = !motion.isAvailable
        let engine = RunEngine(course: setup.course, weather: setup.weather, localSeed: setup.seed)
        scene = GameScene(engine: engine)
        hud = scene.hudSnapshot
        scene.usesTouchSteering = usesTouchSteering
        scene.input = { [weak self] in self?.currentInput ?? .level }
        scene.onEvents = { [weak self] events in self?.handle(events) }
        scene.onHUD = { [weak self] snapshot in self?.hud = snapshot }
    }

    /// Raw device tilt for the calibration screen's spirit level, `nil` without motion sensors.
    var rawTilt: SIMD2<Double>? {
        motion.tilt
    }

    /// The tilt the egg currently feels.
    var calibratedTilt: SIMD2<Double> {
        motion.tilt.map(calibration.apply) ?? .zero
    }

    private var currentInput: RunEngine.Input {
        RunEngine.Input(tilt: calibratedTilt, sprint: isSprinting)
    }

    // MARK: Lifecycle

    func start() {
        motion.start()
        UIApplication.shared.isIdleTimerDisabled = phase.keepsScreenAwake
    }

    func stop() {
        countdownTask?.cancel()
        endTask?.cancel()
        motion.stop()
        scene.mode = .ended
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Stores the current pose as level and starts (or resumes) with a countdown.
    func calibrate() {
        if let raw = motion.tilt {
            calibration.calibrate(at: raw)
        }
        startCountdown()
    }

    func pause() {
        switch phase {
        case .running, .countdown:
            countdownTask?.cancel()
            isSprinting = false
            phase = .paused
            scene.mode = .paused
        case .calibrating, .paused, .finished:
            break
        }
    }

    func resume() {
        guard phase == .paused else { return }
        startCountdown()
    }

    func recalibrate() {
        guard phase == .paused else { return }
        phase = .calibrating
        scene.mode = .preview
    }

    private func startCountdown() {
        countdownTask?.cancel()
        scene.mode = .warmUp
        countdownTask = Task { [weak self] in
            for count in stride(from: 3, through: 1, by: -1) {
                self?.phase = .countdown(count)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled {
                    return
                }
            }
            self?.phase = .running
            self?.scene.mode = .running
        }
    }

    // MARK: Events

    private func handle(_ events: [RunEvent]) {
        for event in events {
            switch event {
            case .finished, .runOver:
                end()
            default:
                break
            }
        }
    }

    private func end() {
        scene.mode = .ended
        isSprinting = false
        let engine = scene.engine
        let outcome = RunOutcome(
            course: engine.course,
            finished: engine.phase == .finished,
            time: engine.elapsed,
            meters: engine.meters,
            eggsLost: engine.eggsLost
        )
        hud = scene.hudSnapshot
        // Give the finish or the broken egg a moment on screen before the results appear.
        endTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            if Task.isCancelled {
                return
            }
            self?.phase = .finished(outcome)
        }
    }
}
