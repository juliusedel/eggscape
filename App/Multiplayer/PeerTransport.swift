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

enum TransportEvent: Sendable {
    case connected(RemotePeer)
    case disconnected(RemotePeer)
    case received(Data, from: RemotePeer)
    /// The room could not be joined or the host stopped hosting.
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
