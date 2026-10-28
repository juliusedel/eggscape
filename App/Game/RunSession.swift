import EggscapeCore
import Observation
import UIKit

/// Everything needed to start a run.
struct RunSetup: Hashable {
    var mode: RunMode
    /// Seed of the shared weather plan.
    var raceSeed: UInt64
    /// Seed of this player's footsteps. Hot-seat players share it, so everybody gets the same bumps.
    var localSeed: UInt64

    init(mode: RunMode, raceSeed: UInt64, localSeed: UInt64? = nil) {
        self.mode = mode
        self.raceSeed = raceSeed
        var derived = SplitMix64(seed: raceSeed).stream(0x10CA1)
        self.localSeed = localSeed ?? derived.next()
    }

    var course: Course {
        mode.course
    }

    var weatherSchedule: WeatherSchedule {
        WeatherSchedule(seed: raceSeed)
    }
}

/// How a run ended.
struct RunOutcome: Equatable {
    var mode: RunMode
    /// `true` if the finish line was reached, `false` if the last egg broke first.
    var finished: Bool
    var time: Double
    var meters: Double
    var eggsLost: Int
    var isPersonalBest: Bool
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

    let setup: RunSetup
    let scene: GameScene
    let background: BackgroundMode
    /// No motion sensors (Simulator): the player drags the egg with a finger instead.
    let usesTouchSteering: Bool
    private(set) var phase = Phase.calibrating {
        didSet { UIApplication.shared.isIdleTimerDisabled = phase.keepsScreenAwake }
    }

    private(set) var hud: HUDSnapshot
    /// Held down via the sprint button.
    var isSprinting = false

    @ObservationIgnored private let motion: MotionInput
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let haptics: Haptics
    @ObservationIgnored private let sounds: SoundPlayer
    /// `nil` for runs that must not count as personal bests (hot-seat turns).
    @ObservationIgnored private let records: RecordsStore?
    @ObservationIgnored private var calibration: TiltCalibration
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var endTask: Task<Void, Never>?

    init(
        setup: RunSetup,
        motion: MotionInput,
        settings: SettingsStore,
        records: RecordsStore?,
        haptics: Haptics,
        sounds: SoundPlayer
    ) {
        self.setup = setup
        self.motion = motion
        self.settings = settings
        self.records = records
        self.haptics = haptics
        self.sounds = sounds
        background = settings.background
        calibration = TiltCalibration(zero: settings.calibrationZero ?? .zero, sensitivity: settings.sensitivity)
        usesTouchSteering = !motion.isAvailable
        let engine = RunEngine(course: setup.course, weather: setup.weatherSchedule, localSeed: setup.localSeed)
        scene = GameScene(engine: engine)
        hud = scene.hudSnapshot
        scene.usesTouchSteering = usesTouchSteering
        scene.input = { [weak self] in self?.currentInput ?? .level }
        scene.onEvents = { [weak self] events in self?.handle(events) }
        scene.onHUD = { [weak self] snapshot in self?.hud = snapshot }
        scene.onFrame = { [weak self] engine in self?.haptics.updateDanger(rimDistance: engine.egg.rimDistance) }
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
        haptics.prepare()
        sounds.prepare()
        UIApplication.shared.isIdleTimerDisabled = phase.keepsScreenAwake
    }

    func stop() {
        countdownTask?.cancel()
        endTask?.cancel()
        motion.stop()
        haptics.shutDown()
        sounds.stopLoops()
        scene.mode = .ended
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Stores the current pose as level and starts (or resumes) with a countdown.
    func calibrate() {
        if let raw = motion.tilt {
            calibration.calibrate(at: raw)
            settings.calibrationZero = raw
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
            haptics.stopDanger()
            sounds.stopLoops()
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
                self?.sounds.play(.beep)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled {
                    return
                }
            }
            self?.sounds.play(.go)
            self?.phase = .running
            self?.scene.mode = .running
        }
    }

    // MARK: Events

    private func handle(_ events: [RunEvent]) {
        for event in events {
            switch event {
            case let .footstep(sprinting):
                haptics.footstep(sprinting: sprinting)
                sounds.play(.step, volume: sprinting ? 0.45 : 0.3)
            case .puddle:
                haptics.splash()
                sounds.play(.splash)
            case .lightningStrike:
                haptics.thunder()
                sounds.play(.thunder)
            case .eggDropped:
                haptics.crack()
                sounds.play(.crack)
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(0.3))
                    self?.sounds.play(.splat)
                }
            case .newEgg:
                sounds.play(.plop)
            case .finished:
                sounds.play(.finish)
                end()
            case .runOver:
                sounds.play(.fail)
                end()
            case .kick, .lightningWarning, .weatherChanged:
                break
            }
        }
    }

    private func end() {
        scene.mode = .ended
        isSprinting = false
        haptics.stopDanger()
        sounds.stopLoops()
        let engine = scene.engine
        let finished = engine.phase == .finished
        var isPersonalBest = false
        if let records {
            switch setup.mode {
            case let .timeTrial(distance, weather) where finished:
                isPersonalBest = records.recordTime(engine.elapsed, distance: distance, weather: weather)
            case .endless:
                isPersonalBest = records.recordEndless(meters: engine.meters)
            case .timeTrial:
                break
            }
        }
        let outcome = RunOutcome(
            mode: setup.mode,
            finished: finished,
            time: engine.elapsed,
            meters: engine.meters,
            eggsLost: engine.eggsLost,
            isPersonalBest: isPersonalBest
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
