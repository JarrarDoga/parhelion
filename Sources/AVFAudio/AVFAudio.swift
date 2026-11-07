// A stand-in for Apple's AVFAudio framework on Linux, so that `import AVFAudio`
// builds. On iOS, `import AVFAudio` is Apple's framework and this target is
// not built.
//
// An audio session holds its category, mode, and activity, and does nothing
// else: there is no audio. What the stand-in adds is the notifications. The
// Parhelion preview can make an interruption begin or end and the route
// change, and the session posts `AVAudioSession.interruptionNotification` and
// `routeChangeNotification` with the keys that Apple's posts carry, so an
// app's handlers run. See AudioSessionEvents.swift and
// docs/adr/0018-audio-session-events.md.

import Foundation

public struct AVAudioSessionPortDescription: Sendable {
    public let portType: AVAudioSession.Port
    public let portName: String
    public let uid: String

    init(portType: AVAudioSession.Port, portName: String, uid: String) {
        self.portType = portType
        self.portName = portName
        self.uid = uid
    }
}

public struct AVAudioSessionRouteDescription: Sendable {
    public let inputs: [AVAudioSessionPortDescription]
    public let outputs: [AVAudioSessionPortDescription]

    init(inputs: [AVAudioSessionPortDescription], outputs: [AVAudioSessionPortDescription]) {
        self.inputs = inputs
        self.outputs = outputs
    }
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

    public struct Port: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let builtInMic = Port(rawValue: "MicrophoneBuiltIn")
        public static let headsetMic = Port(rawValue: "MicrophoneWired")
        public static let lineIn = Port(rawValue: "LineIn")
        public static let airPlay = Port(rawValue: "AirPlay")
        public static let bluetoothA2DP = Port(rawValue: "BluetoothA2DPOutput")
        public static let bluetoothLE = Port(rawValue: "BluetoothLE")
        public static let builtInReceiver = Port(rawValue: "Receiver")
        public static let builtInSpeaker = Port(rawValue: "Speaker")
        // swift-format-ignore: AlwaysUseLowerCamelCase
        public static let HDMI = Port(rawValue: "HDMIOutput")
        public static let headphones = Port(rawValue: "Headphones")
        public static let lineOut = Port(rawValue: "LineOut")
        // swift-format-ignore: AlwaysUseLowerCamelCase
        public static let AVB = Port(rawValue: "AVBDevice")
        // swift-format-ignore: AlwaysUseLowerCamelCase
        public static let PCI = Port(rawValue: "PCIDevice")
        public static let bluetoothHFP = Port(rawValue: "BluetoothHFP")
        public static let usbAudio = Port(rawValue: "USBAudio")
        public static let carAudio = Port(rawValue: "CarAudio")
        public static let virtual = Port(rawValue: "Virtual")
        public static let thunderbolt = Port(rawValue: "Thunderbolt")
        public static let displayPort = Port(rawValue: "DisplayPort")
        public static let fireWire = Port(rawValue: "FireWire")
        public static let continuityMicrophone = Port(rawValue: "ContinuityMicrophone")
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

    public enum InterruptionReason: UInt, Sendable {
        case `default` = 0
        case appWasSuspended = 1
        case builtInMicMuted = 2
        case routeDisconnected = 4
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

    private let lock = NSLock()
    private var _category: Category = .soloAmbient
    private var _mode: Mode = .default
    private var _categoryOptions: CategoryOptions = []
    private var _isActive = false
    private var _route = AVAudioSession.speakerRoute

    public private(set) var category: Category {
        get { lock.withLock { _category } }
        set { lock.withLock { _category = newValue } }
    }
    public private(set) var mode: Mode {
        get { lock.withLock { _mode } }
        set { lock.withLock { _mode = newValue } }
    }
    public private(set) var categoryOptions: CategoryOptions {
        get { lock.withLock { _categoryOptions } }
        set { lock.withLock { _categoryOptions = newValue } }
    }
    public internal(set) var isActive: Bool {
        get { lock.withLock { _isActive } }
        set { lock.withLock { _isActive = newValue } }
    }
    public var isOtherAudioPlaying: Bool { false }
    public var secondaryAudioShouldBeSilencedHint: Bool { false }
    /// The phone's built-in speaker until the preview plugs a device in.
    public internal(set) var currentRoute: AVAudioSessionRouteDescription {
        get { lock.withLock { _route } }
        set { lock.withLock { _route = newValue } }
    }
    public var sampleRate: Double { 44100 }
    public var outputVolume: Float { 1 }

    init() {}

    public class func sharedInstance() -> AVAudioSession {
        AudioSessionEvents.install()
        return shared
    }

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

    // Reading a notification name starts listening for the preview's events,
    // so an app that observes a name before it asks for the session is served.
    public static let interruptionNotification = AudioSessionEvents.name(
        "AVAudioSessionInterruptionNotification")
    public static let routeChangeNotification = AudioSessionEvents.name(
        "AVAudioSessionRouteChangeNotification")
    public static let silenceSecondaryAudioHintNotification = AudioSessionEvents.name(
        "AVAudioSessionSilenceSecondaryAudioHintNotification")
    public static let mediaServicesWereLostNotification = AudioSessionEvents.name(
        "AVAudioSessionMediaServicesWereLostNotification")
    public static let mediaServicesWereResetNotification = AudioSessionEvents.name(
        "AVAudioSessionMediaServicesWereResetNotification")
}
