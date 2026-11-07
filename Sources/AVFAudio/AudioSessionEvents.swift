import Foundation

// How the preview reaches an app's audio handlers. On a phone, a call, Siri,
// or unplugged headphones makes iOS post `AVAudioSession.interruptionNotification`
// or `routeChangeNotification`. On Linux nothing does, so the Parhelion preview
// stands in for iOS: `ViewHost.postAudioInterruption` and `postAudioRouteChange`,
// which the `audio_interruption` and `audio_route_change` MCP tools call, post
// one private notification with plain values. The observer below turns it
// into Apple's notification, with Apple's keys and types, and updates the
// session the way iOS does.
//
// The private notification is how the two modules meet without depending on
// each other: ParhelionUI, which builds on every platform, cannot link a
// target that exists only on Linux. The names and values here and in
// ParhelionUI's AudioSessionEvents.swift must agree; a test checks it.

enum AudioSessionEvents {
    /// The notification that ParhelionUI posts. Its user info has `event`
    /// (`interruptionBegan`, `interruptionEnded`, or `routeChange`) and, by
    /// event, `reason`, `shouldResume`, and `device`.
    static let privateName = Notification.Name("ParhelionAudioSessionEvent")

    private static let installed: Void = {
        // The observer lives as long as the process.
        _ = NotificationCenter.default.addObserver(
            forName: privateName, object: nil, queue: nil
        ) { notification in
            guard let info = notification.userInfo else { return }
            handle(
                event: info["event"] as? String ?? "",
                reason: info["reason"] as? String,
                shouldResume: info["shouldResume"] as? Bool ?? false,
                device: info["device"] as? String)
        }
    }()

    /// Starts listening for the preview's events. Safe to call again.
    static func install() {
        _ = installed
    }

    /// A notification name of Apple's, after starting to listen.
    static func name(_ rawValue: String) -> Notification.Name {
        install()
        return Notification.Name(rawValue)
    }

    private static func handle(
        event: String, reason: String?, shouldResume: Bool, device: String?
    ) {
        let session = AVAudioSession.sharedInstance()
        switch event {
        case "interruptionBegan":
            // iOS deactivates the session when an interruption begins.
            session.isActive = false
            var info: [AnyHashable: Any] = [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
            ]
            if let reason = reason.flatMap({ interruptionReasons[$0] }) {
                info[AVAudioSessionInterruptionReasonKey] = reason.rawValue
            }
            post(AVAudioSession.interruptionNotification, session, info)

        case "interruptionEnded":
            let options: AVAudioSession.InterruptionOptions = shouldResume ? .shouldResume : []
            post(
                AVAudioSession.interruptionNotification, session,
                [
                    AVAudioSessionInterruptionTypeKey:
                        AVAudioSession.InterruptionType.ended.rawValue,
                    AVAudioSessionInterruptionOptionKey: options.rawValue,
                ])

        case "routeChange":
            guard let reason = reason.flatMap({ routeChangeReasons[$0] }) else { return }
            let plugged = route(for: device ?? "headphones")
            let previous = session.currentRoute
            switch reason {
            case .newDeviceAvailable: session.currentRoute = plugged
            case .oldDeviceUnavailable: session.currentRoute = AVAudioSession.speakerRoute
            default: break
            }
            // The route that was in use when the device went away is the one with
            // the device in it, whatever the app has seen before.
            let before = reason == .oldDeviceUnavailable ? plugged : previous
            post(
                AVAudioSession.routeChangeNotification, session,
                [
                    AVAudioSessionRouteChangeReasonKey: reason.rawValue,
                    AVAudioSessionRouteChangePreviousRouteKey: before,
                ])

        default:
            break
        }
    }

    private static func post(
        _ name: Notification.Name, _ session: AVAudioSession, _ info: [AnyHashable: Any]
    ) {
        NotificationCenter.default.post(name: name, object: session, userInfo: info)
    }

    static let interruptionReasons: [String: AVAudioSession.InterruptionReason] = [
        "default": .default,
        "appWasSuspended": .appWasSuspended,
        "builtInMicMuted": .builtInMicMuted,
        "routeDisconnected": .routeDisconnected,
    ]

    static let routeChangeReasons: [String: AVAudioSession.RouteChangeReason] = [
        "unknown": .unknown,
        "newDeviceAvailable": .newDeviceAvailable,
        "oldDeviceUnavailable": .oldDeviceUnavailable,
        "categoryChange": .categoryChange,
        "override": .override,
        "wakeFromSleep": .wakeFromSleep,
        "noSuitableRouteForCategory": .noSuitableRouteForCategory,
        "routeConfigurationChange": .routeConfigurationChange,
    ]

    /// The route with one device that a person can plug in or pair.
    static func route(for device: String) -> AVAudioSessionRouteDescription {
        let port: (AVAudioSession.Port, String) =
            switch device {
            case "bluetoothA2DP": (.bluetoothA2DP, "AirPods")
            case "airPlay": (.airPlay, "AirPlay Speaker")
            case "usbAudio": (.usbAudio, "USB Audio")
            case "carAudio": (.carAudio, "Car")
            default: (.headphones, "Headphones")
            }
        let output = AVAudioSessionPortDescription(
            portType: port.0, portName: port.1, uid: "parhelion-\(device)")
        return AVAudioSessionRouteDescription(inputs: [], outputs: [output])
    }
}

extension AVAudioSession {
    /// The route with only the phone's own speaker.
    static var speakerRoute: AVAudioSessionRouteDescription {
        AVAudioSessionRouteDescription(
            inputs: [],
            outputs: [
                AVAudioSessionPortDescription(
                    portType: .builtInSpeaker, portName: "Speaker", uid: "Speaker")
            ])
    }
}
