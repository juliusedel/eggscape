import EggscapeCore
import Observation

/// Long-lived objects shared by all screens.
@MainActor
@Observable
final class AppServices {
    /// One motion manager for the whole app, as Apple recommends.
    let motion = MotionInput()
    let settings: SettingsStore
    let records: RecordsStore
    let wallet: WalletStore
    let store: StoreService
    let gameCenter = GameCenterService()
    let camera = CameraFeed()
    let haptics: Haptics
    let sounds: SoundPlayer
    let navigation = AppNavigation()
    @ObservationIgnored private(set) lazy var launcher = GameLauncher(services: self)

    init(
        settings: SettingsStore = SettingsStore(),
        records: RecordsStore = RecordsStore(),
        wallet: WalletStore = WalletStore()
    ) {
        self.settings = settings
        self.records = records
        self.wallet = wallet
        store = StoreService(productIDs: CoinPack.all.map(\.productID)) { transactionID, productID in
            wallet.creditPurchase(transactionID: transactionID, productID: productID)
        }
        haptics = Haptics(settings: settings)
        sounds = SoundPlayer(settings: settings)
        gameCenter.onSignIn = { [weak records, weak gameCenter] in
            // Bests set before signing in still reach the leaderboards.
            guard let records, let gameCenter else { return }
            for score in records.leaderboardScores {
                gameCenter.submit(score)
            }
        }
    }

    /// "Daten zurücksetzen": settings, records, coins and skins on this device.
    func resetAllData() {
        settings.reset()
        records.reset()
        wallet.reset()
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

    /// The two pages of the shop tab.
    enum ShopPage: Hashable {
        /// Egg skins, unlocked with coins.
        case eggs
        /// Coin packs for real money.
        case coins
    }

    var tab = Tab.singleplayer
    /// Kept next to the tab so the coin shop can be opened directly, e.g. when an egg costs more than the balance.
    var shopPage = ShopPage.eggs
    var showsSettings = false
    var showsTutorial = false
    /// Only for the staged App Store screenshot of a nearby lobby.
    var showsScreenshotLobby = false

    /// The shop's coin packs.
    func showCoinShop() {
        tab = .shop
        shopPage = .coins
    }
}
