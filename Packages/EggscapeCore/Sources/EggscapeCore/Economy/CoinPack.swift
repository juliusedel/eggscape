import Foundation

/// A consumable in-app purchase that adds coins to the wallet.
///
/// Prices are deliberately not part of the app: they are set per storefront in App Store Connect, and StoreKit's
/// `Product` reports the localized price. The amounts are sized against the skin prices: the small pack buys any
/// common egg, the medium one any rare egg, the large one any egg but the last, which takes the large pack plus some
/// play.
public struct CoinPack: Hashable, Sendable, Identifiable {
    /// The product identifier in App Store Connect. Stable forever, like a skin id.
    public let productID: String
    public let coins: Int

    public init(productID: String, coins: Int) {
        self.productID = productID
        self.coins = coins
    }

    public var id: String {
        productID
    }

    public static let small = CoinPack(productID: "de.juliusedel.eggscape.coins.small", coins: 600)
    public static let medium = CoinPack(productID: "de.juliusedel.eggscape.coins.medium", coins: 2000)
    public static let large = CoinPack(productID: "de.juliusedel.eggscape.coins.large", coins: 5000)

    /// All packs, in the order the shop lists them.
    public static let all = [small, medium, large]

    /// The identifiers to request with StoreKit's `Product.products(for:)`.
    public static var productIDs: [String] {
        all.map(\.productID)
    }

    /// The pack a StoreKit product or transaction stands for, `nil` for an identifier this version does not sell.
    public static func pack(productID: String) -> CoinPack? {
        all.first { $0.productID == productID }
    }

    /// The pack with the most coins for the money, for the shop's "best offer" badge.
    ///
    /// `prices` maps product ids to the prices StoreKit reports, all in one storefront's currency, so the answer can
    /// differ between storefronts. `nil` unless at least two packs have a price, because a single pack is no deal;
    /// on a tie the bigger pack wins.
    public static func bestValue(prices: [String: Decimal]) -> CoinPack? {
        let offers = all.compactMap { pack -> (pack: CoinPack, price: Decimal)? in
            guard let price = prices[pack.productID], price > 0 else {
                return nil
            }
            return (pack, price)
        }
        guard let first = offers.first, offers.count >= 2 else {
            return nil
        }
        // Coins per unit of money, compared crosswise so no division rounds. `all` goes from small to large, so `>=`
        // hands a tie to the bigger pack.
        return offers.dropFirst().reduce(first) { best, offer in
            Decimal(offer.pack.coins) * best.price >= Decimal(best.pack.coins) * offer.price ? offer : best
        }.pack
    }
}
