import CoreHaptics
import os
import UIKit

/// Vibration feedback: a light tick per footstep, a continuous buzz that grows as the egg nears the rim (the most
/// important feedback channel), a sharp crack and a lightning rumble. Uses CoreHaptics and falls back to UIKit
/// feedback generators on hardware without a haptic engine.
@MainActor
final class Haptics {
    private let settings: SettingsStore
    private let supportsEngine = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var engine: CHHapticEngine?
    /// `false` until the engine started and again once it stopped, e.g. because the app went to the background.
    /// Nothing is played meanwhile: `start()` blocks, so it is never tried per frame or footstep.
    private var isEngineRunning = false
    private var dangerPlayer: CHHapticAdvancedPatternPlayer?
    private var dangerLevel = 0.0
    /// The runs that use the engine; on "Nochmal" the new one prepares before the old one shuts down.
    private var owners = Leases()
    private lazy var lightImpact = UIImpactFeedbackGenerator(style: .light)
    private lazy var heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private lazy var notification = UINotificationFeedbackGenerator()
    private let logger = Logger(subsystem: "de.juliusedel.eggscape", category: "haptics")

    init(settings: SettingsStore) {
        self.settings = settings
    }

    /// Follows the "Vibration" setting.
    var isEnabled: Bool {
        settings.isHapticsOn
    }

    /// Starts the haptic engine ahead of a run so the first footstep is not delayed. It keeps running until the last
    /// owner has called `shutDown(for:)`.
    func prepare(for owner: AnyObject) {
        owners.acquire(owner)
        startEngine()
    }

    /// The app is active again. The system stops the engine in the background and nothing would start it again
    /// during the run (races never even pause), so it is restarted here for the runs that still need it.
    func resume() {
        guard owners.isHeld else { return }
        startEngine()
    }

    func shutDown(for owner: AnyObject) {
        guard owners.release(owner) else { return }
        stopDanger()
        engine?.stop()
        isEngineRunning = false
    }

    // MARK: Events

    func footstep(sprinting: Bool) {
        transient(intensity: sprinting ? 0.42 : 0.28, sharpness: 0.25) {
            lightImpact.impactOccurred(intensity: sprinting ? 0.6 : 0.4)
        }
    }

    func splash() {
        transient(intensity: 0.7, sharpness: 0.45) {
            heavyImpact.impactOccurred(intensity: 0.7)
        }
    }

    /// The egg breaks: a hard snap followed by a short crunch.
    func crack() {
        stopDanger()
        play(
            events: [
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        .init(parameterID: .hapticIntensity, value: 1),
                        .init(parameterID: .hapticSharpness, value: 1),
                    ],
                    relativeTime: 0
                ),
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        .init(parameterID: .hapticIntensity, value: 0.7),
                        .init(parameterID: .hapticSharpness, value: 0.8),
                    ],
                    relativeTime: 0.05
                ),
                CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        .init(parameterID: .hapticIntensity, value: 0.5),
                        .init(parameterID: .hapticSharpness, value: 0.6),
                    ],
                    relativeTime: 0.08,
                    duration: 0.15
                ),
            ]
        ) {
            notification.notificationOccurred(.error)
        }
    }

    /// Lightning strikes: a deep rumble that fades out.
    func thunder() {
        play(
            events: [
                CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        .init(parameterID: .hapticIntensity, value: 1),
                        .init(parameterID: .hapticSharpness, value: 0.05),
                    ],
                    relativeTime: 0,
                    duration: 0.7
                ),
            ],
            curves: [
                CHHapticParameterCurve(
                    parameterID: .hapticIntensityControl,
                    controlPoints: [.init(relativeTime: 0, value: 1), .init(relativeTime: 0.7, value: 0)],
                    relativeTime: 0
                ),
            ]
        ) {
            heavyImpact.impactOccurred(intensity: 1)
        }
    }

    /// How close the egg is to the rim (elliptical distance 0 ... 1). The buzz starts at about half way and grows
    /// steeply towards the rim.
    func updateDanger(rimDistance: Double) {
        guard isEnabled else {
            stopDanger()
            return
        }
        guard supportsEngine, isEngineRunning, let engine else { return }
        let level = smoothstep(0.5, 1, rimDistance)
        guard level > 0.02 else {
            stopDanger()
            return
        }
        // Only talk to the engine when the level changed noticeably; this runs every frame.
        guard abs(level - dangerLevel) > 0.03 || dangerPlayer == nil else { return }
        dangerLevel = level
        do {
            if dangerPlayer == nil {
                let event = CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        .init(parameterID: .hapticIntensity, value: 1),
                        .init(parameterID: .hapticSharpness, value: 0.3),
                    ],
                    relativeTime: 0,
                    duration: 30
                )
                let player = try engine.makeAdvancedPlayer(with: CHHapticPattern(events: [event], parameters: []))
                player.loopEnabled = true
                try player.start(atTime: CHHapticTimeImmediate)
                dangerPlayer = player
            }
            try dangerPlayer?.sendParameters(
                [
                    CHHapticDynamicParameter(
                        parameterID: .hapticIntensityControl,
                        value: Float(level),
                        relativeTime: 0
                    ),
                    CHHapticDynamicParameter(
                        parameterID: .hapticSharpnessControl,
                        value: Float(level * 0.5),
                        relativeTime: 0
                    ),
                ],
                atTime: CHHapticTimeImmediate
            )
        } catch {
            // The engine is not really running; wait for it to be started again instead of rebuilding every frame.
            logger.error("Danger haptic failed: \(error.localizedDescription)")
            dangerPlayer = nil
            isEngineRunning = false
        }
    }

    func stopDanger() {
        try? dangerPlayer?.stop(atTime: CHHapticTimeImmediate)
        dangerPlayer = nil
        dangerLevel = 0
    }

    // MARK: Plumbing

    private func startEngine() {
        guard isEnabled else { return }
        guard supportsEngine else {
            lightImpact.prepare()
            heavyImpact.prepare()
            return
        }
        if engine == nil {
            makeEngine()
        }
        guard let engine else { return }
        do {
            try engine.start()
            isEngineRunning = true
        } catch {
            isEngineRunning = false
            logger.error("Haptic engine did not start: \(error.localizedDescription)")
        }
    }

    private func makeEngine() {
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = false
            // CoreHaptics calls these on its own queue; hop back to the main actor.
            engine.resetHandler = { @Sendable [weak self] in
                Task { @MainActor in self?.restartAfterReset() }
            }
            engine.stoppedHandler = { @Sendable [weak self] _ in
                Task { @MainActor in self?.engineStopped() }
            }
            self.engine = engine
        } catch {
            logger.error("No haptic engine: \(error.localizedDescription)")
        }
    }

    private func restartAfterReset() {
        dangerPlayer = nil
        dangerLevel = 0
        isEngineRunning = false
        resume()
    }

    /// The system stopped the engine. That usually happens on the way into the background, and `resume()` follows
    /// once the app is active again; a stop while the app stays active, or a notice that arrives late, is answered
    /// right away.
    private func engineStopped() {
        dangerPlayer = nil
        dangerLevel = 0
        isEngineRunning = false
        if UIApplication.shared.applicationState == .active {
            resume()
        }
    }

    private func transient(intensity: Float, sharpness: Float, fallback: () -> Void) {
        play(
            events: [
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        .init(parameterID: .hapticIntensity, value: intensity),
                        .init(parameterID: .hapticSharpness, value: sharpness),
                    ],
                    relativeTime: 0
                ),
            ],
            fallback: fallback
        )
    }

    private func play(events: [CHHapticEvent], curves: [CHHapticParameterCurve] = [], fallback: () -> Void) {
        guard isEnabled else { return }
        guard supportsEngine, let engine else {
            fallback()
            return
        }
        guard isEngineRunning else { return }
        do {
            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            logger.error("Haptic pattern failed: \(error.localizedDescription)")
        }
    }

    private func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
