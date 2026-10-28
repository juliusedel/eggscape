import EggscapeCore
import Foundation
import Observation

/// Coins, owned egg skins and the equipped skin, persisted as JSON in `UserDefaults`.
@MainActor
@Observable
final class WalletStore {
    private static let key = "wallet.v1"

    @ObservationIgnored private let defaults: UserDefaults
    private(set) var wallet: Wallet

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), let stored = try? JSONDecoder().decode(Wallet.self, from: data) {
            wallet = stored
        } else {
            wallet = Wallet()
        }
    }

    var coins: Int {
        wallet.coins
    }

    var equippedSkin: EggSkin {
        wallet.equippedSkin
    }

    func owns(_ skin: EggSkin) -> Bool {
        wallet.owns(skinID: skin.id)
    }

    func purchase(_ skin: EggSkin) throws(WalletError) {
        try wallet.purchase(skin: skin)
        save()
    }

    func equip(_ skin: EggSkin) throws(WalletError) {
        try wallet.equip(skinID: skin.id)
        save()
    }

    /// Credits the coins a finished run earned.
    func earn(_ reward: CoinReward) {
        guard reward.total > 0 else { return }
        wallet.credit(coins: reward.total)
        save()
    }

    /// Credits a coin pack bought with StoreKit, at most once per transaction.
    func creditPurchase(transactionID: UInt64, productID: String) {
        guard let pack = CoinPack.pack(productID: productID) else { return }
        if wallet.creditPurchase(transactionID: transactionID, coins: pack.coins) {
            save()
        }
    }

    /// "Daten zurücksetzen".
    func reset() {
        defaults.removeObject(forKey: Self.key)
        wallet = Wallet()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(wallet) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
