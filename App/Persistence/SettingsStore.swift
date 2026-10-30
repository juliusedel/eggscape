import EggscapeCore
import Foundation
import Observation

/// What the game shows behind the spoon.
enum BackgroundMode: String, CaseIterable, Identifiable, Sendable {
    /// A white studio surface with soft shadows.
    case white
    /// The live rear camera: the player looks "through" the phone at the ground.
    case camera

    var id: String {
        rawValue
    }
}

/// The player's settings, stored in `UserDefaults`.
@MainActor
@Observable
final class SettingsStore {
    private enum Key {
        static let sound = "settings.sound"
        static let haptics = "settings.haptics"
        static let sensitivity = "settings.sensitivity"
        static let playerName = "settings.playerName"
        static let background = "settings.background"
        static let tutorialSeen = "settings.tutorialSeen"
        static let calibration = "settings.calibration"
        static let all = [sound, haptics, sensitivity, playerName, background, tutorialSeen, calibration]
    }

    static let maxNameLength = 16
    /// The camera for fresh installs and after "Daten zurücksetzen" (owner, 2026-10-29): the see-through phone is the
    /// game's look. Without a camera or camera access a run shows the white surface instead (`RunView`).
    static let defaultBackground = BackgroundMode.camera

    @ObservationIgnored private let defaults: UserDefaults

    var isSoundOn: Bool {
        didSet { defaults.set(isSoundOn, forKey: Key.sound) }
    }

    var isHapticsOn: Bool {
        didSet { defaults.set(isHapticsOn, forKey: Key.haptics) }
    }

    /// Multiplier on the calibrated tilt, 0.7 ... 1.3, on top of the base gain (`GameConfig.tiltGain`): 100 % is the
    /// recommended steering, so stored values keep meaning "this much stronger or weaker than recommended".
    var sensitivity: Double {
        didSet {
            let range = GameConfig.standard.sensitivityRange
            let clamped = min(max(sensitivity, range.lowerBound), range.upperBound)
            if clamped != sensitivity {
                sensitivity = clamped
            }
            defaults.set(sensitivity, forKey: Key.sensitivity)
        }
    }

    /// Shown to other players and in results; never empty when read through `displayName`.
    var playerName: String {
        didSet {
            let trimmed = String(playerName.prefix(Self.maxNameLength))
            if trimmed != playerName {
                playerName = trimmed
            }
            defaults.set(playerName, forKey: Key.playerName)
        }
    }

    /// A background the player chose is stored and kept, also when the default changes.
    var background: BackgroundMode {
        didSet { defaults.set(background.rawValue, forKey: Key.background) }
    }

    var hasSeenTutorial: Bool {
        didSet { defaults.set(hasSeenTutorial, forKey: Key.tutorialSeen) }
    }

    /// The pose the player last calibrated as level (raw tilt in radians), used until the next calibration.
    var calibrationZero: SIMD2<Double>? {
        didSet {
            if let calibrationZero {
                defaults.set([calibrationZero.x, calibrationZero.y], forKey: Key.calibration)
            } else {
                defaults.removeObject(forKey: Key.calibration)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isSoundOn = defaults.object(forKey: Key.sound) as? Bool ?? true
        isHapticsOn = defaults.object(forKey: Key.haptics) as? Bool ?? true
        sensitivity = defaults.object(forKey: Key.sensitivity) as? Double ?? 1
        playerName = defaults.string(forKey: Key.playerName) ?? ""
        background = defaults.string(forKey: Key.background).flatMap(BackgroundMode.init(rawValue:))
            ?? Self.defaultBackground
        hasSeenTutorial = defaults.bool(forKey: Key.tutorialSeen)
        calibrationZero = (defaults.array(forKey: Key.calibration) as? [Double]).flatMap { values in
            values.count == 2 ? SIMD2(values[0], values[1]) : nil
        }
    }

    /// Stores a name the player typed, e.g. in the tutorial's last step, without the spaces around it. A blank name is
    /// stored empty, so `displayName` falls back to the generic one.
    func savePlayerName(_ typed: String) {
        playerName = typed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The name to show, falling back to a generic one.
    var displayName: String {
        let trimmed = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Spieler") : trimmed
    }

    /// Restores every setting to its default.
    func reset() {
        Key.all.forEach(defaults.removeObject(forKey:))
        isSoundOn = true
        isHapticsOn = true
        sensitivity = 1
        playerName = ""
        background = Self.defaultBackground
        hasSeenTutorial = false
        calibrationZero = nil
    }
}
