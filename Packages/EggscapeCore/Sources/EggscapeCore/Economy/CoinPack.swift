/// A consumable in-app purchase that adds coins to the wallet.
///
/// Prices are deliberately not part of the app: they are set per storefront in App Store Connect, and StoreKit's
/// `Product` reports the localized price. The amounts are sized against the skin prices: the small pack covers most
/// rare skins, the medium one any epic skin, the large one both legendary skins.
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
}
