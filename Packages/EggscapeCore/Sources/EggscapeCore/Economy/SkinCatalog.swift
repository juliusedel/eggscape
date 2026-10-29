/// Every egg skin the shop sells.
///
/// Once a version with a skin has shipped, its `id` and its `seed` must never change: wallets store the id, and the
/// seed pins the natural irregularities, so changing either would take the skin away from its owners or change how
/// the egg they bought looks. Prices and the display order may change.
///
/// Only the classic white egg is free. The prices climb along the display order like a ladder: the brown egg costs
/// what a new player's first clean medium run pays, personal best included (see `CoinRewards`), and every egg after
/// it about 1.3 times the one before, rounded to a friendly number, up to 6,000 coins for the last one. So the first
/// eggs take one to a few runs each, while each of the last ones is a goal of many runs or a coin pack.
///
/// The colors are albedos for the photo-realistic renderer (`EggscapeArt`), which adds the key light from the top
/// right, the shadows and the finish. Dyed colors are a little muted, like real egg dye on a white shell, because
/// fully saturated colors read as plastic. The German names in the comments are the suggested shop names; the app
/// looks names up by id and localizes them.
public enum SkinCatalog {
    private typealias Color = EggAppearance.Color

    /// All skins in display order, which is also price order: natural eggs, dyed eggs, patterns, then special finishes.
    public static let all: [EggSkin] = [
        classicWhite, farmBrown, quail,
        skyBlue, lemonYellow, rose, mint, orange, lilac,
        polkaDots, navyStripes, zigzag, dipDye, confetti, marble,
        starryNight, pearlWhite, silverMetallic, goldMetallic, rainbowStripes,
    ]

    /// The skin a new player wears, and the fallback when an equipped skin is missing from the catalog.
    public static var defaultSkin: EggSkin {
        classicWhite
    }

    public static let defaultSkinID = classicWhite.id

    /// The skins every player owns from the start: only the classic white egg.
    public static let freeSkinIDs = Set(all.filter(\.isFree).map(\.id))

    /// The skin with `id`, or `nil` for an id this version does not know.
    public static func skin(id: String) -> EggSkin? {
        skinsByID[id]
    }

    /// Duplicate ids keep the first skin instead of trapping; the catalog tests reject duplicates.
    private static let skinsByID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    // MARK: Natural eggs

    /// "Klassisch Weiß": a natural white hen's egg, chalky and matte with a faint warm tint. Free, and the default.
    public static let classicWhite = EggSkin(
        id: "classic-white",
        appearance: EggAppearance(base: Color(hex: 0xF2EDE4), finish: .matte, seed: 0x1864_ABD3_D0E4_0B42),
        price: 0,
        tier: .common
    )

    /// "Landei": a natural brown hen's egg like in a photo, matte, with fine darker brown speckles. The first egg to
    /// unlock: it costs what a new player's first clean medium run pays, or two clean short runs.
    public static let farmBrown = EggSkin(
        id: "farm-brown",
        appearance: EggAppearance(
            base: Color(hex: 0xC8804E),
            pattern: .speckles(color: Color(hex: 0x7A4426), density: 0.35, size: 0.15),
            finish: .matte,
            seed: 0x1C1B_04FB_02B2_BC5F
        ),
        price: 55,
        tier: .common
    )

    /// "Wachtelei": cream like a quail egg, with large dark brown blotches.
    public static let quail = EggSkin(
        id: "quail",
        appearance: EggAppearance(
            base: Color(hex: 0xE6DBC3),
            pattern: .speckles(color: Color(hex: 0x3A2A1E), density: 0.55, size: 0.8),
            finish: .matte,
            seed: 0xC782_8900_DE8D_F473
        ),
        price: 70,
        tier: .common
    )

    // MARK: Dyed eggs

    /// "Himmelblau": dyed sky blue with a soft satin sheen.
    public static let skyBlue = dyed("sky-blue", Color(hex: 0x84C3E6), price: 90, seed: 0xDF79_1C7A_27AA_6200)

    /// "Zitronengelb": dyed lemon yellow.
    public static let lemonYellow = dyed(
        "lemon-yellow",
        Color(hex: 0xF2D54B),
        price: 120,
        seed: 0x6833_E16C_0625_998E
    )

    /// "Rosé": dyed rose pink.
    public static let rose = dyed("rose", Color(hex: 0xE995AE), price: 160, seed: 0xA62B_C3DE_072B_A3C0)

    /// "Minze": dyed mint green.
    public static let mint = dyed("mint", Color(hex: 0xA3D9C1), price: 200, seed: 0xAAB0_2DED_AF74_0502)

    /// "Orange": dyed orange.
    public static let orange = dyed("orange", Color(hex: 0xEF9447), price: 260, seed: 0x85AA_6824_4C7C_F7BB)

    /// "Flieder": dyed lilac.
    public static let lilac = dyed("lilac", Color(hex: 0xB9A3D6), price: 350, seed: 0xC040_51A0_5376_23A6)

    // MARK: Patterns

    /// "Tupfen": cherry red with painted cream polka dots.
    public static let polkaDots = EggSkin(
        id: "polka-dots",
        appearance: EggAppearance(
            base: Color(hex: 0xD84A4A),
            pattern: .dots(color: Color(hex: 0xF6F1E8), size: 0.3),
            finish: .satin,
            seed: 0xD42A_E514_F195_108B
        ),
        price: 450,
        tier: .rare
    )

    /// "Ringel": navy and cream bands, like a Breton shirt.
    public static let navyStripes = EggSkin(
        id: "navy-stripes",
        appearance: EggAppearance(
            base: Color(hex: 0xF6F1E8),
            pattern: .stripes(colors: [Color(hex: 0x24406E), Color(hex: 0xF6F1E8)]),
            finish: .satin,
            seed: 0x3BFF_197D_7BDF_8A83
        ),
        price: 600,
        tier: .rare
    )

    /// "Zickzack": teal with a sunflower yellow zigzag band.
    public static let zigzag = EggSkin(
        id: "zigzag",
        appearance: EggAppearance(
            base: Color(hex: 0x3AA19B),
            pattern: .zigzag(color: Color(hex: 0xF4C542)),
            finish: .satin,
            seed: 0x24D5_C4D5_6188_4B15
        ),
        price: 750,
        tier: .rare
    )

    /// "Farbbad": a natural white egg with its round half dipped in coral dye.
    public static let dipDye = EggSkin(
        id: "dip-dye",
        appearance: EggAppearance(
            base: Color(hex: 0xF2EDE4),
            pattern: .dipDye(color: Color(hex: 0xE9785C)),
            finish: .satin,
            seed: 0xF21B_6999_8BE0_1EBD
        ),
        price: 1000,
        tier: .rare
    )

    /// "Konfetti": cream with small flecks in five party colors.
    public static let confetti = EggSkin(
        id: "confetti",
        appearance: EggAppearance(
            base: Color(hex: 0xF6F1E8),
            pattern: .confetti(colors: [
                Color(hex: 0xE5484D), // red
                Color(hex: 0xF5C02E), // yellow
                Color(hex: 0x3A9AD9), // blue
                Color(hex: 0x4DB36A), // green
                Color(hex: 0x9B62C4), // purple
            ]),
            finish: .satin,
            seed: 0x2AAD_6F8E_B22D_3D54
        ),
        price: 1300,
        tier: .rare
    )

    /// "Marmor": polished white marble with blue-grey veins, glossy like real stone.
    public static let marble = EggSkin(
        id: "marble",
        appearance: EggAppearance(
            base: Color(hex: 0xEEEBE6),
            pattern: .marble(color: Color(hex: 0x7C8794)),
            finish: .glossy,
            seed: 0xC231_2970_CC3D_544D
        ),
        price: 1700,
        tier: .rare
    )

    /// "Sternennacht": deep navy with small pale gold stars.
    public static let starryNight = EggSkin(
        id: "starry-night",
        appearance: EggAppearance(
            base: Color(hex: 0x1A2348),
            pattern: .stars(color: Color(hex: 0xF4DE93)),
            finish: .satin,
            seed: 0xADB8_F6BA_5007_48BC
        ),
        price: 2200,
        tier: .epic
    )

    // MARK: Special finishes

    /// "Perlmutt": white with an iridescent mother-of-pearl shimmer.
    public static let pearlWhite = EggSkin(
        id: "pearl-white",
        appearance: EggAppearance(base: Color(hex: 0xF1EDEA), finish: .pearl, seed: 0x6193_1E61_B295_0968),
        price: 2800,
        tier: .epic
    )

    /// "Silber": polished silver.
    public static let silverMetallic = EggSkin(
        id: "silver-metallic",
        appearance: EggAppearance(base: Color(hex: 0xC5C9CF), finish: .metallic, seed: 0x7E6F_CECB_825D_FAC0),
        price: 3600,
        tier: .epic
    )

    /// "Gold": polished gold, the egg every player wants.
    public static let goldMetallic = EggSkin(
        id: "gold-metallic",
        appearance: EggAppearance(base: Color(hex: 0xD8B04C), finish: .metallic, seed: 0x24BC_B617_E7BD_7D5D),
        price: 4800,
        tier: .legendary
    )

    /// "Regenbogen": glossy lacquered bands in the six rainbow colors, red at the pointy end.
    public static let rainbowStripes = EggSkin(
        id: "rainbow-stripes",
        appearance: EggAppearance(
            base: Color(hex: 0xE53E3E),
            pattern: .stripes(colors: [
                Color(hex: 0xE53E3E), // red
                Color(hex: 0xF28C28), // orange
                Color(hex: 0xF5D33F), // yellow
                Color(hex: 0x47A84F), // green
                Color(hex: 0x2F7FD8), // blue
                Color(hex: 0x8B4FC0), // violet
            ]),
            finish: .glossy,
            seed: 0xC96F_339D_8F78_E63E
        ),
        price: 6000,
        tier: .legendary
    )

    /// A plain egg in one dye color. Dyed solids are all common skins with a satin finish.
    private static func dyed(_ id: String, _ color: Color, price: Int, seed: UInt64) -> EggSkin {
        EggSkin(id: id, appearance: EggAppearance(base: color, finish: .satin, seed: seed), price: price, tier: .common)
    }
}
