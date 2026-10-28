import GameKit
import Observation
import os
import UIKit

/// Game Center sign-in, score submission and leaderboard loading. Signing in is lazy: it starts only when the player
/// opens the leaderboards or online play, and uses Apple's own sheet.
@MainActor
@Observable
final class GameCenterService {
    enum Status: Equatable {
        case signedOut
        case signingIn
        case signedIn(name: String)
        /// Game Center is turned off, restricted or the sign-in failed.
        case unavailable(String)
    }

    enum Scope: String, CaseIterable, Identifiable {
        case global
        case friends

        var id: String {
            rawValue
        }
    }

    struct Entry: Identifiable, Equatable {
        let id: String
        let rank: Int
        let name: String
        let score: String
        let isLocalPlayer: Bool
    }

    struct Board: Equatable {
        var entries: [Entry]
        var localEntry: Entry?
        var totalPlayers: Int
    }

    private(set) var status = Status.signedOut
    @ObservationIgnored private let logger = Logger(subsystem: "de.juliusedel.eggscape", category: "gamecenter")
    /// Best scores reached before signing in, submitted once signed in.
    @ObservationIgnored private var pendingScores: [String: Int] = [:]

    var isSignedIn: Bool {
        if case .signedIn = status {
            true
        } else {
            false
        }
    }

    func signIn() {
        switch status {
        case .signingIn, .signedIn:
            return
        case .signedOut, .unavailable:
            break
        }
        status = .signingIn
        // GameKit may call this several times and on any thread.
        GKLocalPlayer.local.authenticateHandler = { @Sendable [weak self] viewController, error in
            let message = error?.localizedDescription
            let sheet = SendableViewController(viewController)
            Task { @MainActor in
                self?.handleAuthentication(sheet: sheet.value, errorMessage: message)
            }
        }
    }

    private func handleAuthentication(sheet: UIViewController?, errorMessage: String?) {
        if let sheet {
            present(sheet)
            return
        }
        let player = GKLocalPlayer.local
        if player.isAuthenticated {
            status = .signedIn(name: player.displayName)
            submitPendingScores()
        } else {
            status = .unavailable(errorMessage ?? String(localized: "Game Center ist nicht verfügbar."))
        }
    }

    /// Submits a score; remembers the best one per leaderboard if the player is not signed in yet.
    func submit(score: Int, to leaderboardID: String, lowerIsBetter: Bool) {
        guard isSignedIn else {
            let previous = pendingScores[leaderboardID]
            if previous.map({ lowerIsBetter ? score < $0 : score > $0 }) ?? true {
                pendingScores[leaderboardID] = score
            }
            return
        }
        Task {
            do {
                try await GKLeaderboard.submitScore(
                    score,
                    context: 0,
                    player: GKLocalPlayer.local,
                    leaderboardIDs: [leaderboardID]
                )
            } catch {
                logger.error("Submitting to \(leaderboardID) failed: \(error.localizedDescription)")
            }
        }
    }

    func loadBoard(_ leaderboardID: String, scope: Scope, count: Int = 50) async throws -> Board {
        guard let leaderboard = try await GKLeaderboard.loadLeaderboards(IDs: [leaderboardID]).first else {
            throw GKError(.gameUnrecognized)
        }
        let playerScope: GKLeaderboard.PlayerScope = scope == .global ? .global : .friendsOnly
        let (local, entries, total) = try await leaderboard.loadEntries(
            for: playerScope,
            timeScope: .allTime,
            range: NSRange(location: 1, length: count)
        )
        return Board(
            entries: entries.map(Self.entry),
            localEntry: local.map(Self.entry),
            totalPlayers: total
        )
    }

    /// Opens Apple's Game Center leaderboards.
    func showGameCenter() {
        GKAccessPoint.shared.trigger(state: .leaderboards) {}
    }

    private func submitPendingScores() {
        let pending = pendingScores
        pendingScores = [:]
        for (leaderboardID, score) in pending {
            submit(score: score, to: leaderboardID, lowerIsBetter: false)
        }
    }

    private static func entry(_ entry: GKLeaderboard.Entry) -> Entry {
        Entry(
            id: entry.player.gamePlayerID,
            rank: entry.rank,
            name: entry.player.displayName,
            score: entry.formattedScore,
            isLocalPlayer: entry.player.gamePlayerID == GKLocalPlayer.local.gamePlayerID
        )
    }

    private func present(_ viewController: UIViewController) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard var top = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { return }
        while let presented = top.presentedViewController {
            top = presented
        }
        top.present(viewController, animated: true)
    }
}

/// GameKit hands the sign-in sheet to a background callback; it is only touched again on the main actor.
private struct SendableViewController: @unchecked Sendable {
    let value: UIViewController?

    init(_ value: UIViewController?) {
        self.value = value
    }
}
