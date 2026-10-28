/// Why the wallet refused a purchase or a change of skin.
public enum WalletError: Error, Hashable, Sendable {
    /// The skin is not in `SkinCatalog`, e.g. one from a newer version of the app.
    case unknownSkin
    /// The skin is owned already; free skins always are.
    case alreadyOwned
    /// The skin costs more than the balance; `missing` is the difference, for a "120 coins missing" hint.
    case insufficientCoins(missing: Int)
    /// Only owned skins can be equipped.
    case notOwned
}

/// The player's coins and egg skins, as a plain value.
///
/// The app persists it (it is `Codable`) and writes it back after every change. Every mutation keeps three
/// invariants: the balance is never negative, the free skins are owned, and the equipped skin is owned.
public struct Wallet: Hashable, Sendable {
    public private(set) var coins: Int
    public private(set) var ownedSkinIDs: Set<String>
    public private(set) var equippedSkinID: String
    /// StoreKit transaction ids (`Transaction.id`) whose coins were credited, so a transaction that StoreKit delivers
    /// again (after a crash, or on another launch before it was finished) never pays twice.
    public private(set) var processedTransactionIDs: Set<UInt64>

    /// A new player's wallet: no coins, the free skins, and the default skin equipped.
    public init() {
        coins = 0
        ownedSkinIDs = SkinCatalog.freeSkinIDs
        equippedSkinID = SkinCatalog.defaultSkinID
        processedTransactionIDs = []
    }

    /// The equipped skin, or the default skin if the catalog lacks it (a wallet from a newer app version).
    public var equippedSkin: EggSkin {
        SkinCatalog.skin(id: equippedSkinID) ?? SkinCatalog.defaultSkin
    }

    public func owns(skinID: String) -> Bool {
        ownedSkinIDs.contains(skinID)
    }

    /// Adds coins earned by playing, e.g. `CoinReward.total`. `coins` must not be negative.
    public mutating func credit(coins amount: Int) {
        precondition(amount >= 0, "a credit cannot take coins away")
        // Saturating, so even a tampered balance near `Int.max` cannot trap.
        let (sum, overflow) = coins.addingReportingOverflow(amount)
        coins = overflow ? Int.max : sum
    }

    /// Buys `skin` with coins at the catalog's price. It does not equip the skin: the shop decides about that.
    public mutating func purchase(skin: EggSkin) throws(WalletError) {
        // The catalog's entry, not the argument, sets the price, so a stale or hand-made `EggSkin` cannot change it.
        guard let listed = SkinCatalog.skin(id: skin.id) else {
            throw .unknownSkin
        }
        guard !owns(skinID: listed.id) else {
            throw .alreadyOwned
        }
        guard coins >= listed.price else {
            throw .insufficientCoins(missing: listed.price - coins)
        }
        coins -= listed.price
        ownedSkinIDs.insert(listed.id)
    }

    /// Puts on an owned skin.
    public mutating func equip(skinID: String) throws(WalletError) {
        guard SkinCatalog.skin(id: skinID) != nil else {
            throw .unknownSkin
        }
        guard owns(skinID: skinID) else {
            throw .notOwned
        }
        equippedSkinID = skinID
    }

    /// Credits the coins of a coin pack purchase exactly once per StoreKit transaction.
    ///
    /// Returns `false` without changing anything if the transaction was credited before; the app can finish it right
    /// away. After `true`, the app should persist the wallet first and only then call `Transaction.finish()`:
    /// finishing first would lose the coins if the app quit in between, while persisting first at worst makes StoreKit
    /// deliver the transaction again, which this then ignores.
    @discardableResult
    public mutating func creditPurchase(transactionID: UInt64, coins amount: Int) -> Bool {
        guard processedTransactionIDs.insert(transactionID).inserted else {
            return false
        }
        credit(coins: amount)
        return true
    }
}

extension Wallet: Codable {
    private enum CodingKeys: String, CodingKey {
        case coins
        case ownedSkinIDs
        case equippedSkinID
        case processedTransactionIDs
    }

    /// Lenient on purpose: the app falls back to a new wallet when decoding fails, which would wipe a player's coins
    /// and skins. So missing fields get their defaults, the balance is clamped at 0, free skins added in a later
    /// version become owned, and an equipped skin that is not owned is replaced by the default.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let owned = try (container.decodeIfPresent(Set<String>.self, forKey: .ownedSkinIDs) ?? [])
            .union(SkinCatalog.freeSkinIDs)
        let equipped = try container.decodeIfPresent(String.self, forKey: .equippedSkinID)
        coins = try max(container.decodeIfPresent(Int.self, forKey: .coins) ?? 0, 0)
        ownedSkinIDs = owned
        if let equipped, owned.contains(equipped) {
            equippedSkinID = equipped
        } else {
            equippedSkinID = SkinCatalog.defaultSkinID
        }
        processedTransactionIDs = try container.decodeIfPresent(Set<UInt64>.self, forKey: .processedTransactionIDs)
            ?? []
    }

    /// Writes the sets as sorted arrays, because a set's order differs from launch to launch, which would make equal
    /// wallets encode differently.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coins, forKey: .coins)
        try container.encode(ownedSkinIDs.sorted(), forKey: .ownedSkinIDs)
        try container.encode(equippedSkinID, forKey: .equippedSkinID)
        try container.encode(processedTransactionIDs.sorted(), forKey: .processedTransactionIDs)
    }
}
