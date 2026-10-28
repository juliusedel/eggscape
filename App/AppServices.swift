import Observation

/// Long-lived objects shared by all screens.
@MainActor
@Observable
final class AppServices {
    /// One motion manager for the whole app, as Apple recommends.
    let motion = MotionInput()
    let settings: SettingsStore
    let records: RecordsStore
    let camera = CameraFeed()
    let haptics: Haptics
    let sounds: SoundPlayer
    let navigation = AppNavigation()
    @ObservationIgnored private(set) lazy var launcher = GameLauncher(services: self)

    init(settings: SettingsStore = SettingsStore(), records: RecordsStore = RecordsStore()) {
        self.settings = settings
        self.records = records
        haptics = Haptics(settings: settings)
        sounds = SoundPlayer(settings: settings)
    }

    /// "Daten zurücksetzen": settings, records and progress.
    func resetAllData() {
        settings.reset()
        records.reset()
    }
}

/// Which tab is selected and which app-wide sheets are open.
@MainActor
@Observable
final class AppNavigation {
    enum Tab: Hashable {
        case singleplayer
        case multiplayer
        case leaderboard
        case shop
    }

    var tab = Tab.singleplayer
    var showsSettings = false
    var showsTutorial = false
}
