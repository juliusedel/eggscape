import EggscapeCore
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
    /// A friend's invitation the player accepted from a notification; the app opens the online room for it.
    var acceptedInvite: AcceptedInvite?
    @ObservationIgnored private lazy var inviteListener = InviteListener { [weak self] invite in
        self?.acceptedInvite = AcceptedInvite(invite: invite)
    }

    /// Called after every successful sign-in, e.g. to submit bests reached while signed out.
    @ObservationIgnored var onSignIn: () -> Void = {}
    @ObservationIgnored private let logger = Logger(subsystem: "de.juliusedel.eggscape", category: "gamecenter")

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
            let wasSignedIn = isSignedIn
            status = .signedIn(name: player.displayName)
            if !wasSignedIn {
                player.register(inviteListener)
                onSignIn()
            }
        } else {
            status = .unavailable(errorMessage ?? String(localized: "Game Center ist nicht verfügbar."))
        }
    }

    /// Submits a score if the player is signed in; Game Center keeps the best one. Bests reached while signed out are
    /// submitted from the personal records after signing in.
    func submit(_ score: LeaderboardScore) {
        guard isSignedIn else { return }
        Task {
            do {
                try await GKLeaderboard.submitScore(
                    score.value,
                    context: 0,
                    player: GKLocalPlayer.local,
                    leaderboardIDs: [score.leaderboard.rawValue]
                )
            } catch {
                logger.error("Submitting to \(score.leaderboard.rawValue) failed: \(error.localizedDescription)")
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

/// An accepted Game Center invitation, identifiable for presentation.
struct AcceptedInvite: Identifiable {
    let id = UUID()
    let invite: GKInvite
}

/// Receives accepted invitations from GameKit and hands them to the main actor.
private final class InviteListener: NSObject, GKLocalPlayerListener, @unchecked Sendable {
    private let onInvite: @MainActor (GKInvite) -> Void

    init(onInvite: @escaping @MainActor (GKInvite) -> Void) {
        self.onInvite = onInvite
    }

    func player(_: GKPlayer, didAccept invite: GKInvite) {
        let box = InviteBox(invite: invite)
        Task { @MainActor in onInvite(box.invite) }
    }
}

/// GKInvite is immutable once delivered; it is only used again on the main actor.
private struct InviteBox: @unchecked Sendable {
    let invite: GKInvite
}
