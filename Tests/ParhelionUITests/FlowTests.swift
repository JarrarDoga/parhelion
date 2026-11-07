import Foundation
import ParhelionPreview
import Testing

@testable import ParhelionUI

private let small = Device(
    name: "Small", screenSize: CGSize(width: 200, height: 400), safeAreaInsets: EdgeInsets())

private struct Counter: View {
    @State private var count = 0
    @State private var name = ""
    @State private var level = 0.5

    var body: some View {
        VStack {
            Text("Count: \(count)")
            Button("Shuffle") { count += 1 }
                .accessibilityIdentifier("shuffle")
            Button("Plus") { count += 10 }
            Button("Same") { count += 100 }
            Button("Same") { count += 1000 }
            TextField("Name", text: $name)
                .accessibilityIdentifier("name")
            Text("Hello \(name)")
            Slider(value: $level)
            ScrollView {
                ForEach(0..<20) { _ in Color.blue.frame(width: 50, height: 40) }
            }
            .frame(height: 60)
        }
    }
}

@MainActor
private func center(of id: String, in host: ViewHost) throws -> (x: Double, y: Double) {
    let frame = try #require(host.root.node(withID: NodeID(id))?.frame)
    return (Double(frame.midX), Double(frame.midY))
}

@MainActor
private func buttons(labeled label: String, in host: ViewHost) -> [ViewNode] {
    host.root.allNodes.filter { $0.kind == "Button" && $0.label == label }
}

/// Reads and drops the app's messages on another thread. Frames fill the
/// socket unless somebody reads them.
private func drain(_ channel: PreviewChannel) {
    nonisolated(unsafe) let channel = channel
    Thread {
        while (try? channel.receiveAppMessage(timeout: 5)) != nil {}
    }.start()
}

@MainActor
@Suite("Flows")
struct FlowTests {
    // MARK: - The file

    @Test("A flow reads back as it was written, with checkpoints as lines")
    func fileRoundTrip() throws {
        let flow = Flow(
            device: "iPhone 16",
            steps: [
                .expect(outline: "Root\n└─ Text \"a\""),
                .command(.tapAccessibilityIdentifier("shuffle")),
                .command(.scroll(dx: 0, dy: 40, x: 10, y: 20)),
                .wait(seconds: 0.5),
            ])
        let data = try flow.encoded()
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.hasSuffix("}\n"))
        #expect(text.contains("\"Root\""))
        #expect(text.contains("\"wait\" : 0.5"))
        #expect(try Flow.decode(from: data) == flow)
        // The same flow always gives the same file.
        #expect(try flow.encoded() == data)
    }

    @Test("A checkpoint written as one string reads too, and a bad step is refused")
    func handWritten() throws {
        let flow = try Flow.decode(
            from: Data(
                #"{"version":1,"steps":[{"expect":"Root"},{"command":{"tapButton":{"label":"Go"}}}]}"#
                    .utf8))
        #expect(flow.steps == [.expect(outline: "Root"), .command(.tapButton(label: "Go"))])
        #expect(throws: Flow.ReadError.self) {
            try Flow.decode(from: Data(#"{"version":1,"steps":[{"wait":1,"expect":"x"}]}"#.utf8))
        }
        #expect(throws: Flow.ReadError.self) {
            try Flow.decode(from: Data("[]".utf8))
        }
    }

    @Test("A newer file version is refused with a message that says to update")
    func newerVersion() {
        let error = #expect(throws: Flow.ReadError.self) {
            try Flow.decode(from: Data(#"{"version":2,"steps":[]}"#.utf8))
        }
        #expect(error == .unsupportedVersion(2))
        #expect(error?.description.contains("Update Parhelion") == true)
    }

    @Test("A line diff marks what the flow expects and what the screen has")
    func lineDiff() {
        #expect(LineDiff.unified(expected: "a\nb", actual: "a\nb").isEmpty)
        let diff = LineDiff.unified(expected: "a\nb\nc\nd\ne\nf\ng", actual: "a\nb\nX\nd\ne\nf\ng")
        #expect(diff == "  a\n  b\n- c\n+ X\n  d\n  e")
        let far = LineDiff.unified(
            expected: "1\n2\n3\n4\n5\n6\n7\n8\n9", actual: "1\nX\n3\n4\n5\n6\n7\n8\nY", context: 1)
        #expect(far == "  1\n- 2\n+ X\n  3\n  …\n  8\n- 9\n+ Y")
    }

    // MARK: - Replay

    @Test("A flow replays against a new host and reaches the recorded screens")
    func replayPasses() {
        let recorder = ViewHost(Counter(), device: small)
        let before = recorder.root.outline()
        _ = recorder.execute(.tapAccessibilityIdentifier("shuffle"))
        _ = recorder.execute(.tapButton(label: "Plus"))
        let after = recorder.root.outline()

        let flow = Flow(
            steps: [
                .expect(outline: before),
                .command(.tapAccessibilityIdentifier("shuffle")),
                .wait(seconds: 0.5),
                .command(.tapButton(label: "Plus")),
                .expect(outline: after),
            ])
        let host = ViewHost(Counter(), device: small)
        let report = host.replay(flow)
        #expect(report.passed)
        #expect(report.stepsRun == 5 && report.stepCount == 5)
        #expect(report.updatedFlow == nil)
        #expect(host.time == 0.5)
        #expect(host.nodes(withText: "Count: 11").count == 1)
    }

    @Test("A checkpoint that differs stops the replay and shows the lines that differ")
    func replayChecksCheckpoint() {
        let host = ViewHost(Counter(), device: small)
        let expected = host.root.outline().replacingOccurrences(
            of: "Count: 0", with: "Count: 1")
        let flow = Flow(
            steps: [
                .expect(outline: expected),
                .command(.tapButton(label: "Plus")),
            ])
        let report = host.replay(flow)
        #expect(!report.passed)
        #expect(report.stepsRun == 1)
        #expect(report.failure?.step == 0)
        #expect(report.failure?.diff?.contains("- ") == true)
        #expect(report.failure?.diff?.contains("Count: 1") == true)
        #expect(report.failure?.diff?.contains("+") == true)
        // The step after the failure did not run.
        #expect(host.nodes(withText: "Count: 0").count == 1)
    }

    @Test("A command whose reply is not ok fails the replay with the reply's message")
    func replayCommandFailure() {
        let host = ViewHost(Counter(), device: small)
        let flow = Flow(steps: [.command(.tapButton(label: "Missing")), .wait(seconds: 1)])
        let report = host.replay(flow)
        #expect(report.failure?.step == 0)
        #expect(report.failure?.message == "No button is labeled \"Missing\".")
        #expect(report.summary == "Step 1 of 2 failed: No button is labeled \"Missing\".")
    }

    @Test("Waits must be a sensible length, and flows do not nest")
    func replayRefusals() {
        let host = ViewHost(Counter(), device: small)
        #expect(host.replay(Flow(steps: [.wait(seconds: -1)])).failure?.step == 0)
        #expect(host.replay(Flow(steps: [.wait(seconds: .infinity)])).failure?.step == 0)
        let nested = host.replay(
            Flow(steps: [.command(.replay(Flow(), updatingCheckpoints: false))]))
        #expect(nested.failure?.message == "A flow cannot replay another flow.")
    }

    @Test("An advanceTime command moves the clock as a wait does, on a real clock too")
    func replayAdvanceTimeCommand() {
        let host = ViewHost(Counter(), device: small)
        let report = host.replay(Flow(steps: [.command(.advanceTime(seconds: 2))]))
        #expect(report.passed)
        #expect(host.time == 2)
    }

    @Test("Updating rewrites checkpoints and returns the new flow")
    func replayUpdates() throws {
        let host = ViewHost(Counter(), device: small)
        let flow = Flow(
            device: "Small",
            steps: [
                .expect(outline: "stale"),
                .command(.tapButton(label: "Plus")),
                .expect(outline: "also stale"),
            ])
        let report = host.replay(flow, updatingCheckpoints: true)
        #expect(report.passed)
        #expect(report.updatedCheckpoints == 2)
        let updated = try #require(report.updatedFlow)
        #expect(updated.device == "Small")
        guard case .expect(let last) = updated.steps[2] else {
            Issue.record("Expected a checkpoint")
            return
        }
        #expect(last.contains("Count: 10"))
        // Replaying the rewritten flow passes without updating.
        #expect(ViewHost(Counter(), device: small).replay(updated).passed)
        // A failing command still fails, and returns no rewritten flow.
        let broken = Flow(steps: [.command(.tapButton(label: "Missing"))])
        let failed = ViewHost(Counter(), device: small).replay(broken, updatingCheckpoints: true)
        #expect(!failed.passed && failed.updatedFlow == nil)
    }

    @Test("The replay command answers with a report")
    func replayCommand() {
        let host = ViewHost(Counter(), device: small)
        let reply = host.execute(
            .replay(Flow(steps: [.command(.tapButton(label: "Plus"))]), updatingCheckpoints: false))
        #expect(reply.ok)
        #expect(reply.message == "Ran all 1 steps.")
        #expect(reply.flowReport?.passed == true)
        let failing = host.execute(
            .replay(Flow(steps: [.command(.tapButton(label: "No"))]), updatingCheckpoints: false))
        #expect(!failing.ok && failing.flowReport?.failure?.step == 0)
    }

    @Test("Flows and reports survive the protocol's JSON")
    func protocolCoding() throws {
        let flow = Flow(steps: [.wait(seconds: 1), .expect(outline: "Root")])
        let command = PreviewCommand.replay(flow, updatingCheckpoints: true)
        let decoded = try JSONDecoder().decode(
            PreviewCommand.self, from: JSONEncoder().encode(command))
        #expect(decoded == command)
        let reply = PreviewReply(
            ok: false, message: "m", revision: 1, isAnimating: false,
            flowReport: FlowReport(
                stepCount: 2, stepsRun: 1, failure: .init(step: 0, message: "x", diff: "- a\n+ b")))
        let back = try JSONDecoder().decode(
            PreviewReply.self, from: JSONEncoder().encode(reply))
        #expect(back == reply)
    }

    // MARK: - Recording

    /// Runs a session with `recordingFlowTo`, sending `script` from another
    /// thread, and returns the flow it wrote.
    private func record(
        pauses: [TimeInterval] = [],
        _ script: @escaping @Sendable (_ send: (HostMessage) throws -> Void) throws -> Void
    ) throws -> Flow {
        let path = NSTemporaryDirectory() + "parhelion-flow-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let (appEnd, hostEnd) = try PreviewChannel.pair()
        let host = ViewHost(Counter(), device: small)
        nonisolated(unsafe) let sender = hostEnd
        drain(hostEnd)
        let thread = Thread {
            do {
                try script { try sender.send($0) }
                try sender.send(.close)
            } catch {}
        }
        thread.start()
        try PreviewSession(
            host: host, channel: appEnd, scale: 1, appName: "Counter", recordingFlowTo: path
        ).run()
        return try Flow.decode(from: Data(contentsOf: URL(fileURLWithPath: path)))
    }

    @Test("Taps are named by identifier, then label, then node, and a slider by its point")
    func recordsTaps() throws {
        let host = ViewHost(Counter(), device: small)
        let shuffle = try center(of: "Counter/VStack/1/Button", in: host)
        let plus = try center(of: "Counter/VStack/2/Button", in: host)
        let same = try #require(buttons(labeled: "Same", in: host).first)
        let sameCenter = (Double(same.frame!.midX), Double(same.frame!.midY))
        let slider = try #require(host.root.allNodes.first { $0.kind == "Slider" }?.frame)
        let sliderPoint = (Double(slider.minX + 20), Double(slider.midY))
        let flow = try record { send in
            for point in [shuffle, plus, sameCenter, sliderPoint] {
                try send(.pointerDown(x: point.0, y: point.1))
                try send(.pointerUp(x: point.0, y: point.1))
            }
        }
        #expect(flow.version == 1 && flow.device == "Small")
        let commands = flow.steps.compactMap { step -> PreviewCommand? in
            if case .command(let command) = step { return command }
            return nil
        }
        #expect(commands.count == 4)
        #expect(commands[0] == .tapAccessibilityIdentifier("shuffle"))
        #expect(commands[1] == .tapButton(label: "Plus"))
        // Two buttons are labeled "Same", so the node identifier names it.
        #expect(commands[2] == .tapNode(id: same.id.rawValue))
        #expect(commands[3] == .tapPoint(x: sliderPoint.0, y: sliderPoint.1))
        // A checkpoint opens the flow and another closes it.
        guard case .expect(let first) = flow.steps.first, case .expect(let last) = flow.steps.last
        else {
            Issue.record("Expected checkpoints first and last")
            return
        }
        #expect(first.contains("Count: 0"))
        #expect(last.contains("Count: 111"))
    }

    @Test("A recorded flow replays to the screens it recorded")
    func recordedFlowReplays() throws {
        let host = ViewHost(Counter(), device: small)
        let shuffle = try center(of: "Counter/VStack/1/Button", in: host)
        let name = try center(of: "Counter/VStack/5/TextField", in: host)
        let list = try center(of: "Counter/VStack/8/ScrollView", in: host)
        let flow = try record { send in
            try send(.pointerDown(x: shuffle.0, y: shuffle.1))
            try send(.pointerUp(x: shuffle.0, y: shuffle.1))
            try send(.pointerDown(x: name.0, y: name.1))
            try send(.pointerUp(x: name.0, y: name.1))
            try send(.text("Ada"))
            try send(.text(" L"))
            try send(.key("backspace"))
            try send(.checkpoint)
            try send(.scroll(dx: 0, dy: 10, x: list.0, y: list.1))
            try send(.scroll(dx: 0, dy: 15, x: list.0, y: list.1))
        }
        // Typing and wheel events with no pause between them are one command;
        // on a busy machine a pause splits them, so join neighbors first.
        var commands: [PreviewCommand] = []
        for step in flow.steps {
            guard case .command(let command) = step else { continue }
            switch (commands.last, command) {
            case (.typeText(let before)?, .typeText(let more)):
                commands[commands.count - 1] = .typeText(before + more)
            case (.scroll(_, let before, _, _)?, .scroll(_, let more, let x, let y)):
                commands[commands.count - 1] = .scroll(dx: 0, dy: before + more, x: x, y: y)
            default:
                commands.append(command)
            }
        }
        #expect(
            commands == [
                .tapAccessibilityIdentifier("shuffle"),
                .focusAccessibilityIdentifier("name"),
                .typeText("Ada L"),
                .pressKey("backspace"),
                .scroll(dx: 0, dy: 25, x: list.0, y: list.1),
            ])
        let checkpoints = flow.steps.filter { if case .expect = $0 { true } else { false } }
        #expect(checkpoints.count == 3)

        let replayed = ViewHost(Counter(), device: small)
        let report = replayed.replay(flow)
        #expect(report.passed, "\(report.failure?.diff ?? report.summary)")
        #expect(replayed.nodes(withText: "Hello Ada ").count == 1)
    }

    @Test("A drag is recorded as one drag with its length, and a pause as a wait")
    func recordsDragAndWaits() throws {
        let host = ViewHost(Counter(), device: small)
        let list = try #require(host.root.allNodes.first { $0.kind == "ScrollView" }?.frame)
        let x = Double(list.midX)
        let from = Double(list.midY + 20)
        let flow = try record { send in
            try send(.pointerDown(x: x, y: from))
            try send(.pointerMoved(x: x, y: from - 15))
            Thread.sleep(forTimeInterval: 0.1)
            try send(.pointerMoved(x: x, y: from - 40))
            try send(.pointerUp(x: x, y: from - 40))
            Thread.sleep(forTimeInterval: 0.3)
            try send(.key("escape"))
        }
        let steps = flow.steps.filter { if case .expect = $0 { false } else { true } }
        guard
            let dragIndex = steps.firstIndex(where: {
                if case .command(.drag) = $0 { true } else { false }
            }),
            case .command(.drag(let fromX, let fromY, let toX, let toY, let duration)) = steps[
                dragIndex]
        else {
            Issue.record("Expected a drag, got \(steps)")
            return
        }
        #expect(fromX == x && toX == x && fromY == from && toY == from - 40)
        #expect(duration >= 0.03 && duration <= 5)
        guard case .wait(let seconds) = steps[dragIndex + 1] else {
            Issue.record("Expected a wait after the drag")
            return
        }
        #expect(seconds >= 0.25 && seconds <= 10)
        #expect(steps.last == .command(.pressKey("escape")))
    }

    @Test("A press that did not hit anything, and typing with no field, leave no steps")
    func ignoresNoise() throws {
        let flow = try record { send in
            try send(.pointerDown(x: 1, y: 399))
            try send(.pointerUp(x: 1, y: 399))
            try send(.text("lost"))
            try send(.key("nonsense"))
            try send(.scroll(dx: 0, dy: 10, x: 1, y: 399))
        }
        #expect(flow.steps.count == 1)
        guard case .expect = flow.steps[0] else {
            Issue.record("Expected one checkpoint")
            return
        }
    }

    @Test("An appearance change is recorded, and a dark start begins with one")
    func recordsAppearance() throws {
        let path = NSTemporaryDirectory() + "parhelion-flow-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let (appEnd, hostEnd) = try PreviewChannel.pair()
        drain(hostEnd)
        let host = ViewHost(
            Counter(), device: small, colorScheme: .dark, dynamicTypeSize: .large)
        try hostEnd.send(
            .command(id: 1, .setAppearance(colorScheme: nil, dynamicTypeSize: "xLarge")))
        try hostEnd.send(.close)
        try PreviewSession(
            host: host, channel: appEnd, scale: 1, appName: "Counter", recordingFlowTo: path
        ).run()
        let flow = try Flow.decode(from: Data(contentsOf: URL(fileURLWithPath: path)))
        #expect(
            flow.steps.prefix(1)
                == [.command(.setAppearance(colorScheme: "dark", dynamicTypeSize: "large"))])
        #expect(
            flow.steps.contains(
                .command(.setAppearance(colorScheme: nil, dynamicTypeSize: "xLarge"))))
    }
}
