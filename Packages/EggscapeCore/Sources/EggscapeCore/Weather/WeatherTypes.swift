/// The kinds of weather. A new kind is added here and mapped to its effects in `WeatherConditions.mix`.
public enum WeatherKind: String, CaseIterable, Codable, Hashable, Sendable {
    /// Sunny, no weather effects.
    case clear
    /// Gusts push the egg sideways.
    case wind
    /// A wet, slippery bowl, raindrops and puddles.
    case rain
    /// Gewitter: wind, rain and lightning together.
    case storm
}

/// The weather a player picks for a time trial or a multiplayer race.
public enum WeatherOption: Codable, Hashable, Sendable {
    /// No weather at all, also in Endlos.
    case off
    /// The same weather along the whole track: at full strength in a time trial, growing stronger every stage in
    /// Endlos.
    case fixed(WeatherKind)
    /// "Zufall": random weather that escalates along the track.
    case random
}

/// The weather on one stretch of the track.
public struct WeatherConditions: Codable, Hashable, Sendable {
    public var kind: WeatherKind
    /// 0 ... 1, where 1 is the full strength described in `GameConfig`.
    public var intensity: Double

    public init(kind: WeatherKind, intensity: Double) {
        self.kind = kind
        self.intensity = intensity
    }

    public static let clear = WeatherConditions(kind: .clear, intensity: 0)
}

/// How strongly each effect of the weather acts, each 0 ... 1.
///
/// Every kind of weather is a mix of a few small effects rather than a case in one big switch, so a new kind (say
/// hail) needs one new effect type, a field here, a line in `WeatherConditions.mix` and a line in
/// `WeatherSystem.step`, without touching the existing effects.
public struct WeatherMix: Hashable, Sendable {
    /// Gusts from the shared timeline push the egg sideways.
    public var wind: Double
    /// Less damping, raindrops and puddles.
    public var rain: Double
    /// Strikes from the shared timeline jolt the egg.
    public var lightning: Double

    public init(wind: Double = 0, rain: Double = 0, lightning: Double = 0) {
        self.wind = wind
        self.rain = rain
        self.lightning = lightning
    }

    /// No weather effects.
    public static let calm = WeatherMix()
}

public extension WeatherConditions {
    /// The effects this weather is made of, scaled by its intensity.
    var mix: WeatherMix {
        // `> 0` also maps NaN to calm.
        let strength = intensity > 0 ? min(intensity, 1) : 0
        return switch kind {
        case .clear: .calm
        case .wind: WeatherMix(wind: strength)
        case .rain: WeatherMix(rain: strength)
        case .storm: WeatherMix(wind: strength, rain: strength, lightning: strength)
        }
    }
}
