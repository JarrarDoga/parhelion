// An app's interruption and route-change handlers, written as Rustle writes
// them, run when the preview posts the events. The same source builds against
// Apple's AVFAudio, where iOS posts them.

import AVFAudio
import Foundation
import Observation
import SwiftUI
import Testing

@MainActor
@Observable
private final class Player {
    var status = "Playing"
    var wasHeadphones = false
    var interruptionCount = 0
    var lastReason: UInt?
    var lastObject: ObjectIdentifier?

    @ObservationIgnored private var tokens: [any NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        tokens.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification, object: nil, queue: nil
            ) { [weak self] notification in
                let info = notification.userInfo
                let raw = info?[AVAudioSessionInterruptionTypeKey] as? UInt
                let options = info?[AVAudioSessionInterruptionOptionKey] as? UInt
                let reason = info?[AVAudioSessionInterruptionReasonKey] as? UInt
                let object = (notification.object as AnyObject?).map(ObjectIdentifier.init)
                MainActor.assumeIsolated {
                    guard let self, let raw,
                        let type = AVAudioSession.InterruptionType(rawValue: raw)
                    else { return }
                    self.interruptionCount += 1
                    self.lastReason = reason
                    self.lastObject = object
                    switch type {
                    case .began:
                        self.status = "Paused by interruption"
                    case .ended:
                        let resume = AVAudioSession.InterruptionOptions(rawValue: options ?? 0)
                        self.status = resume.contains(.shouldResume) ? "Resumed" : "Stays paused"
                    @unknown default:
                        break
                    }
                }
            })
        tokens.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil
            ) { [weak self] notification in
                let info = notification.userInfo
                let raw = info?[AVAudioSessionRouteChangeReasonKey] as? UInt
                let previous =
                    info?[AVAudioSessionRouteChangePreviousRouteKey]
                    as? AVAudioSessionRouteDescription
                MainActor.assumeIsolated {
                    guard let self, let raw,
                        let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
                    else { return }
                    if reason == .oldDeviceUnavailable {
                        self.wasHeadphones =
                            previous?.outputs.contains { $0.portType == .headphones } ?? false
                        if self.wasHeadphones { self.status = "Paused: headphones unplugged" }
                    }
                }
            })
    }

    func stop() {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
        tokens = []
    }
}

private struct NowPlaying: View {
    let player: Player

    var body: some View {
        VStack {
            Text(player.status)
            Text("Interruptions: \(player.interruptionCount)")
        }
    }
}

@MainActor
@Suite("Audio session events", .serialized)
struct AudioSessionEventTests {
    @Test("An interruption that begins and ends runs the app's handler and shows on screen")
    func interruption() throws {
        let player = Player()
        defer { player.stop() }
        let host = ViewHost(NowPlaying(player: player))
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback)
        try session.setActive(true)
        #expect(host.root.outline().contains("Text \"Playing\""))

        host.postAudioInterruptionBegan(reason: .appWasSuspended)
        #expect(player.status == "Paused by interruption")
        #expect(player.lastReason == AVAudioSession.InterruptionReason.appWasSuspended.rawValue)
        #expect(player.lastObject == ObjectIdentifier(session))
        #expect(!session.isActive)
        #expect(host.root.outline().contains("Text \"Paused by interruption\""))
        #expect(host.root.outline().contains("Text \"Interruptions: 1\""))

        host.postAudioInterruptionEnded(shouldResume: true)
        #expect(player.status == "Resumed")
        #expect(host.root.outline().contains("Text \"Resumed\""))

        host.postAudioInterruptionEnded(shouldResume: false)
        #expect(player.status == "Stays paused")
        #expect(player.interruptionCount == 3)
    }

    @Test("Unplugging headphones posts a route change whose previous route has them")
    func oldDeviceUnavailable() {
        let player = Player()
        defer { player.stop() }
        let host = ViewHost(NowPlaying(player: player))
        let session = AVAudioSession.sharedInstance()

        host.postAudioRouteChange(reason: .newDeviceAvailable, device: .bluetoothA2DP)
        #expect(session.currentRoute.outputs.map(\.portType) == [.bluetoothA2DP])
        #expect(player.status == "Playing")

        host.postAudioRouteChange()
        #expect(player.wasHeadphones)
        #expect(player.status == "Paused: headphones unplugged")
        #expect(session.currentRoute.outputs.map(\.portType) == [.builtInSpeaker])
        #expect(host.root.outline().contains("Text \"Paused: headphones unplugged\""))
    }

    @Test("A reason other than a lost device leaves the route and the handler's state alone")
    func categoryChange() {
        let player = Player()
        defer { player.stop() }
        let host = ViewHost(NowPlaying(player: player))
        host.postAudioRouteChange(reason: .categoryChange)
        #expect(!player.wasHeadphones)
        #expect(player.status == "Playing")
    }

    @Test("Every reason the host names is one the shim knows")
    func namesAgree() {
        let player = Player()
        defer { player.stop() }
        let host = ViewHost(NowPlaying(player: player))
        let expected: [ViewHost.AudioInterruptionReason: AVAudioSession.InterruptionReason] = [
            .default: .default, .appWasSuspended: .appWasSuspended,
            .builtInMicMuted: .builtInMicMuted, .routeDisconnected: .routeDisconnected,
        ]
        for reason in ViewHost.AudioInterruptionReason.allCases {
            host.postAudioInterruptionBegan(reason: reason)
            #expect(player.lastReason == expected[reason]?.rawValue, "\(reason)")
        }
        #expect(player.interruptionCount == ViewHost.AudioInterruptionReason.allCases.count)

        let session = AVAudioSession.sharedInstance()
        for reason in ViewHost.AudioRouteChangeReason.allCases {
            for device in ViewHost.AudioRouteDevice.allCases {
                host.postAudioRouteChange(reason: .newDeviceAvailable, device: device)
                #expect(session.currentRoute.outputs.first?.portType != .builtInSpeaker)
            }
            host.postAudioRouteChange(reason: reason, device: .headphones)
        }
    }
}
