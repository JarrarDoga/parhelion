import Foundation
import ParhelionPreview
import Testing

@testable import ParhelionUI

private struct Screen: View {
    var body: some View { Text("Now playing") }
}

// The notifications themselves are checked in SourceCompatibilityTests, which
// can import AVFAudio; here, a stand-in for it listens to the private
// notification.
@MainActor
@Suite("Audio session commands", .serialized)
struct AudioSessionCommandTests {
    private final class Events: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [[String: String]] = []
        var all: [[String: String]] { lock.withLock { seen } }
        func add(_ info: [AnyHashable: Any]?) {
            var entry: [String: String] = [:]
            for (key, value) in info ?? [:] {
                entry["\(key)"] = "\(value)"
            }
            lock.withLock { seen.append(entry) }
        }
    }

    private func listen(_ events: Events) -> any NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: ViewHost.audioSessionEventName, object: nil, queue: nil
        ) { events.add($0.userInfo) }
    }

    @Test("Commands post the event with plain values and report what happened")
    func posts() {
        let events = Events()
        let token = listen(events)
        defer { NotificationCenter.default.removeObserver(token) }
        let host = ViewHost(Screen())

        let began = host.execute(
            .audioInterruption(began: true, shouldResume: false, reason: "builtInMicMuted"))
        #expect(began.ok)
        #expect(began.message == "The audio interruption began (builtInMicMuted).")

        let ended = host.execute(.audioInterruption(began: false, shouldResume: true, reason: nil))
        #expect(ended.message == "The audio interruption ended, and playback may resume.")

        let route = host.execute(
            .audioRouteChange(reason: "oldDeviceUnavailable", device: "headphones"))
        #expect(route.message == "The audio route changed (oldDeviceUnavailable, headphones).")

        #expect(
            events.all == [
                ["event": "interruptionBegan", "reason": "builtInMicMuted"],
                ["event": "interruptionEnded", "shouldResume": "true"],
                ["event": "routeChange", "reason": "oldDeviceUnavailable", "device": "headphones"],
            ])
    }

    @Test("Unknown names are errors, and nothing is posted")
    func rejects() {
        let events = Events()
        let token = listen(events)
        defer { NotificationCenter.default.removeObserver(token) }
        let host = ViewHost(Screen())

        let reason = host.execute(.audioInterruption(began: true, shouldResume: false, reason: "x"))
        #expect(!reason.ok)
        #expect(reason.message.contains("appWasSuspended"))
        let route = host.execute(.audioRouteChange(reason: "explosion", device: "headphones"))
        #expect(!route.ok)
        #expect(route.message.contains("oldDeviceUnavailable"))
        let device = host.execute(.audioRouteChange(reason: "unknown", device: "toaster"))
        #expect(!device.ok)
        #expect(device.message.contains("bluetoothA2DP"))
        #expect(events.all.isEmpty)
    }
}
