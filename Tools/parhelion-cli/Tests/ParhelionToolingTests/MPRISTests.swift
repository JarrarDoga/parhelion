import Foundation
import ParhelionPreview
import Testing

@testable import ParhelionTooling

private final class Commands: @unchecked Sendable {
    private let lock = NSLock()
    private var received: [PreviewRemoteCommand] = []
    func append(_ command: PreviewRemoteCommand) { lock.withLock { received.append(command) } }
    var all: [PreviewRemoteCommand] { lock.withLock { received } }
}

private let playing = PreviewNowPlaying(
    state: "playing", title: "Song", artist: "Artist", albumTitle: "Album", trackNumber: 2,
    duration: 200, elapsed: 10, rate: 1,
    enabledCommands: ["play", "pause", "nextTrack", "changePlaybackPosition"], hasItem: true)

private func call(
    _ interface: String, _ member: String, _ body: [DBusValue] = [], serial: UInt32 = 7
) -> DBusMessage {
    var message = DBusMessage(
        kind: .methodCall, path: MPRISPlayer.objectPath, interface: interface, member: member,
        destination: "org.mpris.MediaPlayer2.test", body: body)
    message.serial = serial
    message.sender = ":1.9"
    return message
}

@Suite("D-Bus wire format")
struct DBusWireTests {
    @Test("A message with nested values decodes to what was encoded")
    func roundTrip() throws {
        var message = DBusMessage(
            kind: .signal, path: "/org/mpris/MediaPlayer2",
            interface: "org.freedesktop.DBus.Properties", member: "PropertiesChanged",
            body: [
                .string("org.mpris.MediaPlayer2.Player"),
                .dictionary([
                    ("Rate", .double(1.5)),
                    ("Flag", .bool(true)),
                    ("Length", .int64(-5)),
                    ("Artist", .stringArray(["A", "B"])),
                    ("Nested", .dictionary([("n", .uint32(3)), ("b", .byte(9))])),
                ]),
                .stringArray([]),
                .structure([.int32(-1), .string("x"), .uint64(1 << 40)]),
            ])
        message.destination = ":1.5"
        let decoded = try DBusMessage.decode(message.encoded(serial: 42))
        #expect(decoded.serial == 42)
        #expect(decoded.kind == .signal && decoded.member == "PropertiesChanged")
        #expect(decoded.path == message.path && decoded.interface == message.interface)
        #expect(decoded.destination == ":1.5")
        #expect(decoded.body == message.body)
    }

    @Test("Replies carry the serial of the call and are addressed to its sender")
    func replyFields() throws {
        let reply = call("a.b", "C", serial: 11).reply([.string("ok")])
        let decoded = try DBusMessage.decode(reply.encoded(serial: 1))
        #expect(decoded.kind == .methodReturn && decoded.replySerial == 11)
        #expect(decoded.destination == ":1.9" && decoded.body == [.string("ok")])
    }

    @Test("The length of a message is found from its first 16 bytes")
    func messageLength() {
        let bytes = call("a.b", "C", [.string("hello"), .int64(1)]).encoded(serial: 3)
        #expect(DBusMessage.length(ofMessageStartingWith: Array(bytes.prefix(16))) == bytes.count)
    }

    @Test("A body is aligned for its types, even after a short string")
    func bodyAlignment() throws {
        // A string of one byte leaves the offset at 9, so the x must pad to 16.
        var writer = DBusWriter()
        writer.append(DBusValue.string("a"))
        writer.append(DBusValue.int64(1))
        #expect(writer.bytes.count == 4 + 2 + 2 + 8)
        var reader = DBusReader(writer.bytes)
        #expect(try reader.readBody(signature: "sx") == [.string("a"), .int64(1)])
    }

    @Test("Truncated or unknown input is an error, not a crash")
    func malformed() {
        let bytes = call("a.b", "C", [.string("hello")]).encoded(serial: 3)
        #expect(throws: DBusError.self) { try DBusMessage.decode(Array(bytes.prefix(20))) }
        #expect(throws: DBusError.self) { try DBusMessage.decode([UInt8](repeating: 0, count: 32)) }
    }

    @Test("A D-Bus address value is unescaped")
    func addressEscapes() {
        #expect(DBusConnection.unescape("/tmp/a%20b") == "/tmp/a b")
        #expect(DBusConnection.unescape("/plain") == "/plain")
    }
}

@Suite("MPRIS player")
struct MPRISPlayerTests {
    private func makePlayer(_ commands: Commands = Commands()) -> MPRISPlayer {
        let player = MPRISPlayer(identity: "Test App") { commands.append($0) }
        _ = player.update(playing, at: 100)
        return player
    }

    private func get(
        _ player: MPRISPlayer, _ name: String, at now: TimeInterval = 100
    )
        -> DBusValue?
    {
        let reply = player.reply(
            to: call(
                "org.freedesktop.DBus.Properties", "Get",
                [.string(MPRISPlayer.playerInterface), .string(name)]),
            at: now)
        guard case .variant(let value)? = reply?.body.first else { return nil }
        return value
    }

    @Test("The playback status and the controls follow the app's state")
    func status() {
        let player = makePlayer()
        #expect(get(player, "PlaybackStatus") == .string("Playing"))
        #expect(get(player, "CanPause") == .bool(true))
        #expect(get(player, "CanGoNext") == .bool(true))
        #expect(get(player, "CanGoPrevious") == .bool(false))
        #expect(get(player, "CanSeek") == .bool(true))
        _ = player.update(PreviewNowPlaying(state: "stopped"), at: 101)
        #expect(get(player, "PlaybackStatus") == .string("Stopped"))
        #expect(get(player, "CanPause") == .bool(false))
    }

    @Test("The metadata has the title, the artists, and the length in microseconds")
    func metadata() {
        let player = makePlayer()
        guard case .array("{sv}", let entries)? = get(player, "Metadata") else {
            Issue.record("Expected a dictionary")
            return
        }
        let pairs = Dictionary(
            uniqueKeysWithValues: entries.compactMap { entry -> (String, DBusValue)? in
                guard case .dictEntry(.string(let key), .variant(let value)) = entry else {
                    return nil
                }
                return (key, value)
            })
        #expect(pairs["xesam:title"] == .string("Song"))
        #expect(pairs["xesam:artist"] == .stringArray(["Artist"]))
        #expect(pairs["xesam:album"] == .string("Album"))
        #expect(pairs["xesam:trackNumber"] == .int32(2))
        #expect(pairs["mpris:length"] == .int64(200_000_000))
        #expect(pairs["mpris:trackid"] == .objectPath(MPRISPlayer.currentTrack))
    }

    @Test("Without an item, the metadata names no track")
    func noItem() {
        let player = makePlayer()
        _ = player.update(PreviewNowPlaying(state: "stopped"), at: 101)
        #expect(
            get(player, "Metadata")
                == .dictionary([("mpris:trackid", .objectPath(MPRISPlayer.noTrack))]))
    }

    @Test("The position moves while playing, and stops at the length")
    func position() {
        let player = makePlayer()
        #expect(get(player, "Position", at: 100) == .int64(10_000_000))
        #expect(get(player, "Position", at: 104.5) == .int64(14_500_000))
        #expect(get(player, "Position", at: 10_000) == .int64(200_000_000))
        var paused = playing
        paused.state = "paused"
        _ = player.update(paused, at: 200)
        #expect(get(player, "Position", at: 260) == .int64(10_000_000))
    }

    @Test("An update names the properties that changed, and a jump is a seek")
    func changes() {
        let player = makePlayer()
        var next = playing
        next.title = "Other"
        next.elapsed = 10.5
        let first = player.update(next, at: 100.5)
        #expect(first.changed.map(\.0) == ["Metadata"])
        #expect(first.seeked == nil)

        var paused = next
        paused.state = "paused"
        paused.elapsed = 11
        let second = player.update(paused, at: 101)
        #expect(second.changed.map(\.0) == ["PlaybackStatus"])

        var jumped = paused
        jumped.elapsed = 150
        #expect(player.update(jumped, at: 102).seeked == 150_000_000)
        #expect(player.update(jumped, at: 103).changed.isEmpty)
    }

    @Test("Methods reach the app as commands")
    func methods() {
        let commands = Commands()
        let player = makePlayer(commands)
        for member in ["Play", "Pause", "PlayPause", "Stop", "Next", "Previous"] {
            let reply = player.reply(to: call(MPRISPlayer.playerInterface, member))
            #expect(reply?.kind == .methodReturn)
        }
        _ = player.reply(to: call(MPRISPlayer.playerInterface, "Seek", [.int64(-2_500_000)]))
        _ = player.reply(
            to: call(
                MPRISPlayer.playerInterface, "SetPosition",
                [.objectPath(MPRISPlayer.currentTrack), .int64(30_000_000)]))
        // A position for another track is stale.
        _ = player.reply(
            to: call(
                MPRISPlayer.playerInterface, "SetPosition",
                [.objectPath("/other"), .int64(99_000_000)]))
        #expect(
            commands.all == [
                .play, .pause, .togglePlayPause, .stop, .nextTrack, .previousTrack,
                .seek(offset: -2.5), .setPosition(seconds: 30),
            ])
    }

    @Test("A call that wants no reply gets none, and an unknown method gets an error")
    func replies() {
        let player = makePlayer()
        var quiet = call(MPRISPlayer.playerInterface, "Pause")
        quiet.noReplyExpected = true
        #expect(player.reply(to: quiet) == nil)
        let unknown = player.reply(to: call(MPRISPlayer.playerInterface, "Explode"))
        #expect(unknown?.kind == .error)
        #expect(unknown?.errorName == "org.freedesktop.DBus.Error.UnknownMethod")
        let missing = player.reply(
            to: call(
                "org.freedesktop.DBus.Properties", "Get",
                [.string(MPRISPlayer.playerInterface), .string("Nope")]))
        #expect(missing?.errorName == "org.freedesktop.DBus.Error.UnknownProperty")
    }

    @Test("GetAll lists every property of the interface, and introspection is XML")
    func getAll() throws {
        let player = makePlayer()
        let reply = player.reply(
            to: call(
                "org.freedesktop.DBus.Properties", "GetAll", [.string(MPRISPlayer.rootInterface)]))
        guard case .array(_, let entries)? = reply?.body.first else {
            Issue.record("Expected a dictionary")
            return
        }
        #expect(entries.count == 6)
        let xml = player.reply(to: call("org.freedesktop.DBus.Introspectable", "Introspect"))
        #expect(xml?.body.first?.stringValue?.contains("org.mpris.MediaPlayer2.Player") == true)
    }
}

private func dbusDaemonPath() -> String? {
    ["/usr/bin/dbus-daemon", "/bin/dbus-daemon"].first {
        FileManager.default.isExecutableFile(atPath: $0)
    }
}

@Suite("MPRIS on a private bus")
struct MPRISBusTests {
    /// A session bus of this test's own, so nothing touches the desktop's.
    private final class PrivateBus {
        let process = Process()
        let address: String

        init?() {
            guard let daemon = dbusDaemonPath() else { return nil }
            process.executableURL = URL(fileURLWithPath: daemon)
            process.arguments = ["--session", "--nofork", "--print-address"]
            let pipe = Pipe()
            process.standardOutput = pipe
            guard (try? process.run()) != nil else { return nil }
            var line = Data()
            while !line.contains(10) {
                let chunk = pipe.fileHandleForReading.availableData
                if chunk.isEmpty { return nil }
                line += chunk
            }
            address =
                String(decoding: line, as: UTF8.self).split(separator: "\n").first.map(String.init)
                ?? ""
        }

        deinit {
            // The daemon does not always stop for SIGTERM while a client is
            // still connected.
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }
    }

    @Test(
        "A client on the bus reads the player and controls it",
        .enabled(if: dbusDaemonPath() != nil))
    func clientControlsPlayer() throws {
        let bus = try #require(PrivateBus())
        let commands = Commands()
        let service = MPRISService(
            identity: "Bus Test", busAddress: bus.address, onCommand: { commands.append($0) })
        service.update(playing)
        let name = try #require(service.busName)
        defer { service.stop() }

        nonisolated(unsafe) var signalCount = 0
        let client = try DBusConnection.connect(address: bus.address) { message, _ in
            if message.member == "PropertiesChanged" {
                signalCount += 1
            }
        }
        _ = try client.call(
            DBusMessage(
                kind: .methodCall, path: "/org/freedesktop/DBus", interface: "org.freedesktop.DBus",
                member: "AddMatch", destination: "org.freedesktop.DBus",
                body: [.string("type='signal',path='/org/mpris/MediaPlayer2'")]))
        defer { client.close() }

        let status = try client.call(
            DBusMessage(
                kind: .methodCall, path: MPRISPlayer.objectPath,
                interface: "org.freedesktop.DBus.Properties", member: "Get",
                destination: name,
                body: [.string(MPRISPlayer.playerInterface), .string("PlaybackStatus")]))
        #expect(status.body == [.variant(.string("Playing"))])

        _ = try client.call(
            DBusMessage(
                kind: .methodCall, path: MPRISPlayer.objectPath,
                interface: MPRISPlayer.playerInterface, member: "Pause", destination: name))
        #expect(commands.all == [.pause])

        // The player tells listeners about a change.
        var paused = playing
        paused.state = "paused"
        service.update(paused)
        let deadline = Date().addingTimeInterval(5)
        while signalCount == 0, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        #expect(signalCount >= 1)
    }

    @Test("Without a bus, the service does nothing and does not fail")
    func noBus() {
        let service = MPRISService(
            identity: "No Bus", busAddress: "unix:path=/nonexistent/bus", onCommand: { _ in })
        service.update(playing)
        #expect(service.busName == nil)
        service.stop()
    }
}
