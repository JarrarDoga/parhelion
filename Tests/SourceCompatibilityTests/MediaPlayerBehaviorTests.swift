// What the MediaPlayer shim does, beyond compiling: the now-playing info
// reaches the preview session's bridge, and a command from the desktop
// reaches the targets an app added.

import Foundation
import ParhelionPreview
import Testing

@testable import MediaPlayer

@Suite("MediaPlayer on the preview session")
struct MediaPlayerBehaviorTests {
    private final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        func add(_ line: String) { lock.withLock { lines.append(line) } }
        var all: [String] { lock.withLock { lines } }
    }

    /// Fresh centers on a bridge of their own, so no other test can reach them.
    private struct Setup {
        let bridge = MediaSessionBridge()
        let center: MPNowPlayingInfoCenter
        let commands: MPRemoteCommandCenter

        init() { (center, commands) = MPNowPlayingInfoCenter.isolatedPair(bridge: bridge) }
    }

    @Test("Now-playing info becomes the state the host shows")
    func publishesInfo() {
        let setup = Setup()
        let center = setup.center
        let bridge = setup.bridge
        center.nowPlayingInfo = [
            MPMediaItemPropertyTitle: "Song",
            MPMediaItemPropertyArtist: "Artist",
            MPMediaItemPropertyAlbumTitle: "Album",
            MPMediaItemPropertyAlbumTrackNumber: 4,
            MPMediaItemPropertyPlaybackDuration: 200.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 12.0,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
        center.playbackState = .paused
        let state = bridge.current
        #expect(state?.title == "Song" && state?.artist == "Artist" && state?.albumTitle == "Album")
        #expect(state?.trackNumber == 4 && state?.duration == 200 && state?.elapsed == 12)
        #expect(state?.state == "paused" && state?.hasItem == true)

        center.nowPlayingInfo = nil
        #expect(bridge.current?.hasItem == false)
        #expect(bridge.current?.state == "paused")
    }

    @Test("Without a playback state, the rate says whether it plays")
    func stateFromRate() {
        let setup = Setup()
        let center = setup.center
        let bridge = setup.bridge
        center.nowPlayingInfo = [MPNowPlayingInfoPropertyPlaybackRate: 0.0]
        #expect(bridge.current?.state == "paused")
        center.nowPlayingInfo = [MPNowPlayingInfoPropertyPlaybackRate: 1.0]
        #expect(bridge.current?.state == "playing")
        center.playbackState = .interrupted
        #expect(bridge.current?.state == "paused")
    }

    @Test("Enabling a command tells the host")
    func publishesEnabledCommands() {
        let setup = Setup()
        let center = setup.center
        let commands = setup.commands
        let bridge = setup.bridge
        center.nowPlayingInfo = [MPMediaItemPropertyTitle: "Song"]
        commands.pauseCommand.isEnabled = true
        commands.nextTrackCommand.isEnabled = true
        #expect(
            Set(bridge.current?.enabledCommands ?? [])
                == ["pause", "nextTrack"])
        commands.pauseCommand.isEnabled = false
        #expect(bridge.current?.enabledCommands == ["nextTrack"])
    }

    @Test("Play, pause, next, and previous reach their targets")
    func simpleCommands() {
        let setup = Setup()
        let commands = setup.commands
        let bridge = setup.bridge
        let log = Log()
        for (name, command) in [
            ("play", commands.playCommand), ("pause", commands.pauseCommand),
            ("next", commands.nextTrackCommand), ("previous", commands.previousTrackCommand),
            ("stop", commands.stopCommand),
        ] {
            command.isEnabled = true
            command.addTarget { _ in
                log.add(name)
                return .success
            }
        }
        for command in [
            PreviewRemoteCommand.play, .pause, .nextTrack, .previousTrack, .stop,
        ] {
            bridge.deliver(command)
        }
        #expect(log.all == ["play", "pause", "next", "previous", "stop"])
    }

    @Test("A disabled command, or one with its target removed, runs nothing")
    func disabledAndRemoved() {
        let setup = Setup()
        let commands = setup.commands
        let bridge = setup.bridge
        let log = Log()
        let token = commands.pauseCommand.addTarget { _ in
            log.add("pause")
            return .success
        }
        bridge.deliver(.pause)
        #expect(log.all.isEmpty)
        commands.pauseCommand.isEnabled = true
        bridge.deliver(.pause)
        commands.pauseCommand.removeTarget(token)
        bridge.deliver(.pause)
        #expect(log.all == ["pause"])
    }

    @Test("Play and pause fall back to the toggle command")
    func toggleFallback() {
        let setup = Setup()
        let commands = setup.commands
        let bridge = setup.bridge
        let log = Log()
        commands.togglePlayPauseCommand.isEnabled = true
        commands.togglePlayPauseCommand.addTarget { _ in
            log.add("toggle")
            return .success
        }
        bridge.deliver(.play)
        bridge.deliver(.pause)
        bridge.deliver(.togglePlayPause)
        #expect(log.all == ["toggle", "toggle", "toggle"])
    }

    @Test("Toggling without a toggle command plays or pauses by state")
    func toggleWithoutToggleCommand() {
        let setup = Setup()
        let center = setup.center
        let commands = setup.commands
        let bridge = setup.bridge
        let log = Log()
        for (name, command) in [("play", commands.playCommand), ("pause", commands.pauseCommand)] {
            command.isEnabled = true
            command.addTarget { _ in
                log.add(name)
                return .success
            }
        }
        center.playbackState = .playing
        bridge.deliver(.togglePlayPause)
        center.playbackState = .paused
        bridge.deliver(.togglePlayPause)
        #expect(log.all == ["pause", "play"])
    }

    @Test("Seeking reaches the change-position command, and falls back to skipping")
    func seeking() {
        let setup = Setup()
        let center = setup.center
        let commands = setup.commands
        let bridge = setup.bridge
        let positions = Log()
        center.nowPlayingInfo = [
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 50.0,
            MPNowPlayingInfoPropertyPlaybackRate: 0.0,
        ]
        center.playbackState = .paused

        commands.skipForwardCommand.isEnabled = true
        commands.skipForwardCommand.addTarget { event in
            positions.add("skip \((event as? MPSkipIntervalCommandEvent)?.interval ?? -1)")
            return .success
        }
        bridge.deliver(.seek(offset: 15))
        #expect(positions.all == ["skip 15.0"])

        commands.changePlaybackPositionCommand.isEnabled = true
        commands.changePlaybackPositionCommand.addTarget { event in
            positions.add(
                "to \((event as? MPChangePlaybackPositionCommandEvent)?.positionTime ?? -1)")
            return .success
        }
        bridge.deliver(.seek(offset: -20))
        bridge.deliver(.seek(offset: -80))
        bridge.deliver(.setPosition(seconds: 7))
        #expect(positions.all == ["skip 15.0", "to 30.0", "to 0.0", "to 7.0"])
    }
}
