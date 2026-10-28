import EggscapeCore
import Foundation

extension RaceDistance: @retroactive Identifiable {
    public var id: String {
        rawValue
    }

    var title: LocalizedStringResource {
        switch self {
        case .short: "Kurz"
        case .medium: "Mittel"
        case .long: "Lang"
        }
    }
}

extension WeatherKind {
    var title: LocalizedStringResource {
        switch self {
        case .clear: "Sonnig"
        case .wind: "Wind"
        case .rain: "Regen"
        case .storm: "Gewitter"
        }
    }

    var symbolName: String {
        switch self {
        case .clear: "sun.max.fill"
        case .wind: "wind"
        case .rain: "cloud.rain.fill"
        case .storm: "cloud.bolt.rain.fill"
        }
    }
}

extension WeatherOption: @retroactive Identifiable {
    /// The choices offered for time trials and multiplayer races, in display order.
    static let choices: [WeatherOption] = [.off, .fixed(.wind), .fixed(.rain), .fixed(.storm), .random]

    public var id: String {
        storageKey
    }

    var title: LocalizedStringResource {
        switch self {
        case .off: "Kein Wetter"
        case let .fixed(kind): kind.title
        case .random: "Zufall"
        }
    }

    var symbolName: String {
        switch self {
        case .off: "sun.max.fill"
        case let .fixed(kind): kind.symbolName
        case .random: "dice.fill"
        }
    }
}

extension BackgroundMode {
    var title: LocalizedStringResource {
        switch self {
        case .white: "Weiß"
        case .camera: "Kamera"
        }
    }
}
