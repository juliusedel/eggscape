import AVFoundation
import os

/// The one-shot sound effects, synthesized by scripts/make_sounds.swift.
enum SoundEffect: String, CaseIterable {
    case step
    case crack
    case splat
    case plop
    case beep
    case go
    case finish
    case fail
    case splash
    case thunder
    case coin

    /// Footsteps and splashes can overlap themselves.
    var voices: Int {
        switch self {
        case .step, .splash: 3
        default: 1
        }
    }
}

/// Looping weather ambience.
enum AmbientLoop: String, CaseIterable {
    case rain
    case wind
}

/// Plays sound effects with `AVAudioPlayer`. The audio session is `.ambient`, so the silent switch mutes the game and
/// other apps' music keeps playing.
@MainActor
final class SoundPlayer {
    private let settings: SettingsStore
    private var voices: [SoundEffect: [AVAudioPlayer]] = [:]
    private var loops: [AmbientLoop: AVAudioPlayer] = [:]
    private var isSessionConfigured = false
    private let logger = Logger(subsystem: "de.juliusedel.eggscape", category: "sound")

    init(settings: SettingsStore) {
        self.settings = settings
    }

    /// Follows the "Ton" setting, which can change mid-run from the pause menu.
    var isEnabled: Bool {
        settings.isSoundOn
    }

    /// Loads all effects ahead of a run so the first sound plays without delay.
    func prepare() {
        configureSession()
        for effect in SoundEffect.allCases where voices[effect] == nil {
            voices[effect] = (0 ..< effect.voices).compactMap { _ in makePlayer(named: effect.rawValue) }
        }
    }

    func play(_ effect: SoundEffect, volume: Float = 1) {
        guard isEnabled else { return }
        if voices[effect] == nil {
            prepare()
        }
        guard let pool = voices[effect], let player = pool.first(where: { !$0.isPlaying }) ?? pool.first else { return }
        player.volume = volume
        player.currentTime = 0
        player.play()
    }

    /// Fades a weather loop to `volume` (0 stops it).
    func setLoop(_ loop: AmbientLoop, volume: Float, fade: TimeInterval = 0.6) {
        guard isEnabled else {
            stopLoops()
            return
        }
        if volume <= 0.001 {
            guard let player = loops[loop], player.isPlaying else { return }
            player.setVolume(0, fadeDuration: fade)
            return
        }
        let player: AVAudioPlayer
        if let existing = loops[loop] {
            player = existing
        } else if let created = makePlayer(named: loop.rawValue) {
            created.numberOfLoops = -1
            created.volume = 0
            loops[loop] = created
            player = created
        } else {
            return
        }
        if !player.isPlaying {
            player.play()
        }
        player.setVolume(volume, fadeDuration: fade)
    }

    func stopLoops() {
        for player in loops.values {
            player.stop()
            player.currentTime = 0
        }
    }

    private func configureSession() {
        guard !isSessionConfigured else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            isSessionConfigured = true
        } catch {
            logger.error("Audio session: \(error.localizedDescription)")
        }
    }

    private func makePlayer(named name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf") else {
            logger.error("Missing sound \(name)")
            return nil
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            return player
        } catch {
            logger.error("Sound \(name) failed to load: \(error.localizedDescription)")
            return nil
        }
    }
}
