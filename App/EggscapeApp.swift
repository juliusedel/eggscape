import SwiftUI

@main
struct EggscapeApp: App {
    @State private var services = EggscapeApp.makeServices()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services)
                .task {
                    services.store.start()
                    // UI tests, staged screenshots and a simulated first launch never touch GameKit, so their records
                    // never reach a leaderboard.
                    if !LaunchOptions.current.usesEphemeralData {
                        services.gameCenter.authenticate()
                    }
                }
        }
    }

    private static func makeServices() -> AppServices {
        let options = LaunchOptions.current
        guard options.usesEphemeralData else { return AppServices() }
        let defaults = LaunchOptions.ephemeralDefaults()
        let services = AppServices(
            settings: SettingsStore(defaults: defaults),
            records: RecordsStore(defaults: defaults),
            wallet: WalletStore(defaults: defaults)
        )
        // A new install is left as it is.
        guard !options.simulatesFirstLaunch else { return services }
        services.settings.hasSeenTutorial = true
        // The white studio surface: the Simulator has no camera, and the camera prompt would stop a UI test.
        services.settings.background = .white
        return services
    }
}
