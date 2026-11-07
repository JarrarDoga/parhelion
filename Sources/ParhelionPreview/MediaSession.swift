import Foundation

/// What an app plays right now, as the `MediaPlayer` shim reports it to the
/// window host, which shows it to the desktop through MPRIS. See
/// `docs/adr/0017-mediaplayer-mpris.md`.
public struct PreviewNowPlaying: Codable, Equatable, Sendable {
    /// The playback state: `playing`, `paused`, `stopped`, or `unknown`.
    public var state: String
    public var title: String?
    public var artist: String?
    public var albumTitle: String?
    public var albumArtist: String?
    public var trackNumber: Int?
    /// The length of the item in seconds.
    public var duration: Double?
    /// How far into the item playback was, in seconds, at the moment the app
    /// sent this. The host adds the time since then, at ``rate``, while the
    /// state is `playing`.
    public var elapsed: Double?
    /// Playback speed: 1 is normal speed.
    public var rate: Double
    /// The remote commands the app has enabled: ``PreviewRemoteCommand``
    /// names, such as `play` and `next`.
    public var enabledCommands: [String]
    /// Whether the app has any now-playing information. A `false` value
    /// means the app set `nowPlayingInfo` to `nil`.
    public var hasItem: Bool

    public init(
        state: String = "unknown",
        title: String? = nil,
        artist: String? = nil,
        albumTitle: String? = nil,
        albumArtist: String? = nil,
        trackNumber: Int? = nil,
        duration: Double? = nil,
        elapsed: Double? = nil,
        rate: Double = 1,
        enabledCommands: [String] = [],
        hasItem: Bool = false
    ) {
        self.state = state
        self.title = title
        self.artist = artist
        self.albumTitle = albumTitle
        self.albumArtist = albumArtist
        self.trackNumber = trackNumber
        self.duration = duration
        self.elapsed = elapsed
        self.rate = rate
        self.enabledCommands = enabledCommands
        self.hasItem = hasItem
    }
}

/// A command from the desktop's media controls, which the host forwards to
/// the app. The `MediaPlayer` shim turns it into a remote command event.
public enum PreviewRemoteCommand: Codable, Equatable, Sendable {
    case play
    case pause
    case togglePlayPause
    case stop
    case nextTrack
    case previousTrack
    /// Move by this many seconds from the current position (MPRIS `Seek`).
    case seek(offset: Double)
    /// Move to this many seconds into the item (MPRIS `SetPosition`).
    case setPosition(seconds: Double)

    /// The names that ``PreviewNowPlaying/enabledCommands`` uses.
    public enum Name {
        public static let play = "play"
        public static let pause = "pause"
        public static let togglePlayPause = "togglePlayPause"
        public static let stop = "stop"
        public static let nextTrack = "nextTrack"
        public static let previousTrack = "previousTrack"
        public static let changePlaybackPosition = "changePlaybackPosition"
        public static let skipForward = "skipForward"
        public static let skipBackward = "skipBackward"
    }
}

/// Where the `MediaPlayer` shim and the preview session meet. The shim
/// publishes the app's now-playing state here and receives the desktop's
/// commands here; the session carries both over the socket to the window
/// host. Neither side links the other.
public final class MediaSessionBridge: @unchecked Sendable {
    public static let shared = MediaSessionBridge()

    private let lock = NSLock()
    private var latest: PreviewNowPlaying?
    private var sender: (@Sendable (PreviewNowPlaying) -> Void)?
    private var receiver: (@Sendable (PreviewRemoteCommand) -> Void)?

    public init() {}

    /// Reports the app's state. It is sent to the host now if a session has
    /// connected the bridge, and when one does connect otherwise.
    public func publish(_ state: PreviewNowPlaying) {
        let send = lock.withLock {
            latest = state
            return sender
        }
        send?(state)
    }

    /// The last state published, or `nil` if the app never published one.
    public var current: PreviewNowPlaying? {
        lock.withLock { latest }
    }

    /// Connects the session: `send` carries each published state to the host.
    /// The state published so far goes first. Pass `nil` to disconnect.
    public func connect(send: (@Sendable (PreviewNowPlaying) -> Void)?) {
        let pending = lock.withLock {
            sender = send
            return latest
        }
        if let pending { send?(pending) }
    }

    /// Sets what runs when the desktop sends a command. The `MediaPlayer`
    /// shim sets it; the last setter wins.
    public func setReceiver(_ handler: (@Sendable (PreviewRemoteCommand) -> Void)?) {
        lock.withLock { receiver = handler }
    }

    /// Hands a command from the host to the app. Returns whether a receiver
    /// took it.
    @discardableResult
    public func deliver(_ command: PreviewRemoteCommand) -> Bool {
        guard let handler = lock.withLock({ receiver }) else { return false }
        handler(command)
        return true
    }
}
