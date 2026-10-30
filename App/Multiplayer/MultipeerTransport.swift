import EggscapeCore
import Foundation
import MultipeerConnectivity
import os

// MultipeerConnectivity is deprecated as of the iOS 27 SDK but still works, and the build spec asks for it. All of it
// lives in this file behind `PeerTransport`, so a Network framework transport can replace it without touching the
// lobby or the race. See docs/ASSUMPTIONS.md.

// Hosts or joins a nearby room ("Raum") with MultipeerConnectivity: the host advertises, joiners browse and invite
// themselves, the host accepts automatically while there is room.
#if hasAttribute(diagnose)
    @diagnose(DeprecatedDeclaration, as: ignored)
#endif
@MainActor
final class MultipeerTransport: NearbyTransport {
    static let serviceType = "eggscape"
    static let maxPlayers = 4
    /// Seconds MultipeerConnectivity waits for the host to answer an invitation.
    static let invitationTimeout = 15.0

    let events: AsyncStream<TransportEvent>
    private(set) var connectedPeers: [RemotePeer] = []
    /// Rooms found while browsing, for the join list.
    private(set) var rooms: [DiscoveredRoom] = [] {
        didSet { onRoomsChanged(rooms) }
    }

    var onRoomsChanged: ([DiscoveredRoom]) -> Void = { _ in }
    /// Decides whether the host accepts another player (e.g. not during a race).
    var acceptsPlayers: () -> Bool = { true }

    private let localPeer: MCPeerID
    /// A joiner gets a new one for every room it tries (see `cancelJoin()`).
    private var session: MCSession
    private let delegate: MultipeerDelegate
    private let continuation: AsyncStream<TransportEvent>.Continuation
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    /// Host side: the room exists. It is only advertised while `acceptsPlayers` allows another player.
    private var isHosting = false
    private var peersByID: [String: MCPeerID] = [:]
    /// What each joiner sent with its invitation (host side), by peer id.
    private var joinContexts: [String: Data] = [:]
    /// Host side: accepted invitations whose connection is still being set up, by peer id, with when they were
    /// accepted. They hold a seat, so phones that ask at the same moment cannot overfill the room.
    private var pendingPeers: [String: ContinuousClock.Instant] = [:]
    private var foundPeers: [String: (peer: MCPeerID, room: DiscoveredRoom)] = [:]
    /// Joiner side: the host we asked to let us in, by peer id, until it connects or the invitation fails.
    private var invitedHost: String?
    /// Joiner side: when the invitation went out, for the log.
    private var invitedAt: ContinuousClock.Instant?
    private var invitationDeadline: Task<Void, Never>?
    private let logger = Logger(subsystem: "de.juliusedel.eggscape", category: "nearby")

    init(displayName: String) {
        localPeer = Self.peerID(for: displayName)
        (events, continuation) = AsyncStream.makeStream(of: TransportEvent.self)
        delegate = MultipeerDelegate()
        session = Self.makeSession(for: localPeer, delegate: delegate)
        delegate.transport = self
    }

    // MARK: Hosting

    /// "Raum erstellen": makes this phone visible to others nearby.
    func startHosting() {
        isHosting = true
        updateAdvertising()
    }

    func stopHosting() {
        isHosting = false
        updateAdvertising()
    }

    /// Advertises the room only while it takes another player, so joiners do not list a room that is racing, showing
    /// results or full. Call after anything `acceptsPlayers` depends on changed.
    func updateAdvertising() {
        let advertises = isHosting && acceptsPlayers()
        if advertises, advertiser == nil {
            let advertiser = MCNearbyServiceAdvertiser(
                peer: localPeer,
                discoveryInfo: ["v": String(EggscapeCore.protocolVersion)],
                serviceType: Self.serviceType
            )
            advertiser.delegate = delegate
            advertiser.startAdvertisingPeer()
            self.advertiser = advertiser
        } else if !advertises, let advertiser {
            advertiser.stopAdvertisingPeer()
            self.advertiser = nil
        }
    }

    // MARK: Joining

    /// "Beitreten": lists rooms nearby. Called again, it starts over with a fresh list.
    func startBrowsing() {
        stopBrowsing()
        let browser = MCNearbyServiceBrowser(peer: localPeer, serviceType: Self.serviceType)
        browser.delegate = delegate
        browser.startBrowsingForPeers()
        self.browser = browser
    }

    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil
        foundPeers = [:]
        rooms = []
    }

    /// Asks the host to let us in; `context` carries our player id and nickname. Ends with `.connected` for the host,
    /// or with `.joinFailed`.
    func join(_ room: DiscoveredRoom, context: Data) {
        forgetInvitation()
        guard let browser, let host = foundPeers[room.id]?.peer else {
            continuation.yield(.joinFailed(.roomGone))
            return
        }
        invitedHost = room.id
        invitedAt = .now
        logger.info("Inviting ourselves to \(room.hostName)")
        browser.invitePeer(host, to: session, withContext: context, timeout: Self.invitationTimeout)
        // A turned-down or expired invitation shows up as `.notConnected` for the host; this covers it never coming.
        invitationDeadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.invitationTimeout + 2))
            guard !Task.isCancelled else { return }
            self?.joinFailed(.expired)
        }
    }

    /// Gives up on the room, whether the host has answered yet or not: forgets the invitation and leaves the session.
    /// An invitation cannot be taken back, so the next room gets a new session: a host that lets us in after all only
    /// reaches the old one, and we leave that again right away (see `peer(_:changed:in:)`).
    func cancelJoin() {
        forgetInvitation()
        session.disconnect()
        session = Self.makeSession(for: localPeer, delegate: delegate)
        connectedPeers = []
        peersByID = [:]
    }

    // MARK: PeerTransport

    func send(_ data: Data, to peers: [RemotePeer]?, reliable: Bool) {
        let targets = (peers ?? connectedPeers).compactMap { peersByID[$0.id] }
        guard !targets.isEmpty else { return }
        do {
            try session.send(data, toPeers: targets, with: reliable ? .reliable : .unreliable)
        } catch {
            logger.error("Sending failed: \(error.localizedDescription)")
        }
    }

    func close() {
        forgetInvitation()
        stopHosting()
        stopBrowsing()
        session.disconnect()
        connectedPeers = []
        peersByID = [:]
        continuation.finish()
    }

    // MARK: Delegate callbacks (main actor)

    fileprivate func peer(_ peer: MCPeerID, changed state: MCSessionState, in session: MCSession) {
        guard session === self.session else {
            // A room we gave up on let us in after all: its host would hold a seat for us and wait for us to be ready.
            if state == .connected {
                session.disconnect()
            }
            return
        }
        let remote = Self.remote(peer)
        if remote.id == invitedHost {
            let change = Self.describe(state)
            let seconds = secondsSinceInvitation
            logger.info(
                "Host \(remote.displayName) \(change, privacy: .public) at \(seconds, format: .fixed(precision: 1)) s"
            )
        }
        switch state {
        case .connected:
            pendingPeers[remote.id] = nil
            if remote.id == invitedHost {
                forgetInvitation()
            }
            peersByID[remote.id] = peer
            if !connectedPeers.contains(remote) {
                connectedPeers.append(remote)
            }
            continuation.yield(.connected(remote))
        case .notConnected:
            if let acceptedAt = pendingPeers.removeValue(forKey: remote.id) {
                let seconds = (ContinuousClock.now - acceptedAt).seconds
                logger.notice(
                    "Joiner \(remote.displayName) failed to connect after \(seconds, format: .fixed(precision: 1)) s"
                )
            }
            let wasConnected = connectedPeers.contains(remote)
            connectedPeers.removeAll { $0 == remote }
            peersByID[remote.id] = nil
            if wasConnected {
                continuation.yield(.disconnected(remote))
            } else if remote.id == invitedHost {
                joinFailed(.declinedOrFailed)
            }
        case .connecting:
            break
        @unknown default:
            break
        }
    }

    fileprivate func received(_ data: Data, from peer: MCPeerID, in session: MCSession) {
        guard session === self.session else { return }
        continuation.yield(.received(data, from: Self.remote(peer)))
    }

    fileprivate func invitation(from peer: MCPeerID, context: Data?, reply: InvitationReply) {
        let id = Self.remote(peer).id
        let hasSeat = connectedPeers.count + pendingPeers.count + 1 < Self.maxPlayers
        let isOpen = acceptsPlayers()
        let accept = hasSeat && isOpen
        if accept {
            pendingPeers[id] = .now
            if let context {
                joinContexts[id] = context
            }
            logger.info("Letting \(peer.displayName) in")
        } else {
            // The joiner only learns that it did not get in; this line on the host says why.
            let room = isOpen ? "open" : "racing, showing results or full"
            let seats = "\(connectedPeers.count) in, \(pendingPeers.count) joining"
            logger.notice("Turned \(peer.displayName) down: room \(room, privacy: .public), \(seats, privacy: .public)")
        }
        reply.callback(accept, accept ? session : nil)
    }

    /// The data a joiner sent with its invitation (host side).
    func joinContext(for peer: RemotePeer) -> Data? {
        joinContexts[peer.id]
    }

    fileprivate func found(_ peer: MCPeerID, info: [String: String]?) {
        // Rooms of other protocol versions cannot race with us; do not list them. Builds before protocol version 3
        // advertised "1" whatever their version, so none of them is listed either.
        guard info?["v"] == String(EggscapeCore.protocolVersion) else { return }
        let room = DiscoveredRoom(id: Self.remote(peer).id, hostName: peer.displayName, playerCount: nil)
        foundPeers[room.id] = (peer, room)
        rooms = foundPeers.values.map(\.room).sorted { $0.hostName < $1.hostName }
    }

    fileprivate func lost(_ peer: MCPeerID) {
        foundPeers[Self.remote(peer).id] = nil
        rooms = foundPeers.values.map(\.room).sorted { $0.hostName < $1.hostName }
    }

    fileprivate func failed(_ message: String) {
        continuation.yield(.failed(message))
    }

    // MARK: Helpers

    /// The host turned the invitation down (racing, showing results or full), the connection could not be set up, or
    /// the invitation expired.
    private func joinFailed(_ failure: JoinFailure) {
        guard invitedHost != nil else { return }
        cancelJoin()
        continuation.yield(.joinFailed(failure))
    }

    private func forgetInvitation() {
        invitedHost = nil
        invitedAt = nil
        invitationDeadline?.cancel()
        invitationDeadline = nil
    }

    private var secondsSinceInvitation: Double {
        invitedAt.map { (ContinuousClock.now - $0).seconds } ?? 0
    }

    private static func describe(_ state: MCSessionState) -> String {
        switch state {
        case .notConnected: "not connected"
        case .connecting: "connecting"
        case .connected: "connected"
        @unknown default: "in an unknown state"
        }
    }

    private static func remote(_ peer: MCPeerID) -> RemotePeer {
        RemotePeer(id: "\(peer.hash)-\(peer.displayName)", displayName: peer.displayName)
    }

    private static func makeSession(for peer: MCPeerID, delegate: MultipeerDelegate) -> MCSession {
        let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = delegate
        return session
    }

    /// `MCPeerID` takes at most 63 bytes of UTF-8 and raises an uncatchable exception for longer or empty names. Whole
    /// characters are dropped from the end, so an emoji is never cut in half; the lobby shows the full nickname from
    /// the join request anyway.
    static func peerName(for displayName: String) -> String {
        var name = displayName
        while name.utf8.count > 63 {
            name.removeLast()
        }
        return name.isEmpty ? "Eggscape" : name
    }

    /// Reuses the same MCPeerID per name across sessions, as Apple recommends, to avoid ghost peers.
    private static func peerID(for displayName: String) -> MCPeerID {
        let name = peerName(for: displayName)
        let key = "nearby.peerID.\(name)"
        if let data = UserDefaults.standard.data(forKey: key),
           let stored = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: data)
        {
            return stored
        }
        let peer = MCPeerID(displayName: name)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: peer, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: key)
        }
        return peer
    }
}

/// `MCPeerID` is immutable after creation, so handing it from a delegate queue to the main actor is safe.
private struct PeerBox: @unchecked Sendable {
    let peer: MCPeerID
}

/// The session a callback came from; the main actor only checks whether it is the current one, or disconnects it.
private struct SessionBox: @unchecked Sendable {
    let session: MCSession
}

/// MultipeerConnectivity's reply block for an invitation; called once, on the main actor.
struct InvitationReply: @unchecked Sendable {
    let callback: (Bool, MCSession?) -> Void
}

// Receives MultipeerConnectivity callbacks on its private queues and forwards them to the main actor.
#if hasAttribute(diagnose)
    @diagnose(DeprecatedDeclaration, as: ignored)
#endif
private final class MultipeerDelegate: NSObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate,
    MCNearbyServiceBrowserDelegate, @unchecked Sendable
{
    /// Set once right after creation, read on the main actor only.
    @MainActor weak var transport: MultipeerTransport?

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let box = PeerBox(peer: peerID)
        let source = SessionBox(session: session)
        Task { @MainActor in transport?.peer(box.peer, changed: state, in: source.session) }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let box = PeerBox(peer: peerID)
        let source = SessionBox(session: session)
        Task { @MainActor in transport?.received(data, from: box.peer, in: source.session) }
    }

    func session(_: MCSession, didReceive _: InputStream, withName _: String, fromPeer _: MCPeerID) {}

    func session(
        _: MCSession,
        didStartReceivingResourceWithName _: String,
        fromPeer _: MCPeerID,
        with _: Progress
    ) {}

    func session(
        _: MCSession,
        didFinishReceivingResourceWithName _: String,
        fromPeer _: MCPeerID,
        at _: URL?,
        withError _: (any Error)?
    ) {}

    func advertiser(
        _: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        let reply = InvitationReply(callback: invitationHandler)
        let box = PeerBox(peer: peerID)
        Task { @MainActor in
            if let transport {
                transport.invitation(from: box.peer, context: context, reply: reply)
            } else {
                reply.callback(false, nil)
            }
        }
    }

    func advertiser(_: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor in transport?.failed(message) }
    }

    func browser(_: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let box = PeerBox(peer: peerID)
        Task { @MainActor in transport?.found(box.peer, info: info) }
    }

    func browser(_: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let box = PeerBox(peer: peerID)
        Task { @MainActor in transport?.lost(box.peer) }
    }

    func browser(_: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor in transport?.failed(message) }
    }
}
