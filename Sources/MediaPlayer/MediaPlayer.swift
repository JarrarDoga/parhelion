// A stand-in for Apple's MediaPlayer framework on Linux, so that
// `import MediaPlayer` builds. On iOS, `import MediaPlayer` is Apple's
// framework and this target is not built. In a Parhelion preview, the
// now-playing info goes to the window host, which publishes it on the
// desktop's session bus as an MPRIS player, and the player's controls reach
// the remote command targets. See docs/adr/0017-mediaplayer-mpris.md.

import Foundation
import ParhelionPreview

// MARK: - Now Playing

public enum MPNowPlayingPlaybackState: UInt, Sendable {
    case unknown = 0
    case playing = 1
    case paused = 2
    case stopped = 3
    case interrupted = 4
}

public enum MPNowPlayingInfoMediaType: UInt, Sendable {
    case none = 0
    case audio = 1
    case video = 2
}

public final class MPNowPlayingInfoCenter: @unchecked Sendable {
    private static let shared = MPNowPlayingInfoCenter()

    private let lock = NSLock()
    private let bridge: MediaSessionBridge
    private let commands: @Sendable () -> MPRemoteCommandCenter
    private var info: [String: Any]?
    private var state: MPNowPlayingPlaybackState = .unknown
    /// When the info or the state last changed, on the monotonic clock.
    private var changedAt = ProcessInfo.processInfo.systemUptime

    /// What the app plays now. In a Parhelion preview the window host shows
    /// it to the desktop through MPRIS; see `docs/adr/0017-mediaplayer-mpris.md`.
    public var nowPlayingInfo: [String: Any]? {
        get { lock.withLock { info } }
        set {
            lock.withLock {
                info = newValue
                changedAt = ProcessInfo.processInfo.systemUptime
            }
            publish()
        }
    }

    public var playbackState: MPNowPlayingPlaybackState {
        get { lock.withLock { state } }
        set {
            lock.withLock {
                state = newValue
                changedAt = ProcessInfo.processInfo.systemUptime
            }
            publish()
        }
    }

    init(
        bridge: MediaSessionBridge = .shared,
        commands: @escaping @Sendable () -> MPRemoteCommandCenter = { .shared() }
    ) {
        self.bridge = bridge
        self.commands = commands
    }

    /// A now-playing center and a remote command center that talk to each
    /// other and to `bridge` instead of the process-wide ones, for tests.
    static func isolatedPair(
        bridge: MediaSessionBridge
    ) -> (
        MPNowPlayingInfoCenter, MPRemoteCommandCenter
    ) {
        final class Box: @unchecked Sendable {
            var nowPlaying: MPNowPlayingInfoCenter?
            var commands: MPRemoteCommandCenter?
        }
        let box = Box()
        let commands = MPRemoteCommandCenter(bridge: bridge) { box.nowPlaying! }
        let nowPlaying = MPNowPlayingInfoCenter(bridge: bridge) { commands }
        box.nowPlaying = nowPlaying
        box.commands = commands
        return (nowPlaying, commands)
    }

    public class func `default`() -> MPNowPlayingInfoCenter { shared }

    /// How far into the item playback is now, from the elapsed time the app
    /// last set and the time since.
    func estimatedElapsed() -> TimeInterval {
        let (info, state, changedAt) = lock.withLock { (info, state, changedAt) }
        let snapshot = Self.snapshot(info: info, state: state)
        let base = snapshot.elapsed ?? 0
        guard snapshot.state == "playing" else { return base }
        let now = ProcessInfo.processInfo.systemUptime
        return base + (now - changedAt) * snapshot.rate
    }

    /// Sends the current info and state, with the commands enabled now, to
    /// the preview session.
    func publish() {
        let (info, state) = lock.withLock { (info, state) }
        var message = Self.snapshot(info: info, state: state)
        message.enabledCommands = commands().enabledCommandNames
        bridge.publish(message)
    }

    static func snapshot(
        info: [String: Any]?, state: MPNowPlayingPlaybackState
    )
        -> PreviewNowPlaying
    {
        var result = PreviewNowPlaying()
        let rate = info.flatMap { number($0[MPNowPlayingInfoPropertyPlaybackRate]) }
        result.rate = rate ?? 1
        result.hasItem = info != nil
        if let info {
            result.title = info[MPMediaItemPropertyTitle] as? String
            result.artist = info[MPMediaItemPropertyArtist] as? String
            result.albumTitle = info[MPMediaItemPropertyAlbumTitle] as? String
            result.albumArtist = info[MPMediaItemPropertyAlbumArtist] as? String
            result.trackNumber = number(info[MPMediaItemPropertyAlbumTrackNumber]).map(Int.init)
            result.duration = number(info[MPMediaItemPropertyPlaybackDuration])
            result.elapsed = number(info[MPNowPlayingInfoPropertyElapsedPlaybackTime])
        }
        switch state {
        case .playing: result.state = "playing"
        case .paused, .interrupted: result.state = "paused"
        case .stopped: result.state = "stopped"
        case .unknown:
            // Like iOS, derive it from the playback rate while the app does
            // not say.
            result.state = info == nil ? "stopped" : ((rate ?? 1) > 0 ? "playing" : "paused")
        }
        return result
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let value as Double: value
        case let value as Float: Double(value)
        case let value as Int: Double(value)
        case let value as Int64: Double(value)
        case let value as UInt: Double(value)
        case let value as CGFloat: Double(value)
        case let value as NSNumber: value.doubleValue
        default: nil
        }
    }
}

public final class MPMediaItemArtwork: @unchecked Sendable {
    public let bounds: CGSize
    private let requestHandler: (CGSize) -> Any

    /// The handler returns the platform's image type, `UIImage` on iOS.
    public init(boundsSize: CGSize, requestHandler: @escaping @Sendable (CGSize) -> Any) {
        bounds = boundsSize
        self.requestHandler = requestHandler
    }

    public func image(at size: CGSize) -> Any? { requestHandler(size) }
}

// MARK: - Remote commands

public enum MPRemoteCommandHandlerStatus: Int, Sendable {
    case success = 0
    case noSuchContent = 100
    case noActionableNowPlayingItem = 110
    case deviceNotFound = 120
    case commandFailed = 200
}

open class MPRemoteCommandEvent: @unchecked Sendable {
    public let command: MPRemoteCommand
    public let timestamp: TimeInterval

    init(command: MPRemoteCommand, timestamp: TimeInterval = 0) {
        self.command = command
        self.timestamp = timestamp
    }
}

public final class MPChangePlaybackPositionCommandEvent: MPRemoteCommandEvent,
    @unchecked Sendable
{
    public let positionTime: TimeInterval

    init(command: MPRemoteCommand, positionTime: TimeInterval) {
        self.positionTime = positionTime
        super.init(command: command)
    }
}

public final class MPSkipIntervalCommandEvent: MPRemoteCommandEvent, @unchecked Sendable {
    public let interval: TimeInterval

    init(command: MPRemoteCommand, interval: TimeInterval) {
        self.interval = interval
        super.init(command: command)
    }
}

open class MPRemoteCommand: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false
    private var targets:
        [(token: Token, handler: (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus)] = []
    /// The name that ``PreviewNowPlaying/enabledCommands`` uses for this
    /// command.
    let name: String
    /// Called after ``isEnabled`` changes, so the center can report it.
    var onEnabledChange: (@Sendable () -> Void)?

    private final class Token {}

    public var isEnabled: Bool {
        get { lock.withLock { enabled } }
        set {
            let changed = lock.withLock {
                defer { enabled = newValue }
                return enabled != newValue
            }
            if changed { onEnabledChange?() }
        }
    }

    init(name: String = "") { self.name = name }

    @discardableResult
    public func addTarget(
        handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) -> Any {
        let token = Token()
        lock.withLock { targets.append((token, handler)) }
        return token
    }

    public func removeTarget(_ target: Any?) {
        guard let token = target as? Token else {
            // Like Apple's, `nil` removes every target.
            if target == nil { lock.withLock { targets.removeAll() } }
            return
        }
        lock.withLock { targets.removeAll { $0.token === token } }
    }

    /// Runs the targets with an event, the way the system does when the user
    /// presses a control, and returns the first failure or success.
    /// A disabled command runs nothing.
    @discardableResult
    func perform(
        _ makeEvent: (MPRemoteCommand) -> MPRemoteCommandEvent
    )
        -> MPRemoteCommandHandlerStatus
    {
        let (isOn, handlers) = lock.withLock { (enabled, targets.map(\.handler)) }
        guard isOn else { return .commandFailed }
        guard !handlers.isEmpty else { return .noActionableNowPlayingItem }
        let event = makeEvent(self)
        var result = MPRemoteCommandHandlerStatus.success
        for handler in handlers {
            let status = handler(event)
            if status != .success, result == .success { result = status }
        }
        return result
    }
}

public final class MPChangePlaybackPositionCommand: MPRemoteCommand, @unchecked Sendable {}

public final class MPSkipIntervalCommand: MPRemoteCommand, @unchecked Sendable {
    public var preferredIntervals: [NSNumber] = []
}

public final class MPRemoteCommandCenter: @unchecked Sendable {
    private static let sharedCenter = MPRemoteCommandCenter()

    public let pauseCommand = MPRemoteCommand(name: PreviewRemoteCommand.Name.pause)
    public let playCommand = MPRemoteCommand(name: PreviewRemoteCommand.Name.play)
    public let stopCommand = MPRemoteCommand(name: PreviewRemoteCommand.Name.stop)
    public let togglePlayPauseCommand = MPRemoteCommand(
        name: PreviewRemoteCommand.Name.togglePlayPause)
    public let nextTrackCommand = MPRemoteCommand(name: PreviewRemoteCommand.Name.nextTrack)
    public let previousTrackCommand = MPRemoteCommand(
        name: PreviewRemoteCommand.Name.previousTrack)
    public let seekForwardCommand = MPRemoteCommand(name: "seekForward")
    public let seekBackwardCommand = MPRemoteCommand(name: "seekBackward")
    public let changePlaybackRateCommand = MPRemoteCommand(name: "changePlaybackRate")
    public let changeRepeatModeCommand = MPRemoteCommand(name: "changeRepeatMode")
    public let changeShuffleModeCommand = MPRemoteCommand(name: "changeShuffleMode")
    public let likeCommand = MPRemoteCommand(name: "like")
    public let dislikeCommand = MPRemoteCommand(name: "dislike")
    public let bookmarkCommand = MPRemoteCommand(name: "bookmark")
    public let skipForwardCommand = MPSkipIntervalCommand(
        name: PreviewRemoteCommand.Name.skipForward)
    public let skipBackwardCommand = MPSkipIntervalCommand(
        name: PreviewRemoteCommand.Name.skipBackward)
    public let changePlaybackPositionCommand = MPChangePlaybackPositionCommand(
        name: PreviewRemoteCommand.Name.changePlaybackPosition)

    private var all: [MPRemoteCommand] {
        [
            pauseCommand, playCommand, stopCommand, togglePlayPauseCommand, nextTrackCommand,
            previousTrackCommand, skipForwardCommand, skipBackwardCommand,
            changePlaybackPositionCommand,
        ]
    }

    private let nowPlaying: @Sendable () -> MPNowPlayingInfoCenter

    init(
        bridge: MediaSessionBridge = .shared,
        nowPlaying: @escaping @Sendable () -> MPNowPlayingInfoCenter = { .default() }
    ) {
        self.nowPlaying = nowPlaying
        for command in all {
            command.onEnabledChange = { nowPlaying().publish() }
        }
        bridge.setReceiver { [unowned self] command in
            handle(command)
        }
    }

    public class func shared() -> MPRemoteCommandCenter { sharedCenter }

    /// The names of the enabled commands that the desktop's controls use.
    var enabledCommandNames: [String] {
        all.filter(\.isEnabled).map(\.name)
    }

    /// Runs the targets that a command from the desktop's media controls
    /// reaches. The desktop's controls and Apple's differ a little, so a
    /// command the app did not enable falls back to the nearest one it did.
    func handle(_ command: PreviewRemoteCommand) {
        let now = ProcessInfo.processInfo.systemUptime
        func plain(_ command: MPRemoteCommand) -> Bool {
            guard command.isEnabled else { return false }
            command.perform { MPRemoteCommandEvent(command: $0, timestamp: now) }
            return true
        }
        let info = nowPlaying()
        switch command {
        case .play:
            _ = plain(playCommand) || plain(togglePlayPauseCommand)
        case .pause:
            _ = plain(pauseCommand) || plain(togglePlayPauseCommand)
        case .togglePlayPause:
            if togglePlayPauseCommand.isEnabled {
                _ = plain(togglePlayPauseCommand)
            } else if info.playbackState == .playing
                || (info.playbackState == .unknown && info.nowPlayingInfo != nil)
            {
                _ = plain(pauseCommand)
            } else {
                _ = plain(playCommand)
            }
        case .stop:
            _ = plain(stopCommand) || plain(pauseCommand)
        case .nextTrack:
            _ = plain(nextTrackCommand)
        case .previousTrack:
            _ = plain(previousTrackCommand)
        case .setPosition(let seconds):
            seekTo(max(seconds, 0))
        case .seek(let offset):
            if changePlaybackPositionCommand.isEnabled {
                seekTo(max(info.estimatedElapsed() + offset, 0))
            } else {
                let skip = offset >= 0 ? skipForwardCommand : skipBackwardCommand
                skip.perform {
                    MPSkipIntervalCommandEvent(command: $0, interval: abs(offset))
                }
            }
        }
    }

    private func seekTo(_ position: TimeInterval) {
        changePlaybackPositionCommand.perform {
            MPChangePlaybackPositionCommandEvent(command: $0, positionTime: position)
        }
    }
}
