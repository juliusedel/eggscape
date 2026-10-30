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
        // A believable history: a few bests, some coins, some eggs. The bests needed a little sprinting (15 m take
        // 5.2 s at running speed, 50 m 16.9 s), so the staged results run, which does not sprint, is no new best. The
        // brown egg, the most realistic one, is unlocked like any other; the shop's first rows then mix unlocked eggs
        // with locked ones (745 coins left).
        services.records.recordTime(4.87, distance: .short, weather: .off)
        services.records.recordTime(15.9, distance: .medium, weather: .off)
        services.records.recordEndless(meters: 412)
        services.wallet.earn(CoinReward(lines: [CoinReward.Line(kind: .distance, coins: 1500)]))
        for id in ["farm-brown", "sky-blue", "rose", "polka-dots"] {
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
            services.navigation.shopPage = .eggs
        case .lobby:
            services.navigation.tab = .multiplayer
            services.navigation.showsScreenshotLobby = true
        case .calibration:
            services.launcher.start(.timeTrial(.short, .off))
        // The capture follows a few seconds after the jump, well before the finish (16.9 s over 50 m, 33.6 s over
        // 100 m). The storm is captured between the lightning strikes at 12.9 and 23.1 s of the fixed seed, so no
        // flash washes it out; the results run jumps past its finish.
        case .sunnyRun:
            stageRun(.timeTrial(.medium, .off), skipping: 4, egg: SIMD2(0.16, 0.1), services: services)
        case .rainRun:
            stageRun(.timeTrial(.medium, .fixed(.rain)), skipping: 7, egg: SIMD2(-0.14, 0.18), services: services)
        case .stormRun:
            stageRun(.timeTrial(.long, .fixed(.storm)), skipping: 14, egg: SIMD2(0.22, -0.08), services: services)
        case .results:
            stageRun(.timeTrial(.short, .off), skipping: 10, egg: SIMD2(0.05, 0.05), services: services)
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
