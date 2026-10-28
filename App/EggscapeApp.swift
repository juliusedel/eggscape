import SwiftUI

@main
struct EggscapeApp: App {
    @State private var services = EggscapeApp.makeServices()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services)
                .task { services.store.start() }
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
        services.settings.hasSeenTutorial = true
        return services
    }
}
