// A compile-only stand-in for Apple's MediaPlayer framework on Linux, so that
// `import MediaPlayer` builds. On iOS, `import MediaPlayer` is Apple's
// framework and this target is not built. Issue #64 makes it work.

import Foundation

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

    public var nowPlayingInfo: [String: Any]?
    public var playbackState: MPNowPlayingPlaybackState = .unknown

    init() {}

    public class func `default`() -> MPNowPlayingInfoCenter { shared }
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
    public var isEnabled = false

    init() {}

    @discardableResult
    public func addTarget(
        handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) -> Any {
        NSObject()
    }

    public func removeTarget(_ target: Any?) {}
}

public final class MPChangePlaybackPositionCommand: MPRemoteCommand, @unchecked Sendable {}

public final class MPSkipIntervalCommand: MPRemoteCommand, @unchecked Sendable {
    public var preferredIntervals: [NSNumber] = []
}

public final class MPRemoteCommandCenter: @unchecked Sendable {
    private static let sharedCenter = MPRemoteCommandCenter()

    public let pauseCommand = MPRemoteCommand()
    public let playCommand = MPRemoteCommand()
    public let stopCommand = MPRemoteCommand()
    public let togglePlayPauseCommand = MPRemoteCommand()
    public let nextTrackCommand = MPRemoteCommand()
    public let previousTrackCommand = MPRemoteCommand()
    public let seekForwardCommand = MPRemoteCommand()
    public let seekBackwardCommand = MPRemoteCommand()
    public let changePlaybackRateCommand = MPRemoteCommand()
    public let changeRepeatModeCommand = MPRemoteCommand()
    public let changeShuffleModeCommand = MPRemoteCommand()
    public let likeCommand = MPRemoteCommand()
    public let dislikeCommand = MPRemoteCommand()
    public let bookmarkCommand = MPRemoteCommand()
    public let skipForwardCommand = MPSkipIntervalCommand()
    public let skipBackwardCommand = MPSkipIntervalCommand()
    public let changePlaybackPositionCommand = MPChangePlaybackPositionCommand()

    init() {}

    public class func shared() -> MPRemoteCommandCenter { sharedCenter }
}
