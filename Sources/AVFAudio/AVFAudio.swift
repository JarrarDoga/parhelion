// A compile-only stand-in for Apple's AVFAudio framework on Linux, so that
// `import AVFAudio` builds. On iOS, `import AVFAudio` is Apple's framework and
// this target is not built. Issue #79 makes it work.

import Foundation

public struct AVAudioSessionPortDescription: Sendable {
    public let portType: String
    public let portName: String
    public let uid: String
}

public struct AVAudioSessionRouteDescription: Sendable {
    public let inputs: [AVAudioSessionPortDescription]
    public let outputs: [AVAudioSessionPortDescription]
}

public final class AVAudioSession: @unchecked Sendable {
    public struct Category: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let ambient = Category(rawValue: "AVAudioSessionCategoryAmbient")
        public static let soloAmbient = Category(rawValue: "AVAudioSessionCategorySoloAmbient")
        public static let playback = Category(rawValue: "AVAudioSessionCategoryPlayback")
        public static let record = Category(rawValue: "AVAudioSessionCategoryRecord")
        public static let playAndRecord = Category(
            rawValue: "AVAudioSessionCategoryPlayAndRecord")
        public static let multiRoute = Category(rawValue: "AVAudioSessionCategoryMultiRoute")
    }

    public struct Mode: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let `default` = Mode(rawValue: "AVAudioSessionModeDefault")
        public static let voiceChat = Mode(rawValue: "AVAudioSessionModeVoiceChat")
        public static let gameChat = Mode(rawValue: "AVAudioSessionModeGameChat")
        public static let videoRecording = Mode(rawValue: "AVAudioSessionModeVideoRecording")
        public static let measurement = Mode(rawValue: "AVAudioSessionModeMeasurement")
        public static let moviePlayback = Mode(rawValue: "AVAudioSessionModeMoviePlayback")
        public static let videoChat = Mode(rawValue: "AVAudioSessionModeVideoChat")
        public static let spokenAudio = Mode(rawValue: "AVAudioSessionModeSpokenAudio")
        public static let voicePrompt = Mode(rawValue: "AVAudioSessionModeVoicePrompt")
    }

    public struct CategoryOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }

        public static let mixWithOthers = CategoryOptions(rawValue: 1 << 0)
        public static let duckOthers = CategoryOptions(rawValue: 1 << 1)
        public static let allowBluetooth = CategoryOptions(rawValue: 1 << 2)
        public static let defaultToSpeaker = CategoryOptions(rawValue: 1 << 3)
        public static let interruptSpokenAudioAndMixWithOthers = CategoryOptions(
            rawValue: 1 << 4)
        public static let allowBluetoothA2DP = CategoryOptions(rawValue: 1 << 5)
        public static let allowAirPlay = CategoryOptions(rawValue: 1 << 6)
        public static let overrideMutedMicrophoneInterruption = CategoryOptions(
            rawValue: 1 << 7)
    }

    public struct SetActiveOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }

        public static let notifyOthersOnDeactivation = SetActiveOptions(rawValue: 1 << 0)
    }

    public enum InterruptionType: UInt, Sendable {
        case began = 1
        case ended = 0
    }

    public struct InterruptionOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }

        public static let shouldResume = InterruptionOptions(rawValue: 1 << 0)
    }

    public enum RouteChangeReason: UInt, Sendable {
        case unknown = 0
        case newDeviceAvailable = 1
        case oldDeviceUnavailable = 2
        case categoryChange = 3
        case override = 4
        case wakeFromSleep = 6
        case noSuitableRouteForCategory = 7
        case routeConfigurationChange = 8
    }

    public enum SilenceSecondaryAudioHintType: UInt, Sendable {
        case begin = 1
        case end = 0
    }

    private static let shared = AVAudioSession()

    public private(set) var category: Category = .soloAmbient
    public private(set) var mode: Mode = .default
    public private(set) var categoryOptions: CategoryOptions = []
    public private(set) var isActive = false
    public var isOtherAudioPlaying: Bool { false }
    public var secondaryAudioShouldBeSilencedHint: Bool { false }
    public var currentRoute: AVAudioSessionRouteDescription {
        AVAudioSessionRouteDescription(inputs: [], outputs: [])
    }
    public var sampleRate: Double { 44100 }
    public var outputVolume: Float { 1 }

    init() {}

    public class func sharedInstance() -> AVAudioSession { shared }

    public func setCategory(
        _ category: Category, mode: Mode = .default, options: CategoryOptions = []
    ) throws {
        self.category = category
        self.mode = mode
        categoryOptions = options
    }

    public func setCategory(_ category: Category, options: CategoryOptions = []) throws {
        try setCategory(category, mode: .default, options: options)
    }

    public func setMode(_ mode: Mode) throws {
        self.mode = mode
    }

    public func setActive(_ active: Bool, options: SetActiveOptions = []) throws {
        isActive = active
    }

    public static let interruptionNotification = Notification.Name(
        "AVAudioSessionInterruptionNotification")
    public static let routeChangeNotification = Notification.Name(
        "AVAudioSessionRouteChangeNotification")
    public static let silenceSecondaryAudioHintNotification = Notification.Name(
        "AVAudioSessionSilenceSecondaryAudioHintNotification")
    public static let mediaServicesWereLostNotification = Notification.Name(
        "AVAudioSessionMediaServicesWereLostNotification")
    public static let mediaServicesWereResetNotification = Notification.Name(
        "AVAudioSessionMediaServicesWereResetNotification")
}
