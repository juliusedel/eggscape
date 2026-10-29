import GameKit
import os
import SwiftUI

/// Online play: a Game Center match carries the same messages as nearby play. The player with the lowest
/// `gamePlayerID` (including the local player) is the referee.
@MainActor
final class GameKitTransport: PeerTransport {
    let events: AsyncStream<TransportEvent>
    private(set) var connectedPeers: [RemotePeer] = []

    private let match: GKMatch
    private let delegate: GameKitMatchDelegate
    private let continuation: AsyncStream<TransportEvent>.Continuation
    /// Set while `waitForAllPlayers()` waits.
    private var allPlayersWaiter: CheckedContinuation<Bool, Never>?
    /// A player left, or the match failed or was closed: not everybody the matchmaker found will be there.
    private var isBroken = false
    private let logger = Logger(subsystem: "de.juliusedel.eggscape", category: "online")

    init(match: GKMatch) {
        self.match = match
        (events, continuation) = AsyncStream.makeStream(of: TransportEvent.self)
        delegate = GameKitMatchDelegate()
        delegate.transport = self
        match.delegate = delegate
        connectedPeers = match.players.map(Self.remote)
        for peer in connectedPeers {
            continuation.yield(.connected(peer))
        }
    }

    /// The local player's id as the race logic uses it.
    var localPlayerID: String {
        GKLocalPlayer.local.gamePlayerID
    }

    var localDisplayName: String {
        GKLocalPlayer.local.displayName
    }

    /// The referee: the lowest player id among everybody in the match.
    var refereeID: String {
        ([localPlayerID] + match.players.map(\.gamePlayerID)).min() ?? localPlayerID
    }

    /// The referee's phone, unless that is this one.
    var refereePeer: RemotePeer? {
        match.players.first { $0.gamePlayerID == refereeID }.map(Self.remote)
    }

    /// Waits until every player the matchmaker found is connected: only then do all phones know the same players and
    /// pick the same referee. `false` when a player left or the match failed first. Call it once; `events` keeps
    /// everything that happens meanwhile for the race room.
    func waitForAllPlayers() async -> Bool {
        guard !isBroken else { return false }
        guard match.expectedPlayerCount > 0 else { return true }
        return await withCheckedContinuation { allPlayersWaiter = $0 }
    }

    func send(_ data: Data, to peers: [RemotePeer]?, reliable: Bool) {
        let targets = peers
            .map { wanted in match.players.filter { player in wanted.contains { $0.id == player.gamePlayerID } } }
            ?? match.players
        guard !targets.isEmpty else { return }
        do {
            try match.send(data, to: targets, dataMode: reliable ? .reliable : .unreliable)
        } catch {
            logger.error("Sending failed: \(error.localizedDescription)")
        }
    }

    func close() {
        finishWaiting(allConnected: false)
        match.disconnect()
        match.delegate = nil
        connectedPeers = []
        continuation.finish()
    }

    fileprivate func received(_ data: Data, from player: GKPlayer) {
        continuation.yield(.received(data, from: Self.remote(player)))
    }

    fileprivate func player(_ player: GKPlayer, changed state: GKPlayerConnectionState) {
        let remote = Self.remote(player)
        switch state {
        case .connected:
            if !connectedPeers.contains(remote) {
                connectedPeers.append(remote)
            }
            continuation.yield(.connected(remote))
            if match.expectedPlayerCount == 0 {
                finishWaiting(allConnected: true)
            }
        case .disconnected:
            connectedPeers.removeAll { $0 == remote }
            continuation.yield(.disconnected(remote))
            finishWaiting(allConnected: false)
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    fileprivate func failed(_ message: String) {
        continuation.yield(.failed(message))
        finishWaiting(allConnected: false)
    }

    /// Ends `waitForAllPlayers()`; once a player left or the match failed, later calls end right away.
    private func finishWaiting(allConnected: Bool) {
        if !allConnected {
            isBroken = true
        }
        allPlayersWaiter?.resume(returning: allConnected)
        allPlayersWaiter = nil
    }

    private static func remote(_ player: GKPlayer) -> RemotePeer {
        RemotePeer(id: player.gamePlayerID, displayName: player.displayName)
    }
}

/// GameKit objects are only handed to the main actor, where they are used.
private struct PlayerBox: @unchecked Sendable {
    let player: GKPlayer
}

/// Receives GKMatch callbacks and forwards them to the main actor.
private final class GameKitMatchDelegate: NSObject, GKMatchDelegate, @unchecked Sendable {
    /// Set once right after creation, read on the main actor only.
    @MainActor weak var transport: GameKitTransport?

    func match(_: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        let box = PlayerBox(player: player)
        Task { @MainActor in transport?.received(data, from: box.player) }
    }

    func match(_: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        let box = PlayerBox(player: player)
        Task { @MainActor in transport?.player(box.player, changed: state) }
    }

    func match(_: GKMatch, didFailWithError error: (any Error)?) {
        let message = error?.localizedDescription ?? ""
        Task { @MainActor in transport?.failed(message) }
    }
}

/// Apple's matchmaking screen for 2-4 players, including invitations to friends; with an `invite`, it joins the match
/// a friend invited us to.
struct MatchmakerView: UIViewControllerRepresentable {
    var invite: GKInvite?
    var onMatch: (GKMatch) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMatch: onMatch, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 4
        request.defaultNumberOfPlayers = 2
        let made = invite.flatMap(GKMatchmakerViewController.init(invite:))
            ?? GKMatchmakerViewController(matchRequest: request)
        guard let controller = made else {
            return UIViewController()
        }
        controller.matchmakerDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}

    final class Coordinator: NSObject, GKMatchmakerViewControllerDelegate {
        private let onMatch: (GKMatch) -> Void
        private let onCancel: () -> Void

        init(onMatch: @escaping (GKMatch) -> Void, onCancel: @escaping () -> Void) {
            self.onMatch = onMatch
            self.onCancel = onCancel
        }

        func matchmakerViewController(_: GKMatchmakerViewController, didFind match: GKMatch) {
            onMatch(match)
        }

        func matchmakerViewControllerWasCancelled(_: GKMatchmakerViewController) {
            onCancel()
        }

        func matchmakerViewController(_: GKMatchmakerViewController, didFailWithError _: any Error) {
            onCancel()
        }
    }
}
