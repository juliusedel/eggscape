import EggscapeCore
import Foundation

/// The staged scenes for App Store screenshots: `--screenshot-mode <scene>` (see fastlane/Snapfile and
/// EggscapeUITests/ScreenshotTests.swift). Data is ephemeral and seeds are fixed, so every capture looks the same.
enum ScreenshotScene: String, CaseIterable {
    case start
    case calibration
    case sunnyRun = "run-sunny"
    case rainRun = "run-rain"
    case stormRun = "run-storm"
    case lobby
    case results
    case shop
}

@MainActor
enum ScreenshotStage {
    static func prepare(_ scene: ScreenshotScene, services: AppServices) {
        services.settings.isSoundOn = false
        services.settings.isHapticsOn = false
        services.settings.playerName = "Sam"
        // A believable history: a few bests, some coins, some eggs.
        services.records.recordTime(48.7, distance: .short, weather: .off)
        services.records.recordTime(101.3, distance: .medium, weather: .off)
        services.records.recordEndless(meters: 412)
        services.wallet.earn(CoinReward(lines: [CoinReward.Line(kind: .distance, coins: 2140)]))
        for id in ["sky-blue", "polka-dots", "pearl-white"] {
            if let skin = SkinCatalog.skin(id: id) {
                try? services.wallet.purchase(skin)
            }
        }
        let brown = SkinCatalog.skin(id: "farm-brown") ?? SkinCatalog.defaultSkin
        try? services.wallet.equip(scene == .shop ? SkinCatalog.skin(id: "polka-dots") ?? brown : brown)

        switch scene {
        case .start:
            services.navigation.tab = .singleplayer
        case .shop:
            services.navigation.tab = .shop
        case .lobby:
            services.navigation.tab = .multiplayer
            services.navigation.showsScreenshotLobby = true
        case .calibration:
            services.launcher.start(.timeTrial(.short, .off))
        case .sunnyRun:
            stageRun(.timeTrial(.medium, .off), skipping: 21, egg: SIMD2(0.16, 0.1), services: services)
        case .rainRun:
            stageRun(.timeTrial(.medium, .fixed(.rain)), skipping: 34, egg: SIMD2(-0.14, 0.18), services: services)
        case .stormRun:
            stageRun(.timeTrial(.long, .fixed(.storm)), skipping: 47, egg: SIMD2(0.22, -0.08), services: services)
        case .results:
            stageRun(.timeTrial(.short, .off), skipping: 60, egg: SIMD2(0.05, 0.05), services: services)
        }
    }

    /// Starts a run and, once its screen is up, jumps into it.
    private static func stageRun(
        _ mode: RunMode,
        skipping seconds: Double,
        egg: SIMD2<Double>,
        services: AppServices
    ) {
        services.launcher.start(mode)
        Task {
            try? await Task.sleep(for: .seconds(1))
            if case let .single(flow) = services.launcher.flow {
                flow.session.stageForScreenshot(skipping: seconds, egg: egg)
            }
        }
    }
}
