#if canImport(Foundation)
import Foundation
#endif

// Parhelion-only: what a call, Siri, or unplugged headphones do on a phone.
// iOS posts `AVAudioSession.interruptionNotification` and
// `routeChangeNotification` to the app. Nothing does on Linux, so a test or an
// agent asks the host to, and the app's own handlers run.
//
// ParhelionUI builds on every platform and cannot link the Linux-only
// `AVFAudio` target, so the host posts one private notification with plain
// values, and `AVFAudio` turns it into Apple's notification. An app that does
// not use `AVFAudio` sees nothing, as it would not on a phone. See
// Sources/AVFAudio/AudioSessionEvents.swift.

extension ViewHost {
    /// Why an interruption began, by the case names of
    /// `AVAudioSession.InterruptionReason`.
    public enum AudioInterruptionReason: String, CaseIterable, Hashable, Sendable {
        case `default`
        case appWasSuspended
        case builtInMicMuted
        case routeDisconnected
    }

    /// Why the audio route changed, by the case names of
    /// `AVAudioSession.RouteChangeReason`.
    public enum AudioRouteChangeReason: String, CaseIterable, Sendable {
        case unknown
        case newDeviceAvailable
        case oldDeviceUnavailable
        case categoryChange
        case override
        case wakeFromSleep
        case noSuitableRouteForCategory
        case routeConfigurationChange
    }

    /// The device that a route change plugs in or takes away.
    public enum AudioRouteDevice: String, CaseIterable, Sendable {
        case headphones
        case bluetoothA2DP
        case airPlay
        case usbAudio
        case carAudio
    }

    /// The name that `AVFAudio` listens for.
    static let audioSessionEventName = Notification.Name("ParhelionAudioSessionEvent")

    /// Posts `AVAudioSession.interruptionNotification` as iOS does when a call
    /// or Siri takes the audio: the session becomes inactive, the notification
    /// has type `began` and the reason, and handlers run. Then the host updates,
    /// so the screen shows what the handlers changed.
    public func postAudioInterruptionBegan(reason: AudioInterruptionReason = .default) {
        postAudioSessionEvent(["event": "interruptionBegan", "reason": reason.rawValue])
    }

    /// Posts `AVAudioSession.interruptionNotification` with type `ended`, and
    /// the `shouldResume` option when the system says that playback may resume.
    public func postAudioInterruptionEnded(shouldResume: Bool) {
        postAudioSessionEvent(["event": "interruptionEnded", "shouldResume": shouldResume])
    }

    /// Posts `AVAudioSession.routeChangeNotification`. With
    /// `.oldDeviceUnavailable`, `device` is what was unplugged and the previous
    /// route in the notification has it; with `.newDeviceAvailable`, it is
    /// what was plugged in.
    public func postAudioRouteChange(
        reason: AudioRouteChangeReason = .oldDeviceUnavailable,
        device: AudioRouteDevice = .headphones
    ) {
        postAudioSessionEvent([
            "event": "routeChange", "reason": reason.rawValue, "device": device.rawValue,
        ])
    }

    private func postAudioSessionEvent(_ info: [String: Any]) {
        NotificationCenter.default.post(
            name: Self.audioSessionEventName, object: nil, userInfo: info)
        update()
    }
}
