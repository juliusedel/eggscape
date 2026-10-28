import EggscapeCore
import Foundation

/// Localized names of the egg skins and their tiers; the catalog itself only knows stable ids.
enum SkinNames {
    static func name(for skin: EggSkin) -> LocalizedStringResource {
        switch skin.id {
        case "classic-white": "Klassisch Weiß"
        case "farm-brown": "Hofei Braun"
        case "quail": "Wachtelei"
        case "sky-blue": "Himmelblau"
        case "lemon-yellow": "Zitronengelb"
        case "rose": "Rosé"
        case "mint": "Minze"
        case "orange": "Orange"
        case "lilac": "Flieder"
        case "polka-dots": "Tupfen"
        case "navy-stripes": "Marinestreifen"
        case "zigzag": "Zickzack"
        case "dip-dye": "Zweifarbig"
        case "confetti": "Konfetti"
        case "marble": "Marmor"
        case "starry-night": "Sternennacht"
        case "pearl-white": "Perlmutt"
        case "silver-metallic": "Silber"
        case "gold-metallic": "Gold"
        case "rainbow-stripes": "Regenbogen"
        default: "Ei"
        }
    }

    static func tier(_ tier: EggSkin.Tier) -> LocalizedStringResource {
        switch tier {
        case .common: "Gewöhnlich"
        case .rare: "Selten"
        case .epic: "Episch"
        case .legendary: "Legendär"
        }
    }
}
