import Foundation

/// One message on the wire, with its sender and the protocol version it was written in:
/// `{"version":3,"sender":"<player id>","message":{"type":"progress",...}}` (the messages are listed at `NetMessage`).
///
/// ## Versioning
///
/// `EggscapeCore.protocolVersion` names the format, and phones only race together when their versions match. So the
/// version is the one thing every future build must still be able to read: it sits at the top level, and `NetCodec`
/// checks it before it looks at the message. Bump the version when a message or field is removed, renamed, retyped
/// or becomes required, and when an enum on the wire gains a value (a weather kind, a distance), because older
/// builds cannot read those. Bump it as well when the same messages come to mean another race, such as a distance
/// of a new length, because the phones would then run different courses. Two changes keep the version:
/// - a new optional field: decoders ignore keys they do not know, and newer ones must cope with it missing;
/// - a new message type that older builds can do without: they report it as `NetCodecError.unknownMessageType`.
public struct NetEnvelope: Codable, Equatable, Sendable {
    public var version: Int
    public var sender: PlayerID
    public var message: NetMessage

    public init(version: Int = EggscapeCore.protocolVersion, sender: PlayerID, message: NetMessage) {
        self.version = version
        self.sender = sender
        self.message = message
    }

    /// The JSON keys are part of the wire format: when renaming a property, keep its key (`case newName = "oldName"`).
    private enum CodingKeys: String, CodingKey {
        case version
        case sender
        case message
    }
}

/// Why `NetCodec` could not read or write an envelope.
public enum NetCodecError: Error, Equatable, Sendable {
    /// The sender speaks another protocol version, so nothing else in the data can be trusted. The app asks the
    /// players to install the same version of the game.
    case versionMismatch(received: Int, expected: Int)
    /// A message type this build does not know, from a newer build of the same protocol version. Safe to ignore.
    case unknownMessageType(String)
    /// Not an envelope: not JSON, or a field is missing, has the wrong type or holds an unknown value.
    case invalidData(String)
    /// The envelope cannot be written as JSON, for example because a number is NaN or infinite.
    case unencodable(String)
}

/// Turns envelopes into compact JSON and back.
///
/// The output has no whitespace and sorted keys, so the same message always gives the same bytes, which keeps the
/// format easy to pin in tests and to compare in logs.
public struct NetCodec: Sendable {
    /// The protocol version this codec writes and the only one it accepts.
    public let version: Int

    public init(version: Int = EggscapeCore.protocolVersion) {
        self.version = version
    }

    /// Wraps `message` in an envelope of this codec's version.
    public func encode(_ message: NetMessage, from sender: PlayerID) throws(NetCodecError) -> Data {
        try encode(NetEnvelope(version: version, sender: sender, message: message))
    }

    /// Writes the envelope as it is, including its version.
    public func encode(_ envelope: NetEnvelope) throws(NetCodecError) -> Data {
        // A fresh encoder per call: it is a class, and sharing one would quietly give this value type shared state.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(envelope)
        } catch {
            throw .unencodable(String(describing: error))
        }
    }

    /// Reads an envelope of this codec's version.
    ///
    /// The version is checked first, so data from another version is reported as `versionMismatch` even when its
    /// message would not decode, and an unknown message type is told apart from broken data.
    public func decode(_ data: Data) throws(NetCodecError) -> NetEnvelope {
        let decoder = JSONDecoder()
        let header: EnvelopeHeader
        do {
            header = try decoder.decode(EnvelopeHeader.self, from: data)
        } catch {
            throw .invalidData(String(describing: error))
        }
        guard header.version == version else {
            throw .versionMismatch(received: header.version, expected: version)
        }
        if let type = header.messageType, NetMessage.Kind(rawValue: type) == nil {
            throw .unknownMessageType(type)
        }
        do {
            return try decoder.decode(NetEnvelope.self, from: data)
        } catch {
            throw .invalidData(String(describing: error))
        }
    }
}

/// The part of an envelope that every version can read. Its keys must match `NetEnvelope` and `NetMessage`.
private struct EnvelopeHeader: Decodable {
    var version: Int
    /// `nil` when the message or its type is missing; decoding the whole envelope then reports what is wrong.
    var messageType: String?

    private enum CodingKeys: String, CodingKey {
        case version
        case message
    }

    private enum MessageKeys: String, CodingKey {
        case type
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        messageType = try? container.nestedContainer(keyedBy: MessageKeys.self, forKey: .message)
            .decode(String.self, forKey: .type)
    }
}

extension KeyedDecodingContainer {
    /// Decodes one of a fixed set of strings (a message type, a distance, a weather kind) and names an unknown one in
    /// the error.
    func decodeWireValue<Value: RawRepresentable>(_: Value.Type, forKey key: Key) throws -> Value
        where Value.RawValue == String
    {
        let name = try decode(String.self, forKey: key)
        guard let value = Value(rawValue: name) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Unknown value \"\(name)\" for \(Value.self)"
            )
        }
        return value
    }
}
