import Foundation
import ParhelionPreview
import Testing

@testable import ParhelionTooling

@Suite("Flow files")
struct FlowFilesTests {
    private func temporaryPath() -> String {
        NSTemporaryDirectory() + "parhelion-flow-\(UUID().uuidString).json"
    }

    @Test("A flow written to a file reads back")
    func roundTrip() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let flow = Flow(
            device: "iPhone 16",
            steps: [.expect(outline: "Root"), .command(.tapButton(label: "Go")), .wait(seconds: 1)])
        try FlowFiles.write(flow, to: path)
        #expect(try FlowFiles.load(path) == flow)
    }

    @Test("A missing, broken, or newer file says which file and why")
    func loadFailures() throws {
        let missing = temporaryPath()
        #expect(throws: FlowFiles.Failure.self) { try FlowFiles.load(missing) }

        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        try Data(#"{"version":9,"steps":[]}"#.utf8).write(to: URL(fileURLWithPath: path))
        let error = #expect(throws: FlowFiles.Failure.self) { try FlowFiles.load(path) }
        #expect(error?.description.hasPrefix("\(path): ") == true)
        #expect(error?.description.contains("version 9") == true)

        try Data("not json".utf8).write(to: URL(fileURLWithPath: path))
        #expect(throws: FlowFiles.Failure.self) { try FlowFiles.load(path) }
    }

    @Test("A passing flow prints one line, and says when checkpoints were rewritten")
    func describePass() {
        let report = FlowReport(stepCount: 3, stepsRun: 3)
        #expect(FlowFiles.describe(path: "a.json", report: report) == ["PASS a.json (3 steps)"])
        let updated = FlowReport(stepCount: 1, stepsRun: 1, updatedCheckpoints: 1)
        #expect(
            FlowFiles.describe(path: "a.json", report: updated, updated: true)
                == ["PASS a.json (1 step), rewrote 1 checkpoint"])
    }

    @Test("A failing flow names the step and shows the lines that differ")
    func describeFailure() {
        let report = FlowReport(
            stepCount: 4, stepsRun: 3,
            failure: .init(
                step: 2, message: "The screen is not the one the flow recorded.",
                diff: "  Root\n- Text \"a\"\n+ Text \"b\""))
        #expect(
            FlowFiles.describe(path: "a.json", report: report) == [
                "FAIL a.json",
                "  step 3 of 4: The screen is not the one the flow recorded.",
                "  - the flow expects, + the screen has:",
                "      Root",
                "    - Text \"a\"",
                "    + Text \"b\"",
            ])
        let command = FlowReport(
            stepCount: 1, stepsRun: 1,
            failure: .init(step: 0, message: "No button is labeled \"Go\"."))
        #expect(
            FlowFiles.describe(path: "b.json", report: command) == [
                "FAIL b.json", "  step 1 of 1: No button is labeled \"Go\".",
            ])
    }
}
