/// The kinds of weather. A new kind is added here and given its effects in `WeatherSystem`.
public enum WeatherKind: String, CaseIterable, Codable, Hashable, Sendable {
    /// Sunny, no weather effects.
    case clear
    case wind
    case rain
    /// Gewitter: wind, rain and lightning together.
    case storm
}

/// The weather a player picks for a time trial or a multiplayer race.
public enum WeatherOption: Codable, Hashable, Sendable {
    case off
    /// The same weather at full strength along the whole track.
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
