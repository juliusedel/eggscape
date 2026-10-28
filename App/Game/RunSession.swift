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

    /// The shared weather plan; every player of a race derives the same one from `raceSeed`.
    var weatherSchedule: WeatherSchedule {
        WeatherSchedule(seed: raceSeed, option: mode.weather, course: course)
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
    /// Coins earned, `nil` where runs earn nothing (hot-seat turns).
    var reward: CoinReward?
}

/// What a run counts towards.
struct RunRules {
    /// Personal bests and Game Center leaderboards.
    var countsAsRecord: Bool
    /// Coins for the shop.
    var earnsCoins: Bool

    static let singlePlayer = RunRules(countsAsRecord: true, earnsCoins: true)
    /// Several people share the phone, so nobody's records or coins change.
    static let hotSeat = RunRules(countsAsRecord: false, earnsCoins: false)
    /// Coins are credited once the race results (with the place) are known.
    static let race = RunRules(countsAsRecord: false, earnsCoins: false)
}

/// How a multiplayer race plugs into a run: a shared start time and callbacks that report this player's race.
struct RaceHooks {
    /// "Los!" on this phone's clock, already converted from the host's clock.
    var startAt: ContinuousClock.Instant
    /// About ten times per second.
    var onProgress: (_ meters: Double, _ eggsLeft: Int) -> Void
    var onEggDropped: (_ eggsLeft: Int) -> Void
    var onFinished: (RunOutcome) -> Void
}

/// Another player's position during a race, for the HUD's progress bar.
struct OpponentProgress: Identifiable, Equatable {
    let id: String
    var name: String
    var meters: Double
    var eggsLeft: Int
    var isConnected: Bool
    var isDone: Bool
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
    /// What the player chose; the view falls back to white when the camera is unavailable.
    let background: BackgroundMode
    /// No motion sensors (Simulator): the player drags the egg with a finger instead.
    let usesTouchSteering: Bool
    private(set) var phase = Phase.calibrating {
        didSet { UIApplication.shared.isIdleTimerDisabled = phase.keepsScreenAwake }
    }

    private(set) var hud: HUDSnapshot
    /// Held down via the sprint button.
    var isSprinting = false
    /// Set for multiplayer races; such runs cannot be paused.
    let race: RaceHooks?
    /// The other racers, updated by the multiplayer coordinator.
    var opponents: [OpponentProgress] = []
    /// A short message about the other racers, e.g. "Mia hat ein Ei verloren".
    private(set) var toast: String?

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let rules: RunRules
    @ObservationIgnored private var calibration: TiltCalibration
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var endTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    init(setup: RunSetup, services: AppServices, rules: RunRules, race: RaceHooks? = nil) {
        self.setup = setup
        self.services = services
        self.rules = rules
        self.race = race
        // Racers calibrate in the lobby and go straight to the shared countdown.
        phase = race == nil ? .calibrating : .countdown(3)
        background = services.settings.background
        calibration = TiltCalibration(
            zero: services.settings.calibrationZero ?? .zero,
            sensitivity: services.settings.sensitivity
        )
        usesTouchSteering = !services.motion.isAvailable
        let engine = RunEngine(course: setup.course, weather: setup.weatherSchedule, localSeed: setup.localSeed)
        scene = GameScene(
            engine: engine,
            appearance: services.wallet.equippedSkin.appearance,
            reduceMotion: UIAccessibility.isReduceMotionEnabled
        )
        hud = scene.hudSnapshot
        scene.usesTouchSteering = usesTouchSteering
        scene.input = { [weak self] in self?.currentInput ?? .level }
        scene.onEvents = { [weak self] events in self?.handle(events) }
        scene.onHUD = { [weak self] snapshot in
            self?.hud = snapshot
            self?.race?.onProgress(snapshot.meters, snapshot.eggsLeft)
        }
        scene.onFrame = { [weak self] engine in
            self?.services.haptics.updateDanger(rimDistance: engine.egg.rimDistance)
            self?.updateWeatherSounds(engine.weather)
        }
    }

    /// Raw device tilt for the calibration screen's spirit level, `nil` without motion sensors.
    var rawTilt: SIMD2<Double>? {
        services.motion.tilt
    }

    /// The tilt the egg currently feels.
    var calibratedTilt: SIMD2<Double> {
        services.motion.tilt.map(calibration.apply) ?? .zero
    }

    /// Pausing would stop only this phone's race, so multiplayer runs cannot be paused.
    var allowsPause: Bool {
        race == nil
    }

    private var currentInput: RunEngine.Input {
        RunEngine.Input(tilt: calibratedTilt, sprint: isSprinting)
    }

    // MARK: Lifecycle

    func start() {
        services.motion.start()
        services.haptics.prepare()
        services.sounds.prepare()
        UIApplication.shared.isIdleTimerDisabled = phase.keepsScreenAwake
        // Multiplayer racers calibrated in the lobby; everybody counts down to the same moment.
        if let race {
            startCountdown(until: race.startAt)
        }
    }

    func stop() {
        countdownTask?.cancel()
        endTask?.cancel()
        toastTask?.cancel()
        services.motion.stop()
        services.haptics.shutDown()
        services.sounds.stopLoops()
        scene.mode = .ended
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Stores the current pose as level and starts (or resumes) with a countdown.
    func calibrate() {
        calibrateInPlace()
        startCountdown(until: .now + .seconds(3))
    }

    /// The current pose becomes level immediately (also mid-race in multiplayer, where there is no countdown).
    func calibrateInPlace() {
        if let raw = services.motion.tilt {
            calibration.calibrate(at: raw)
            services.settings.calibrationZero = raw
        }
    }

    func pause() {
        guard allowsPause else { return }
        switch phase {
        case .running, .countdown:
            countdownTask?.cancel()
            isSprinting = false
            phase = .paused
            scene.mode = .paused
            services.haptics.stopDanger()
            services.sounds.stopLoops()
        case .calibrating, .paused, .finished:
            break
        }
    }

    func resume() {
        guard phase == .paused else { return }
        startCountdown(until: .now + .seconds(3))
    }

    func recalibrate() {
        guard phase == .paused else { return }
        phase = .calibrating
        scene.mode = .preview
    }

    /// Shows a short note about another racer.
    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            if Task.isCancelled {
                return
            }
            self?.toast = nil
        }
    }

    /// Counts "3, 2, 1" down to `start`, then runs. Waiting for the clock instead of sleeping one second three times
    /// keeps all phones of a race in step.
    private func startCountdown(until start: ContinuousClock.Instant) {
        countdownTask?.cancel()
        scene.mode = .warmUp
        countdownTask = Task { [weak self] in
            var announced = Int.max
            while true {
                let remaining = (start - .now).seconds
                if remaining <= 0 {
                    break
                }
                let count = Int(remaining.rounded(.up))
                if count < announced, count <= 3 {
                    announced = count
                    self?.phase = .countdown(count)
                    self?.services.sounds.play(.beep)
                }
                try? await Task.sleep(for: .milliseconds(20))
                if Task.isCancelled {
                    return
                }
            }
            self?.services.sounds.play(.go)
            self?.phase = .running
            self?.scene.mode = .running
        }
    }

    // MARK: Events

    private func handle(_ events: [RunEvent]) {
        let haptics = services.haptics
        let sounds = services.sounds
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
            case let .eggDropped(_, eggsLeft):
                race?.onEggDropped(eggsLeft)
                haptics.crack()
                sounds.play(.crack)
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(0.3))
                    self?.services.sounds.play(.splat)
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

    /// Rain and wind loops follow the weather where the runner is.
    private func updateWeatherSounds(_ weather: WeatherSystem) {
        services.sounds.setLoop(.rain, volume: Float(0.5 * weather.mix.rain))
        services.sounds.setLoop(
            .wind,
            volume: Float(0.15 + 0.5 * weather.gustStrength) * (weather.mix.wind > 0 ? 1 : 0)
        )
    }

    private func end() {
        scene.mode = .ended
        isSprinting = false
        services.haptics.stopDanger()
        services.sounds.stopLoops()
        let engine = scene.engine
        let finished = engine.phase == .finished
        // In a race the clock keeps running for everybody, even while this phone was in the background.
        let time = race.map { (ContinuousClock.now - $0.startAt).seconds } ?? engine.elapsed

        var isPersonalBest = false
        if rules.countsAsRecord {
            switch setup.mode {
            case let .timeTrial(distance, weather) where finished:
                isPersonalBest = services.records.recordTime(time, distance: distance, weather: weather)
            case .endless:
                isPersonalBest = services.records.recordEndless(meters: engine.meters)
            case .timeTrial:
                break
            }
            if let score = LeaderboardScore(
                course: setup.course,
                finished: finished,
                time: time,
                meters: engine.meters
            ) {
                services.gameCenter.submit(score)
            }
        }

        var reward: CoinReward?
        if rules.earnsCoins {
            let earned = CoinRewards.reward(for: RewardInput(
                course: setup.course,
                weather: setup.mode.weather,
                finished: finished,
                meters: engine.meters,
                eggsLost: engine.eggsLost,
                isPersonalBest: isPersonalBest
            ))
            services.wallet.earn(earned)
            reward = earned
        }

        let outcome = RunOutcome(
            mode: setup.mode,
            finished: finished,
            time: time,
            meters: engine.meters,
            eggsLost: engine.eggsLost,
            isPersonalBest: isPersonalBest,
            reward: reward
        )
        hud = scene.hudSnapshot
        race?.onFinished(outcome)
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
