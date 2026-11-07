import Foundation
import ParhelionPreview

#if canImport(Glibc)
import Glibc

// Shows what an app plays to the desktop, as an MPRIS player on the session
// bus, and carries the desktop's controls back to the app. The KDE media
// widget and `playerctl` both speak MPRIS. See
// docs/adr/0017-mediaplayer-mpris.md.

/// The MPRIS player for one app: its properties, from the state the app
/// reported, and its answers to method calls. It holds no connection, so
/// tests drive it directly.
public final class MPRISPlayer: @unchecked Sendable {
    public static let rootInterface = "org.mpris.MediaPlayer2"
    public static let playerInterface = "org.mpris.MediaPlayer2.Player"
    public static let objectPath = "/org/mpris/MediaPlayer2"
    static let noTrack = "/org/mpris/MediaPlayer2/TrackList/NoTrack"
    static let currentTrack = "/org/parhelion/track/current"

    private let lock = NSLock()
    private let identity: String
    private let onCommand: @Sendable (PreviewRemoteCommand) -> Void
    private var state = PreviewNowPlaying()
    /// When `state` arrived, on the monotonic clock.
    private var receivedAt: TimeInterval = 0

    public init(identity: String, onCommand: @escaping @Sendable (PreviewRemoteCommand) -> Void) {
        self.identity = identity
        self.onCommand = onCommand
    }

    // MARK: State

    /// Takes a new state from the app. Returns the player properties that
    /// changed, for a `PropertiesChanged` signal, and the position in
    /// microseconds if the app moved it other than by playing, for `Seeked`.
    public func update(
        _ new: PreviewNowPlaying, at now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> (changed: [(String, DBusValue)], seeked: Int64?) {
        lock.lock()
        defer { lock.unlock() }
        let before = properties(at: now)
        let hadItem = state.hasItem
        let predicted = position(at: now)
        state = new
        receivedAt = now
        let after = properties(at: now)
        let changed = after.filter { name, value in
            before.first { $0.0 == name }?.1 != value
        }
        var seeked: Int64?
        if hadItem, new.hasItem, abs(position(at: now) - predicted) > 1, new.elapsed != nil {
            seeked = Int64(position(at: now) * 1_000_000)
        }
        return (changed, seeked)
    }

    /// How far into the item playback is, in seconds.
    private func position(at now: TimeInterval) -> Double {
        let base = state.elapsed ?? 0
        guard state.state == "playing" else { return min(base, state.duration ?? base) }
        let moved = base + max(now - receivedAt, 0) * state.rate
        return min(max(moved, 0), state.duration ?? moved)
    }

    private var status: String {
        switch state.state {
        case "playing": "Playing"
        case "paused": "Paused"
        default: "Stopped"
        }
    }

    private func can(_ names: String...) -> Bool {
        names.contains { state.enabledCommands.contains($0) }
    }

    private var metadata: DBusValue {
        guard state.hasItem else {
            return .dictionary([("mpris:trackid", .objectPath(Self.noTrack))])
        }
        var pairs: [(String, DBusValue)] = [("mpris:trackid", .objectPath(Self.currentTrack))]
        if let duration = state.duration {
            pairs.append(("mpris:length", .int64(Int64(duration * 1_000_000))))
        }
        if let title = state.title { pairs.append(("xesam:title", .string(title))) }
        if let artist = state.artist { pairs.append(("xesam:artist", .stringArray([artist]))) }
        if let album = state.albumTitle { pairs.append(("xesam:album", .string(album))) }
        if let albumArtist = state.albumArtist {
            pairs.append(("xesam:albumArtist", .stringArray([albumArtist])))
        }
        if let number = state.trackNumber {
            pairs.append(("xesam:trackNumber", .int32(Int32(number))))
        }
        return .dictionary(pairs)
    }

    /// The properties of `org.mpris.MediaPlayer2.Player`, except `Position`,
    /// which the spec leaves out of change signals.
    private func properties(at now: TimeInterval) -> [(String, DBusValue)] {
        [
            ("PlaybackStatus", .string(status)),
            ("LoopStatus", .string("None")),
            ("Rate", .double(state.rate)),
            ("Shuffle", .bool(false)),
            ("Metadata", metadata),
            ("Volume", .double(1)),
            ("MinimumRate", .double(1)),
            ("MaximumRate", .double(1)),
            ("CanGoNext", .bool(can(PreviewRemoteCommand.Name.nextTrack))),
            ("CanGoPrevious", .bool(can(PreviewRemoteCommand.Name.previousTrack))),
            (
                "CanPlay",
                .bool(
                    can(PreviewRemoteCommand.Name.play, PreviewRemoteCommand.Name.togglePlayPause))
            ),
            (
                "CanPause",
                .bool(
                    can(PreviewRemoteCommand.Name.pause, PreviewRemoteCommand.Name.togglePlayPause))
            ),
            (
                "CanSeek",
                .bool(
                    can(
                        PreviewRemoteCommand.Name.changePlaybackPosition,
                        PreviewRemoteCommand.Name.skipForward,
                        PreviewRemoteCommand.Name.skipBackward))
            ),
            ("CanControl", .bool(true)),
        ]
    }

    private var rootProperties: [(String, DBusValue)] {
        [
            ("CanQuit", .bool(false)),
            ("CanRaise", .bool(false)),
            ("HasTrackList", .bool(false)),
            ("Identity", .string(identity)),
            ("SupportedUriSchemes", .stringArray([])),
            ("SupportedMimeTypes", .stringArray([])),
        ]
    }

    /// The value of one property of an interface, or `nil` if there is none.
    func property(
        _ interface: String, _ name: String, at now: TimeInterval
    ) -> DBusValue? {
        lock.lock()
        defer { lock.unlock() }
        switch interface {
        case Self.rootInterface: return rootProperties.first { $0.0 == name }?.1
        case Self.playerInterface:
            if name == "Position" { return .int64(Int64(position(at: now) * 1_000_000)) }
            return properties(at: now).first { $0.0 == name }?.1
        default: return nil
        }
    }

    private func allProperties(_ interface: String, at now: TimeInterval) -> [(String, DBusValue)]?
    {
        lock.lock()
        defer { lock.unlock() }
        switch interface {
        case Self.rootInterface: return rootProperties
        case Self.playerInterface:
            return properties(at: now) + [
                ("Position", .int64(Int64(position(at: now) * 1_000_000)))
            ]
        default: return nil
        }
    }

    // MARK: Calls

    /// The reply to a method call, or `nil` when the call wants none.
    public func reply(
        to call: DBusMessage, at now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> DBusMessage? {
        guard call.kind == .methodCall else { return nil }
        let reply = answer(call, at: now)
        return call.noReplyExpected ? nil : reply
    }

    private func answer(_ call: DBusMessage, at now: TimeInterval) -> DBusMessage {
        func unknown() -> DBusMessage {
            call.error(
                "org.freedesktop.DBus.Error.UnknownMethod",
                "No method \(call.interface ?? "") \(call.member ?? "")")
        }
        switch (call.interface, call.member) {
        case ("org.freedesktop.DBus.Peer", "Ping"):
            return call.reply()
        case ("org.freedesktop.DBus.Peer", "GetMachineId"):
            return call.reply([.string(String(repeating: "0", count: 32))])
        case ("org.freedesktop.DBus.Introspectable", "Introspect"):
            return call.reply([.string(Self.introspection)])
        case ("org.freedesktop.DBus.Properties", "Get"):
            guard call.body.count == 2, let interface = call.body[0].stringValue,
                let name = call.body[1].stringValue
            else { return call.error("org.freedesktop.DBus.Error.InvalidArgs", "Get takes ss") }
            guard let value = property(interface, name, at: now) else {
                return call.error(
                    "org.freedesktop.DBus.Error.UnknownProperty", "No property \(interface) \(name)"
                )
            }
            return call.reply([.variant(value)])
        case ("org.freedesktop.DBus.Properties", "GetAll"):
            guard let interface = call.body.first?.stringValue else {
                return call.error("org.freedesktop.DBus.Error.InvalidArgs", "GetAll takes s")
            }
            return call.reply([.dictionary(allProperties(interface, at: now) ?? [])])
        case ("org.freedesktop.DBus.Properties", "Set"):
            // Volume, rate, loop, and shuffle are not the app's to follow.
            return call.reply()
        case (Self.rootInterface?, "Raise"), (Self.rootInterface?, "Quit"):
            return call.reply()
        case (Self.playerInterface?, let member?):
            switch member {
            case "Play": onCommand(.play)
            case "Pause": onCommand(.pause)
            case "PlayPause": onCommand(.togglePlayPause)
            case "Stop": onCommand(.stop)
            case "Next": onCommand(.nextTrack)
            case "Previous": onCommand(.previousTrack)
            case "Seek":
                guard let microseconds = call.body.first?.int64Value else {
                    return call.error("org.freedesktop.DBus.Error.InvalidArgs", "Seek takes x")
                }
                onCommand(.seek(offset: Double(microseconds) / 1_000_000))
            case "SetPosition":
                guard call.body.count == 2, let microseconds = call.body[1].int64Value else {
                    return call.error(
                        "org.freedesktop.DBus.Error.InvalidArgs", "SetPosition takes ox")
                }
                // A position for a track that is no longer current is ignored.
                if call.body[0].stringValue == Self.currentTrack {
                    onCommand(.setPosition(seconds: Double(microseconds) / 1_000_000))
                }
            case "OpenUri": break
            default: return unknown()
            }
            return call.reply()
        default:
            return unknown()
        }
    }

    // MARK: Signals

    func propertiesChanged(_ changed: [(String, DBusValue)]) -> DBusMessage {
        DBusMessage(
            kind: .signal, path: Self.objectPath, interface: "org.freedesktop.DBus.Properties",
            member: "PropertiesChanged",
            body: [
                .string(Self.playerInterface), .dictionary(changed), .stringArray([]),
            ])
    }

    func seeked(_ microseconds: Int64) -> DBusMessage {
        DBusMessage(
            kind: .signal, path: Self.objectPath, interface: Self.playerInterface,
            member: "Seeked", body: [.int64(microseconds)])
    }

    static let introspection = """
        <!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN" \
        "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
        <node>
         <interface name="org.freedesktop.DBus.Introspectable">
          <method name="Introspect"><arg name="xml" type="s" direction="out"/></method>
         </interface>
         <interface name="org.freedesktop.DBus.Peer">
          <method name="Ping"/>
          <method name="GetMachineId"><arg name="machine_uuid" type="s" direction="out"/></method>
         </interface>
         <interface name="org.freedesktop.DBus.Properties">
          <method name="Get">
           <arg name="interface_name" type="s" direction="in"/>
           <arg name="property_name" type="s" direction="in"/>
           <arg name="value" type="v" direction="out"/>
          </method>
          <method name="GetAll">
           <arg name="interface_name" type="s" direction="in"/>
           <arg name="properties" type="a{sv}" direction="out"/>
          </method>
          <method name="Set">
           <arg name="interface_name" type="s" direction="in"/>
           <arg name="property_name" type="s" direction="in"/>
           <arg name="value" type="v" direction="in"/>
          </method>
          <signal name="PropertiesChanged">
           <arg name="interface_name" type="s"/>
           <arg name="changed_properties" type="a{sv}"/>
           <arg name="invalidated_properties" type="as"/>
          </signal>
         </interface>
         <interface name="org.mpris.MediaPlayer2">
          <method name="Raise"/>
          <method name="Quit"/>
          <property name="CanQuit" type="b" access="read"/>
          <property name="CanRaise" type="b" access="read"/>
          <property name="HasTrackList" type="b" access="read"/>
          <property name="Identity" type="s" access="read"/>
          <property name="SupportedUriSchemes" type="as" access="read"/>
          <property name="SupportedMimeTypes" type="as" access="read"/>
         </interface>
         <interface name="org.mpris.MediaPlayer2.Player">
          <method name="Next"/>
          <method name="Previous"/>
          <method name="Pause"/>
          <method name="PlayPause"/>
          <method name="Stop"/>
          <method name="Play"/>
          <method name="Seek"><arg name="Offset" type="x" direction="in"/></method>
          <method name="SetPosition">
           <arg name="TrackId" type="o" direction="in"/>
           <arg name="Position" type="x" direction="in"/>
          </method>
          <method name="OpenUri"><arg name="Uri" type="s" direction="in"/></method>
          <signal name="Seeked"><arg name="Position" type="x"/></signal>
          <property name="PlaybackStatus" type="s" access="read"/>
          <property name="LoopStatus" type="s" access="readwrite"/>
          <property name="Rate" type="d" access="readwrite"/>
          <property name="Shuffle" type="b" access="readwrite"/>
          <property name="Metadata" type="a{sv}" access="read"/>
          <property name="Volume" type="d" access="readwrite"/>
          <property name="Position" type="x" access="read"/>
          <property name="MinimumRate" type="d" access="read"/>
          <property name="MaximumRate" type="d" access="read"/>
          <property name="CanGoNext" type="b" access="read"/>
          <property name="CanGoPrevious" type="b" access="read"/>
          <property name="CanPlay" type="b" access="read"/>
          <property name="CanPause" type="b" access="read"/>
          <property name="CanSeek" type="b" access="read"/>
          <property name="CanControl" type="b" access="read"/>
         </interface>
        </node>
        """
}

/// An app's MPRIS player on the session bus, from the first state the app
/// reports until the service stops.
///
/// The player is published lazily, so an app that never sets now-playing
/// info never touches the bus. Without a session bus, the service logs the
/// reason once and does nothing: the preview works the same, only the
/// desktop does not see it.
public final class MPRISService: @unchecked Sendable {
    private let player: MPRISPlayer
    private let busAddress: String?
    private let log: @Sendable (String) -> Void
    private let lock = NSLock()
    private var connection: DBusConnection?
    private var failed = false
    private var stopped = false
    /// The well-known name the player owns, once it has one.
    public private(set) var busName: String?

    /// - Parameters:
    ///   - identity: The player's name for people, such as the app's name.
    ///   - busAddress: A D-Bus address to use instead of the session bus, for
    ///     tests.
    ///   - onCommand: Called on a bus thread for each control the desktop
    ///     uses.
    public init(
        identity: String, busAddress: String? = nil,
        log: @escaping @Sendable (String) -> Void = { _ in },
        onCommand: @escaping @Sendable (PreviewRemoteCommand) -> Void
    ) {
        player = MPRISPlayer(identity: identity, onCommand: onCommand)
        self.busAddress = busAddress
        self.log = log
    }

    deinit { stop() }

    /// Shows the app's new state to the desktop.
    public func update(_ state: PreviewNowPlaying) {
        guard let connection = ensureConnected() else { return }
        let (changed, seeked) = player.update(state)
        if !changed.isEmpty { _ = try? connection.send(player.propertiesChanged(changed)) }
        if let seeked { _ = try? connection.send(player.seeked(seeked)) }
    }

    /// Takes the player off the bus.
    public func stop() {
        let connection = lock.withLock {
            stopped = true
            defer { self.connection = nil }
            return self.connection
        }
        connection?.close()
    }

    private func ensureConnected() -> DBusConnection? {
        lock.lock()
        defer { lock.unlock() }
        if let connection { return connection }
        guard !failed, !stopped else { return nil }
        let player = self.player
        let handler: @Sendable (DBusMessage, DBusConnection) -> Void = { message, connection in
            if let reply = player.reply(to: message) { _ = try? connection.send(reply) }
        }
        do {
            let new: DBusConnection
            if let busAddress {
                new = try DBusConnection.connect(address: busAddress, handler: handler)
            } else {
                new = try DBusConnection.connectToSessionBus(handler: handler)
            }
            let name = "org.mpris.MediaPlayer2.parhelion.instance\(getpid())"
            // DO_NOT_QUEUE (4): fail instead of waiting for the name.
            let reply = try new.call(
                DBusMessage(
                    kind: .methodCall, path: "/org/freedesktop/DBus",
                    interface: "org.freedesktop.DBus", member: "RequestName",
                    destination: "org.freedesktop.DBus",
                    body: [.string(name), .uint32(4)]))
            guard case .uint32(1)? = reply.body.first else {
                new.close()
                throw DBusError.connectionFailed("the bus did not give the name \(name)")
            }
            busName = name
            connection = new
            log("publishing \(name) on the session bus")
            return new
        } catch {
            failed = true
            log("the desktop's media controls are not available: \(error)")
            return nil
        }
    }
}
#endif
