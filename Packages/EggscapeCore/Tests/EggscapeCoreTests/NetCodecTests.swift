@testable import EggscapeCore
import Foundation
import Testing

private let sampleLobby = LobbyState(
    hostID: "anna",
    players: [
        PlayerInfo(id: "anna", nickname: "Anna", eggSkinID: "classic", isHost: true, isReady: true),
        // A nickname that needs escaping, and a player who left.
        PlayerInfo(id: "ben", nickname: "Jürgen \"Eierkönig\" 🥚/2", eggSkinID: "gold-leaf", isConnected: false),
    ],
    settings: RaceSettings(distance: .long, weather: .fixed(.storm))
)

private let sampleResults = RaceResults(entries: [
    RaceResultEntry(place: 1, playerID: "ben", nickname: "Ben", status: .finished(time: 51.23), eggsLost: 1),
    RaceResultEntry(place: 2, playerID: "anna", nickname: "Anna", status: .outOfEggs(meters: 120.5), eggsLost: 3),
    RaceResultEntry(place: 3, playerID: "cem", nickname: "Cem", status: .disconnected(meters: 1.0 / 3), eggsLost: 0),
])

/// Every kind of message, with awkward values: extreme seeds and ids, fractions that binary floating point cannot
/// hold exactly, negative and huge times.
private let everyMessage: [NetMessage] = [
    .lobbyState(sampleLobby),
    .setSettings(.standard),
    .ready(true),
    .ready(false),
    .startRace(seed: .max, startAt: 5003.25),
    .startRace(seed: 0, startAt: -0.1),
    .progress(meters: 12.5, eggsLeft: 2),
    .progress(meters: 0.1 + 0.2, eggsLeft: 0),
    .eggDropped(eggsLeft: 1),
    .finished(FinishReport(completed: true, time: 51.234_567_89, meters: 150, eggsLost: 1)),
    .finished(FinishReport(completed: false, time: 33.3, meters: 99.99, eggsLost: 3)),
    .results(sampleResults),
    .results(RaceResults(entries: [])),
    .ping(id: 0, sentAt: 102.5),
    .ping(id: .max, sentAt: 1e9 + 0.123),
    .pong(id: 7, pingSentAt: 102.5, hostTime: 5000.75),
]

private let everyWeather: [WeatherOption] = [.off, .random] + WeatherKind.allCases.map(WeatherOption.fixed)

private let everyStatus: [RaceResultEntry.Status] = [
    .finished(time: 50.25),
    .outOfEggs(meters: 99.5),
    .disconnected(meters: 0),
]

/// An envelope of the current protocol version around `message`, as JSON text.
private func envelope(_ message: String, sender: String = "anna") -> Data {
    Data(#"{"version":\#(EggscapeCore.protocolVersion),"sender":"\#(sender)","message":\#(message)}"#.utf8)
}

/// The documented format (see `NetMessage`), written by hand the way an older build would send it.
private let documentedExamples: [(json: String, message: NetMessage)] = [
    (
        #"""
        {"type":"lobbyState","lobby":{"hostID":"A","players":[{"id":"A","nickname":"Anna","eggSkinID":"classic",
        "isHost":true,"isReady":false,"isConnected":true}],"settings":{"distance":"short","weather":{"type":"off"}}}}
        """#,
        .lobbyState(LobbyState(
            hostID: "A",
            players: [PlayerInfo(id: "A", nickname: "Anna", eggSkinID: "classic", isHost: true)]
        ))
    ),
    (
        #"{"type":"setSettings","settings":{"distance":"long","weather":{"type":"fixed","kind":"rain"}}}"#,
        .setSettings(RaceSettings(distance: .long, weather: .fixed(.rain)))
    ),
    (
        #"{"type":"setSettings","settings":{"distance":"medium","weather":{"type":"random"}}}"#,
        .setSettings(RaceSettings(distance: .medium, weather: .random))
    ),
    (#"{"type":"ready","isReady":true}"#, .ready(true)),
    (
        #"{"type":"startRace","seed":"9876543210123456789","startAt":5003.25}"#,
        .startRace(seed: 9_876_543_210_123_456_789, startAt: 5003.25)
    ),
    (#"{"type":"progress","meters":12.5,"eggsLeft":2}"#, .progress(meters: 12.5, eggsLeft: 2)),
    (#"{"type":"eggDropped","eggsLeft":1}"#, .eggDropped(eggsLeft: 1)),
    (
        #"{"type":"finished","report":{"completed":true,"time":51.23,"meters":150,"eggsLost":1}}"#,
        .finished(FinishReport(completed: true, time: 51.23, meters: 150, eggsLost: 1))
    ),
    (
        #"""
        {"type":"results","results":{"entries":[{"place":1,"playerID":"A","nickname":"Anna",
        "status":{"type":"finished","time":51.23},"eggsLost":1},{"place":2,"playerID":"B","nickname":"Ben",
        "status":{"type":"outOfEggs","meters":120},"eggsLost":3},{"place":3,"playerID":"C","nickname":"Cem",
        "status":{"type":"disconnected","meters":80},"eggsLost":0}]}}
        """#,
        .results(RaceResults(entries: [
            RaceResultEntry(place: 1, playerID: "A", nickname: "Anna", status: .finished(time: 51.23), eggsLost: 1),
            RaceResultEntry(place: 2, playerID: "B", nickname: "Ben", status: .outOfEggs(meters: 120), eggsLost: 3),
            RaceResultEntry(place: 3, playerID: "C", nickname: "Cem", status: .disconnected(meters: 80), eggsLost: 0),
        ]))
    ),
    (#"{"type":"ping","id":7,"sentAt":102.5}"#, .ping(id: 7, sentAt: 102.5)),
    (
        #"{"type":"pong","id":7,"pingSentAt":102.5,"hostTime":5000.75}"#,
        .pong(id: 7, pingSentAt: 102.5, hostTime: 5000.75)
    ),
]

/// Envelopes that are broken in one way each.
private let malformedMessages = [
    #"{"isReady":true}"#,
    #"{"type":7}"#,
    #"{"type":"ready"}"#,
    #"{"type":"ready","isReady":"yes"}"#,
    #"{"type":"progress","meters":"far","eggsLeft":2}"#,
    #"{"type":"progress","meters":12.5,"eggsLeft":2.5}"#,
    #"{"type":"startRace","seed":42,"startAt":1}"#,
    #"{"type":"startRace","seed":"-1","startAt":1}"#,
    #"{"type":"startRace","seed":"18446744073709551616","startAt":1}"#,
    #"{"type":"ping","id":-1,"sentAt":1}"#,
    #"{"type":"setSettings","settings":{"distance":"marathon","weather":{"type":"off"}}}"#,
    #"{"type":"setSettings","settings":{"distance":"short","weather":{"type":"fixed","kind":"snow"}}}"#,
    #"{"type":"setSettings","settings":{"distance":"short","weather":{"type":"fixed"}}}"#,
    #"{"type":"setSettings","settings":{"distance":"short","weather":{"type":"hail"}}}"#,
    #"{"type":"setSettings","settings":{"distance":"short","weather":"off"}}"#,
    #"{"type":"finished","report":{"completed":true,"time":51.2,"meters":150}}"#,
    #"""
    {"type":"results","results":{"entries":[{"place":1,"playerID":"A","nickname":"A","status":{"type":"won"},
    "eggsLost":0}]}}
    """#,
    #"""
    {"type":"lobbyState","lobby":{"hostID":7,"players":[],
    "settings":{"distance":"short","weather":{"type":"off"}}}}
    """#,
]

struct NetCodecTests {
    private let codec = NetCodec()

    /// The codec rejects `data` as broken (not as another version or an unknown message type).
    private func expectInvalidData(_ data: Data, sourceLocation: SourceLocation = #_sourceLocation) {
        let error = #expect(throws: NetCodecError.self, sourceLocation: sourceLocation) {
            try codec.decode(data)
        }
        switch error {
        case .invalidData?, nil:
            break
        default:
            Issue.record("expected invalidData, got \(String(describing: error))", sourceLocation: sourceLocation)
        }
    }

    private func text(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    @Test func samplesCoverEveryKind() {
        #expect(Set(everyMessage.map(\.kind)) == Set(NetMessage.Kind.allCases))
        #expect(Set(documentedExamples.map(\.message.kind)) == Set(NetMessage.Kind.allCases))
    }

    @Test(arguments: everyMessage)
    func everyMessageSurvivesARoundTrip(_ message: NetMessage) throws {
        let envelope = NetEnvelope(sender: "anna", message: message)
        #expect(try codec.decode(codec.encode(envelope)) == envelope)
    }

    @Test(arguments: RaceDistance.allCases, everyWeather)
    func everySettingSurvivesARoundTrip(distance: RaceDistance, weather: WeatherOption) throws {
        let message = NetMessage.setSettings(RaceSettings(distance: distance, weather: weather))
        #expect(try codec.decode(codec.encode(message, from: "anna")).message == message)
    }

    @Test(arguments: everyStatus)
    func everyStatusSurvivesARoundTrip(_ status: RaceResultEntry.Status) throws {
        let entry = RaceResultEntry(place: 1, playerID: "anna", nickname: "Anna", status: status, eggsLost: 2)
        let message = NetMessage.results(RaceResults(entries: [entry]))
        #expect(try codec.decode(codec.encode(message, from: "anna")).message == message)
    }

    @Test(arguments: documentedExamples)
    func readsTheDocumentedFormat(json: String, message: NetMessage) throws {
        let decoded = try codec.decode(envelope(json, sender: "A"))
        #expect(decoded == NetEnvelope(sender: "A", message: message))
    }

    @Test func progressKeepsItsExactShape() throws {
        let data = try codec.encode(.progress(meters: 12.5, eggsLeft: 2), from: "anna")
        let expected = #"{"message":{"eggsLeft":2,"meters":12.5,"type":"progress"},"sender":"anna","version":1}"#
        #expect(text(data) == expected)
    }

    @Test func startRaceSendsTheSeedAsDecimalText() throws {
        let data = try codec.encode(.startRace(seed: .max, startAt: 5003.25), from: "anna")
        #expect(text(data) == #"""
        {"message":{"seed":"18446744073709551615","startAt":5003.25,"type":"startRace"},\#
        "sender":"anna","version":1}
        """#)
    }

    @Test func resultsKeepTheirExactShape() throws {
        let entry = RaceResultEntry(
            place: 1,
            playerID: "A",
            nickname: "Anna",
            status: .finished(time: 51.23),
            eggsLost: 1
        )
        let data = try codec.encode(.results(RaceResults(entries: [entry])), from: "A")
        #expect(text(data) == #"""
        {"message":{"results":{"entries":[{"eggsLost":1,"nickname":"Anna","place":1,"playerID":"A",\#
        "status":{"time":51.23,"type":"finished"}}]},"type":"results"},"sender":"A","version":1}
        """#)
    }

    @Test func lobbyStateKeepsItsKeys() throws {
        let data = try codec.encode(.lobbyState(sampleLobby), from: "anna")
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(root.keys) == ["version", "sender", "message"])
        let message = try #require(root["message"] as? [String: Any])
        #expect(Set(message.keys) == ["type", "lobby"])
        #expect(message["type"] as? String == "lobbyState")
        let lobby = try #require(message["lobby"] as? [String: Any])
        #expect(Set(lobby.keys) == ["hostID", "players", "settings"])
        let players = try #require(lobby["players"] as? [[String: Any]])
        #expect(players.count == 2)
        for player in players {
            #expect(Set(player.keys) == ["id", "nickname", "eggSkinID", "isHost", "isReady", "isConnected"])
        }
        let settings = try #require(lobby["settings"] as? [String: Any])
        #expect(settings["distance"] as? String == "long")
        #expect(settings["weather"] as? [String: String] == ["type": "fixed", "kind": "storm"])
    }

    @Test func writesTheSameBytesEveryTime() throws {
        let first = try codec.encode(.lobbyState(sampleLobby), from: "anna")
        let second = try codec.encode(.lobbyState(sampleLobby), from: "anna")
        #expect(first == second)
        // Only what JSON requires is escaped: the quotes, not the slash or the umlauts and the emoji.
        #expect(text(first).contains(#""nickname":"Jürgen \"Eierkönig\" 🥚/2""#))
    }

    @Test func rejectsOtherProtocolVersions() throws {
        let current = EggscapeCore.protocolVersion
        for version in [current - 1, current + 1] {
            let data = try NetCodec(version: version).encode(.ready(true), from: "ben")
            #expect(throws: NetCodecError.versionMismatch(received: version, expected: current)) {
                try codec.decode(data)
            }
        }
    }

    @Test func checksTheVersionBeforeTheMessage() {
        // A future version may change the messages entirely; it must still be recognized as another version.
        let future = EggscapeCore.protocolVersion + 1
        let messages = [#"{"type":"teleport","to":"finish"}"#, #"{"kind":"progress"}"#, #""rocket""#]
        for message in messages {
            let data = Data(#"{"version":\#(future),"sender":"ben","message":\#(message)}"#.utf8)
            #expect(throws: NetCodecError.versionMismatch(received: future, expected: EggscapeCore.protocolVersion)) {
                try codec.decode(data)
            }
        }
    }

    @Test func reportsUnknownMessageTypes() {
        #expect(throws: NetCodecError.unknownMessageType("emote")) {
            try codec.decode(envelope(#"{"type":"emote","emoji":"🥚"}"#))
        }
    }

    @Test func ignoresFieldsItDoesNotKnow() throws {
        // Lets a later build add optional fields without a new protocol version.
        let data = Data(#"""
        {"version":\#(EggscapeCore.protocolVersion),"sender":"anna","region":"eu",\#
        "message":{"type":"progress","meters":12.5,"eggsLeft":2,"heartRate":120}}
        """#.utf8)
        #expect(try codec.decode(data) == NetEnvelope(sender: "anna", message: .progress(meters: 12.5, eggsLeft: 2)))
    }

    @Test func rejectsDataThatIsNoEnvelope() {
        let documents = [
            "",
            "not json",
            "[1,2,3]",
            "{}",
            "null",
            #"{"version":"1","sender":"anna","message":{"type":"ready","isReady":true}}"#,
            #"{"version":1.5,"sender":"anna","message":{"type":"ready","isReady":true}}"#,
            #"{"version":\#(EggscapeCore.protocolVersion),"message":{"type":"ready","isReady":true}}"#,
            #"{"version":\#(EggscapeCore.protocolVersion),"sender":"anna"}"#,
            #"{"version":\#(EggscapeCore.protocolVersion),"sender":"anna","message":{"type":"progress","meters":1"#,
        ]
        for document in documents {
            expectInvalidData(Data(document.utf8))
        }
    }

    @Test(arguments: malformedMessages)
    func rejectsMalformedMessages(_ message: String) {
        expectInvalidData(envelope(message))
    }

    @Test func rejectsRandomBytes() {
        var rng = SplitMix64(seed: 404)
        for _ in 0 ..< 200 {
            let bytes = (0 ..< rng.index(below: 120)).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
            expectInvalidData(Data(bytes))
        }
    }

    @Test func refusesNumbersJSONCannotHold() {
        for message in [NetMessage.progress(meters: .nan, eggsLeft: 2), .ping(id: 1, sentAt: .infinity)] {
            let error = #expect(throws: NetCodecError.self) {
                try codec.encode(message, from: "anna")
            }
            if case .unencodable? = error {} else {
                Issue.record("expected unencodable, got \(String(describing: error))")
            }
        }
    }

    @Test func streamsGoUnreliable() {
        let unreliable = Set(everyMessage.filter { $0.delivery == .unreliable }.map(\.kind))
        #expect(unreliable == [.progress, .ping, .pong])
    }

    @Test func onlyTheHostAnnouncesAndStarts() {
        let hostOnly = Set(everyMessage.filter(\.isHostOnly).map(\.kind))
        #expect(hostOnly == [.lobbyState, .setSettings, .startRace, .results, .pong])
    }
}
