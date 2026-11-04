import Foundation

/// Another phone in the room, as the transport sees it.
struct RemotePeer: Hashable, Sendable {
    /// Unique for the lifetime of the connection.
    let id: String
    let displayName: String
}

/// A nearby room that can be joined.
struct DiscoveredRoom: Identifiable, Hashable, Sendable {
    let id: String
    let hostName: String
    /// Players already in the room, if the host advertises it.
    let playerCount: Int?
}

/// Why joining a nearby room failed. A joiner cannot tell a turned-down invitation from a connection that could not be
/// set up, so the player reads one message for every reason (`NearbySession.joinFailedMessage`); the log tells them
/// apart as far as they can be told.
enum JoinFailure: Equatable, Sendable {
    /// The room had gone from the list before the invitation went out.
    case roomGone
    /// MultipeerConnectivity reported the host as not connected early, before it ever connected and well within the
    /// invitation timeout: the host turned the invitation down (racing, showing results or full) or the connection
    /// could not be set up.
    case declinedOrFailed
    /// No answer or no connection within the invitation timeout: MultipeerConnectivity reported the host as not
    /// connected only at the timeout, or reported nothing (or was still connecting) when the transport gave up.
    case expired
    /// The host let us in, but the connection broke before it sent the lobby.
    case droppedWhileConnecting
    /// The host let us in, but never sent a lobby with this player in it.
    case noLobby

    /// English, for the log only.
    var logDescription: String {
        switch self {
        case .roomGone: "the room was no longer in the list"
        case .declinedOrFailed: "the host turned the invitation down or the connection could not be set up"
        case .expired: "no answer or no connection within the invitation timeout"
        case .droppedWhileConnecting: "the host connected, but the connection broke before the lobby came"
        case .noLobby: "the host connected, but sent no lobby with this player in it"
        }
    }
}

enum TransportEvent: Sendable {
    case connected(RemotePeer)
    case disconnected(RemotePeer)
    case received(Data, from: RemotePeer)
    /// Joiner: the host did not let us in, see `JoinFailure`.
    case joinFailed(JoinFailure)
    /// Nearby: iOS did not let this phone advertise its room (host) or look for rooms (joiner), for example while its
    /// Local Network prompt was still up. Nothing is wrong with the room, so `NearbySession` tries again. The text is
    /// for the log.
    case discoveryFailed(String)
    /// Online: the Game Center match failed, which ends the room.
    case failed(String)
}

/// Moves opaque message data between phones. Nearby play uses MultipeerConnectivity; online play can use GameKit.
/// The lobby and race logic only see this protocol.
@MainActor
protocol PeerTransport: AnyObject {
    var events: AsyncStream<TransportEvent> { get }
    var connectedPeers: [RemotePeer] { get }
    /// Sends to `peers`, or to everybody when `nil`. Unreliable sends may be dropped (used for 10 Hz progress).
    func send(_ data: Data, to peers: [RemotePeer]?, reliable: Bool)
    func close()
}

/// A nearby room's transport: besides moving messages it hosts, lists rooms and joins one. MultipeerConnectivity in the
/// app (`MultipeerTransport`); the tests drive `NearbySession` with a fake.
@MainActor
protocol NearbyTransport: PeerTransport {
    /// Rooms found while browsing.
    var onRoomsChanged: ([DiscoveredRoom]) -> Void { get set }
    /// Host: whether the room takes another player right now.
    var acceptsPlayers: () -> Bool { get set }
    /// Host: opens the room. Called again, it advertises the room anew, for when iOS turned the last attempt down.
    func startHosting()
    /// Host: call after anything `acceptsPlayers` depends on changed.
    func updateAdvertising()
    /// Joiner: lists rooms nearby. Called again, it starts over with a fresh list.
    func startBrowsing()
    func stopBrowsing()
    /// Joiner: asks the host to let us in. Ends with `.connected` for the host, or with `.joinFailed`.
    func join(_ room: DiscoveredRoom, context: Data)
    /// Joiner: gives up on the room, whether the host has answered yet or not.
    func cancelJoin()
    /// Host: what a joiner sent with its invitation.
    func joinContext(for peer: RemotePeer) -> Data?
}
