/// A Game Center leaderboard, configured in App Store Connect.
///
/// The raw values are the leaderboard ids there. They must never change: Game Center keeps the scores already
/// submitted under the old id, so a renamed leaderboard would start empty. The time trials kept their ids when they
/// were shortened from 150, 300 and 600 m: a time from the longer courses that is already on a board is slower than
/// any run over the new lengths, so it ranks last.
public enum LeaderboardID: String, CaseIterable, Codable, Hashable, Sendable {
    /// Best time over 15 m.
    case shortTimeTrial = "de.juliusedel.eggscape.time.short"
    /// Best time over 50 m.
    case mediumTimeTrial = "de.juliusedel.eggscape.time.medium"
    /// Best time over 100 m.
    case longTimeTrial = "de.juliusedel.eggscape.time.long"
    /// Longest endless run.
    case endless = "de.juliusedel.eggscape.endless"

    /// The leaderboard that ranks runs on `course`.
    public init(course: Course) {
        switch course {
        case .timeTrial(.short): self = .shortTimeTrial
        case .timeTrial(.medium): self = .mediumTimeTrial
        case .timeTrial(.long): self = .longTimeTrial
        case .endless: self = .endless
        }
    }

    /// The course whose runs this leaderboard ranks.
    public var course: Course {
        switch self {
        case .shortTimeTrial: .timeTrial(.short)
        case .mediumTimeTrial: .timeTrial(.medium)
        case .longTimeTrial: .timeTrial(.long)
        case .endless: .endless
        }
    }

    /// Time trials rank the fastest time first, endless the longest distance. Must match the score sort order in
    /// App Store Connect: "Low to High" for the time trials, "High to Low" for endless.
    public var lowerIsBetter: Bool {
        switch self {
        case .shortTimeTrial, .mediumTimeTrial, .longTimeTrial: true
        case .endless: false
        }
    }
}
