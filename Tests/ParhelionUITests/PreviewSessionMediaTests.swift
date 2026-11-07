import Foundation
import ParhelionPreview
import Testing

@testable import ParhelionUI

private let screen = Device(
    name: "Test",
    screenSize: CGSize(width: 60, height: 60),
    safeAreaInsets: EdgeInsets()
)

@MainActor
@Suite("Preview session with a media session")
struct PreviewSessionMediaTests {
    @Test("A welcomed session carries now-playing state out and remote commands in")
    func carriesMedia() throws {
        let commands = CommandLog()
        let bridge = MediaSessionBridge()
        bridge.setReceiver { commands.append($0) }
        bridge.publish(
            PreviewNowPlaying(state: "playing", title: "Song", hasItem: true))

        let (appEnd, hostEnd) = try PreviewChannel.pair()
        try hostEnd.send(.welcome(PreviewWelcome(capabilities: [PreviewCapability.mediaSession])))
        try hostEnd.send(.remoteCommand(.pause))
        try hostEnd.send(.remoteCommand(.setPosition(seconds: 9)))
        try hostEnd.send(.close)
        try PreviewSession(
            host: ViewHost(Text("Hello"), device: screen), channel: appEnd, scale: 1,
            appName: "Media", mediaBridge: bridge
        ).run()

        var titles: [String?] = []
        while let message = try hostEnd.receiveAppMessage(timeout: 0.2) {
            if case .nowPlaying(let state) = message { titles.append(state.title) }
        }
        #expect(titles == ["Song"])
        #expect(commands.all == [.pause, .setPosition(seconds: 9)])
    }

    @Test("A host that did not welcome the media session gets none of it")
    func unwelcomed() throws {
        let bridge = MediaSessionBridge()
        let (appEnd, hostEnd) = try PreviewChannel.pair()
        try hostEnd.send(.welcome(PreviewWelcome(capabilities: [PreviewCapability.hostClock])))
        try hostEnd.send(.close)
        try PreviewSession(
            host: ViewHost(Text("Hello"), device: screen), channel: appEnd, scale: 1,
            appName: "Media", mediaBridge: bridge
        ).run()
        bridge.publish(PreviewNowPlaying(title: "Quiet"))
        while let message = try hostEnd.receiveAppMessage(timeout: 0.2) {
            if case .nowPlaying = message { Issue.record("Sent now-playing state unasked") }
        }
    }
}

private final class CommandLog: @unchecked Sendable {
    private let lock = NSLock()
    private var commands: [PreviewRemoteCommand] = []
    func append(_ command: PreviewRemoteCommand) { lock.withLock { commands.append(command) } }
    var all: [PreviewRemoteCommand] { lock.withLock { commands } }
}
