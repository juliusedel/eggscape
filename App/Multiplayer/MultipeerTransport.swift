import Foundation
import MultipeerConnectivity
import os

// MultipeerConnectivity is deprecated as of the iOS 27 SDK but still works, and the build spec asks for it. All of it
// lives in this file behind `PeerTransport`, so a Network framework transport can replace it without touching the
// lobby or the race. See docs/ASSUMPTIONS.md.

/// Hosts or joins a nearby room ("Raum") with MultipeerConnectivity: the host advertises, joiners browse and invite
/// themselves, the host accepts automatically while there is room.
@available(iOS, deprecated: 27.0, message: "MultipeerConnectivity is deprecated; replace with Network framework")
@MainActor
final class MultipeerTransport: PeerTransport {
    static let serviceType = "eggscape"
    static let maxPlayers = 4

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
    private let session: MCSession
    private let delegate: MultipeerDelegate
    private let continuation: AsyncStream<TransportEvent>.Continuation
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var peersByID: [String: MCPeerID] = [:]
    private var foundPeers: [String: (peer: MCPeerID, room: DiscoveredRoom)] = [:]
    private let logger = Logger(subsystem: "de.juliusedel.eggscape", category: "nearby")

    init(displayName: String) {
        localPeer = Self.peerID(for: displayName)
        session = MCSession(peer: localPeer, securityIdentity: nil, encryptionPreference: .required)
        (events, continuation) = AsyncStream.makeStream(of: TransportEvent.self)
        delegate = MultipeerDelegate()
        session.delegate = delegate
        delegate.transport = self
    }

    // MARK: Hosting

    /// "Raum erstellen": makes this phone visible to others nearby.
    func startHosting() {
        let advertiser = MCNearbyServiceAdvertiser(
            peer: localPeer,
            discoveryInfo: ["v": String(EggscapeProtocol.version)],
            serviceType: Self.serviceType
        )
        advertiser.delegate = delegate
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
    }

    func stopHosting() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
    }

    // MARK: Joining

    /// "Beitreten": lists rooms nearby.
    func startBrowsing() {
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

    /// Asks the host to let us in; `context` carries our player id and nickname.
    func join(_ room: DiscoveredRoom, context: Data) {
        guard let browser, let host = foundPeers[room.id]?.peer else { return }
        browser.invitePeer(host, to: session, withContext: context, timeout: 15)
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
        stopHosting()
        stopBrowsing()
        session.disconnect()
        connectedPeers = []
        peersByID = [:]
        continuation.finish()
    }

    // MARK: Delegate callbacks (main actor)

    fileprivate func peer(_ peer: MCPeerID, changed state: MCSessionState) {
        let remote = Self.remote(peer)
        switch state {
        case .connected:
            peersByID[remote.id] = peer
            if !connectedPeers.contains(remote) {
                connectedPeers.append(remote)
            }
            continuation.yield(.connected(remote))
        case .notConnected:
            let wasConnected = connectedPeers.contains(remote)
            connectedPeers.removeAll { $0 == remote }
            peersByID[remote.id] = nil
            if wasConnected {
                continuation.yield(.disconnected(remote))
            }
        case .connecting:
            break
        @unknown default:
            break
        }
    }

    fileprivate func received(_ data: Data, from peer: MCPeerID) {
        continuation.yield(.received(data, from: Self.remote(peer)))
    }

    fileprivate func invitation(from peer: MCPeerID, reply: InvitationReply) {
        let accept = connectedPeers.count + 1 < Self.maxPlayers && acceptsPlayers()
        reply.callback(accept, accept ? session : nil)
    }

    fileprivate func found(_ peer: MCPeerID, info: [String: String]?) {
        // Rooms of other protocol versions cannot race with us; do not list them.
        guard info?["v"] == String(EggscapeProtocol.version) else { return }
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

    private static func remote(_ peer: MCPeerID) -> RemotePeer {
        RemotePeer(id: "\(peer.hash)-\(peer.displayName)", displayName: peer.displayName)
    }

    /// Reuses the same MCPeerID per name across sessions, as Apple recommends, to avoid ghost peers.
    private static func peerID(for displayName: String) -> MCPeerID {
        let name = displayName.isEmpty ? "Eggscape" : String(displayName.prefix(40))
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

/// MultipeerConnectivity's reply block for an invitation; called once, on the main actor.
struct InvitationReply: @unchecked Sendable {
    let callback: (Bool, MCSession?) -> Void
}

/// Receives MultipeerConnectivity callbacks on its private queues and forwards them to the main actor.
@available(iOS, deprecated: 27.0, message: "MultipeerConnectivity is deprecated; replace with Network framework")
private final class MultipeerDelegate: NSObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate,
    MCNearbyServiceBrowserDelegate, @unchecked Sendable
{
    /// Set once right after creation, read on the main actor only.
    @MainActor weak var transport: MultipeerTransport?

    func session(_: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let box = PeerBox(peer: peerID)
        Task { @MainActor in transport?.peer(box.peer, changed: state) }
    }

    func session(_: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let box = PeerBox(peer: peerID)
        Task { @MainActor in transport?.received(data, from: box.peer) }
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
        withContext _: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        let reply = InvitationReply(callback: invitationHandler)
        let box = PeerBox(peer: peerID)
        Task { @MainActor in
            if let transport {
                transport.invitation(from: box.peer, reply: reply)
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

/// Shared protocol constants of the app.
enum EggscapeProtocol {
    static let version = 1
}
