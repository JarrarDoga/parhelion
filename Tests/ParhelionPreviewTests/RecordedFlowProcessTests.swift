#if canImport(Glibc)
import Foundation
import Testing

@testable import ParhelionPreview

/// Records a flow from the built `Counter` example, the way a window host's
/// input reaches it, and replays the file in another process on the manual
/// clock. A separate process is the only way to start an app as `parhelion
/// test` does, and it covers the replay on every toolchain the tests run on.
@Suite("Recorded flows in an app process", .serialized)
struct RecordedFlowProcessTests {
    static var counterExecutable: String? {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let products = [
            URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent(),
            root.appendingPathComponent(".build/debug"),
        ]
        return products.map { $0.appendingPathComponent("Counter").path }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// The center of the button whose text is `label`, from an outline with
    /// frames.
    static func center(ofButton label: String, in outline: String) -> (x: Double, y: Double)? {
        let lines = outline.split(separator: "\n").map(String.init)
        guard let text = lines.firstIndex(where: { $0.contains("Text \"\(label)\"") }),
            text > 0, let open = lines[text - 1].lastIndex(of: "["),
            let close = lines[text - 1].lastIndex(of: "]")
        else { return nil }
        let numbers = lines[text - 1][lines[text - 1].index(after: open)..<close]
            .split(whereSeparator: { $0 == "," || $0 == "×" || $0 == " " }).compactMap {
                Double($0)
            }
        guard numbers.count == 4 else { return nil }
        return (numbers[0] + numbers[2] / 2, numbers[1] + numbers[3] / 2)
    }

    @Test("An app records the taps it receives and replays the file on a manual clock")
    func recordAndReplay() throws {
        guard let executable = Self.counterExecutable else {
            Issue.record("The Counter example is not built next to the tests.")
            return
        }
        let path = NSTemporaryDirectory() + "parhelion-flow-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let recording = try ManualClockProcessTests.Session(
            executable: executable, manualClock: false,
            environment: [previewRecordFlowEnvironmentKey: path])
        #expect(recording.hello.capabilities?.contains(PreviewCapability.flowReplay) == true)
        let outline = try recording.request(.inspect(json: false)).message
        let increase = try #require(Self.center(ofButton: "Increase", in: outline))
        for _ in 0..<2 {
            try recording.channel.send(.pointerDown(x: increase.x, y: increase.y))
            try recording.channel.send(.pointerUp(x: increase.x, y: increase.y))
        }
        try recording.channel.send(.checkpoint)
        // A command the window sent as well; it answers after the taps.
        _ = try recording.request(.inspect(json: false))
        recording.finish()

        let flow = try Flow.decode(from: Data(contentsOf: URL(fileURLWithPath: path)))
        #expect(flow.device == "iPhone 16")
        let commands = flow.steps.compactMap { step -> PreviewCommand? in
            if case .command(let command) = step { return command }
            return nil
        }
        #expect(commands == [.tapButton(label: "Increase"), .tapButton(label: "Increase")])
        let checkpoints = flow.steps.compactMap { step -> String? in
            if case .expect(let outline) = step { return outline }
            return nil
        }
        // The start and F2; the close finds the same screen as F2 did.
        #expect(checkpoints.count == 2)
        #expect(checkpoints.first?.contains("Count: 0") == true)
        #expect(checkpoints.last?.contains("Count: 2") == true)

        let replay = try ManualClockProcessTests.Session(
            executable: executable, manualClock: true)
        defer { replay.finish() }
        let reply = try replay.request(.replay(flow, updatingCheckpoints: false))
        #expect(reply.ok, "\(reply.message)")
        #expect(reply.flowReport?.passed == true)
        #expect(reply.flowReport?.stepsRun == flow.steps.count)

        // Without its taps, the flow fails at the last checkpoint.
        var broken = flow
        broken.steps.removeAll { $0 == .command(.tapButton(label: "Increase")) }
        let fresh = try ManualClockProcessTests.Session(executable: executable, manualClock: true)
        defer { fresh.finish() }
        let failed = try fresh.request(.replay(broken, updatingCheckpoints: false))
        #expect(!failed.ok)
        let failure = try #require(failed.flowReport?.failure)
        #expect(
            failure.step
                == broken.steps.firstIndex {
                    if case .expect(let outline) = $0 {
                        outline.contains("Count: 2")
                    } else {
                        false
                    }
                })
        #expect(failure.diff?.contains("- ") == true && failure.diff?.contains("Count: 2") == true)
    }
}
#endif
