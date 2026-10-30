/// An egg skin the shop sells: how the egg looks, what it costs and how rare it is.
///
/// Skins are bought with coins (see `Wallet`). Display names are not part of the skin: the app looks them up by `id`
/// and localizes them.
public struct EggSkin: Codable, Hashable, Sendable, Identifiable {
    /// How rare a skin is. The tier sets the price band and the badge the shop shows.
    public enum Tier: String, CaseIterable, Codable, Hashable, Sendable, Comparable {
        case common
        case rare
        case epic
        case legendary

        /// The coin prices skins of this tier sell for; the free starter skin is the only exception.
        ///
        /// The bands cut the catalog's price ladder (see `SkinCatalog`) into tiers. A clean short run in calm weather
        /// pays 28 coins (see `CoinRewards`), so a common skin costs two to fifteen of them, a rare one dozens, an
        /// epic one around a hundred and a legendary one about two hundred, or a coin pack.
        public var priceRange: ClosedRange<Int> {
            switch self {
            case .common: 50 ... 400
            case .rare: 450 ... 2000
            case .epic: 2200 ... 4000
            case .legendary: 4500 ... 7500
            }
        }

        public static func < (lhs: Tier, rhs: Tier) -> Bool {
            lhs.rank < rhs.rank
        }

        /// Spelled out because enums with raw values get no synthesized `Comparable`.
        private var rank: Int {
            switch self {
            case .common: 0
            case .rare: 1
            case .epic: 2
            case .legendary: 3
            }
        }
    }

    /// Stable forever, e.g. `"classic-white"`: wallets store it, so changing it would take the skin away from
    /// everyone who owns it.
    public let id: String
    public let appearance: EggAppearance
    /// Price in coins, 0 for the free starter skin.
    public let price: Int
    public let tier: Tier

    public init(id: String, appearance: EggAppearance, price: Int, tier: Tier) {
        self.id = id
        self.appearance = appearance
        self.price = price
        self.tier = tier
    }

    /// Free skins belong to every player from the start, so they are never bought.
    public var isFree: Bool {
        price == 0
    }
}
