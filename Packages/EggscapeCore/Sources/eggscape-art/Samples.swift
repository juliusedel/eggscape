import EggscapeCore

/// The appearances shown on the preview sheets: natural shells, dyes, every pattern and every finish.
enum Samples {
    static func color(_ hex: UInt32) -> EggAppearance.Color {
        EggAppearance.Color(hex: hex)
    }

    /// The default brown hen's egg ("farm brown").
    static let farmBrown = EggAppearance(
        base: color(0xC8804E),
        pattern: .speckles(color: color(0x4A2012), density: 0.35, size: 0.3),
        finish: .matte,
        seed: 1
    )

    static let skins: [EggAppearance] = [
        farmBrown,
        EggAppearance(base: color(0xF1ECE3), pattern: .plain, finish: .matte, seed: 2),
        EggAppearance(
            base: color(0xD8CBB0),
            pattern: .speckles(color: color(0x3A2A1E), density: 0.85, size: 0.8),
            finish: .matte,
            seed: 3
        ),
        EggAppearance(base: color(0x7FB2DE), pattern: .plain, finish: .satin, seed: 4),
        EggAppearance(base: color(0xB8232B), pattern: .plain, finish: .glossy, seed: 5),
        EggAppearance(base: color(0xF3EDEE), pattern: .plain, finish: .pearl, seed: 6),
        EggAppearance(base: color(0xE0AE48), pattern: .plain, finish: .metallic, seed: 7),
        EggAppearance(base: color(0xF4D04A), pattern: .dots(color: color(0xFFFFFF), size: 0.5), finish: .satin, seed: 8),
        EggAppearance(
            base: color(0xF7F3EC),
            pattern: .stripes(colors: [color(0xE65A73), color(0xF2B33D), color(0x45AFC4)]),
            finish: .satin,
            seed: 9
        ),
        EggAppearance(base: color(0x3B78AE), pattern: .zigzag(color: color(0xF6E5BD)), finish: .matte, seed: 10),
        EggAppearance(base: color(0xEDEAE4), pattern: .marble(color: color(0x3A3E49)), finish: .glossy, seed: 11),
        EggAppearance(base: color(0xF2EEE7), pattern: .dipDye(color: color(0xD64C88)), finish: .matte, seed: 12),
        EggAppearance(
            base: color(0xFAF5EC),
            pattern: .confetti(colors: [color(0xE94F64), color(0x2BB3A3), color(0xF6C343), color(0x6C5CE7)]),
            finish: .glossy,
            seed: 13
        ),
        EggAppearance(base: color(0x1D2A58), pattern: .stars(color: color(0xF7E39C)), finish: .satin, seed: 14),
        EggAppearance(
            base: color(0x9ED8C2),
            pattern: .speckles(color: color(0x2E5B4F), density: 0.5, size: 0.35),
            finish: .satin,
            seed: 15
        ),
        EggAppearance(base: color(0xC7CCD3), pattern: .stripes(colors: [color(0x8E949C)]), finish: .metallic, seed: 16),
        EggAppearance(base: color(0x6A3FA0), pattern: .dots(color: color(0xF2C94C), size: 0.25), finish: .pearl, seed: 17),
        EggAppearance(base: color(0x2F8F5B), pattern: .marble(color: color(0xE9F2EA)), finish: .satin, seed: 18),
        EggAppearance(base: color(0xE88A3C), pattern: .zigzag(color: color(0x5B2A86)), finish: .glossy, seed: 19),
        EggAppearance(base: color(0xFFF7E6), pattern: .dipDye(color: color(0x2C7FB8)), finish: .pearl, seed: 20),
    ]
}
