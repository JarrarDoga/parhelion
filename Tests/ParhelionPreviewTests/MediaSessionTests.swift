import Foundation
import Testing

@testable import ParhelionPreview

@Suite("Media session messages")
struct MediaSessionTests {
    @Test("A now-playing state crosses the channel")
    func nowPlayingRoundTrip() throws {
        let (appEnd, hostEnd) = try PreviewChannel.pair()
        let state = PreviewNowPlaying(
            state: "playing", title: "Song", artist: "Artist", albumTitle: "Album",
            trackNumber: 3, duration: 180, elapsed: 12.5, rate: 1,
            enabledCommands: ["play", "pause", "nextTrack"], hasItem: true)
        try appEnd.send(.nowPlaying(state))
        #expect(try hostEnd.receiveAppMessage(timeout: 1) == .nowPlaying(state))
    }

    @Test("Remote commands cross the channel")
    func remoteCommandRoundTrip() throws {
        let (appEnd, hostEnd) = try PreviewChannel.pair()
        let commands: [PreviewRemoteCommand] = [
            .play, .pause, .togglePlayPause, .stop, .nextTrack, .previousTrack,
            .seek(offset: -5.5), .setPosition(seconds: 42),
        ]
        for command in commands { try hostEnd.send(.remoteCommand(command)) }
        for command in commands {
            #expect(try appEnd.receiveHostMessage(timeout: 1) == .remoteCommand(command))
        }
    }

    @Test("The media session is a capability that hosts can use")
    func capability() {
        #expect(PreviewCapability.all.contains(PreviewCapability.mediaSession))
    }

    @Test("The bridge sends the state published before a session connected")
    func bridgeSendsEarlyState() {
        let bridge = MediaSessionBridge()
        bridge.publish(PreviewNowPlaying(state: "paused", title: "Early", hasItem: true))
        let received = Received()
        bridge.connect { received.append($0) }
        bridge.publish(PreviewNowPlaying(state: "playing", title: "Late", hasItem: true))
        #expect(received.titles == ["Early", "Late"])
        bridge.connect(send: nil)
        bridge.publish(PreviewNowPlaying(title: "After"))
        #expect(received.titles == ["Early", "Late"])
        #expect(bridge.current?.title == "After")
    }

    @Test("The bridge hands a command to the receiver, and says when there is none")
    func bridgeDelivers() {
        let bridge = MediaSessionBridge()
        #expect(!bridge.deliver(.play))
        let received = Received()
        bridge.setReceiver { received.append($0) }
        #expect(bridge.deliver(.nextTrack))
        #expect(received.commands == [.nextTrack])
    }
}

private final class Received: @unchecked Sendable {
    private let lock = NSLock()
    private var states: [PreviewNowPlaying] = []
    private var received: [PreviewRemoteCommand] = []

    func append(_ state: PreviewNowPlaying) { lock.withLock { states.append(state) } }
    func append(_ command: PreviewRemoteCommand) { lock.withLock { received.append(command) } }
    var titles: [String?] { lock.withLock { states.map(\.title) } }
    var commands: [PreviewRemoteCommand] { lock.withLock { received } }
}
