import ParhelionPreview

#if canImport(Foundation)
import Foundation
#endif

extension ViewHost {
    /// Plays a recorded ``Flow`` against this host and reports how it went.
    ///
    /// A command step runs as a tool's command does, and fails when its reply
    /// says it did not work. A wait step moves the clock on with
    /// ``advanceClock(by:)``: on a manual clock, every `Task.sleep` that falls
    /// due wakes in order; otherwise, as in a Swift Testing test, only
    /// ``time`` moves, so animations finish but a `Task.sleep` in the app
    /// still takes real time. A checkpoint compares the screen's `outline()`,
    /// without identifiers or frames, with the recorded one.
    ///
    /// The replay stops at the first step that fails. The host should be in
    /// the state the recording started from, such as a new ``ViewHost``, on
    /// the device the flow names.
    ///
    /// - Parameter updatingCheckpoints: Rewrites checkpoints that differ
    ///   instead of failing, and returns the rewritten flow in the report.
    ///   Commands still fail the replay.
    public func replay(_ flow: Flow, updatingCheckpoints: Bool = false) -> FlowReport {
        var steps = flow.steps
        var updated = 0
        var run = 0
        var failure: FlowReport.Failure?
        for (index, step) in flow.steps.enumerated() {
            run += 1
            switch step {
            case .wait(let seconds):
                failure = wait(seconds).map { .init(step: index, message: $0) }
            case .command(.advanceTime(let seconds)):
                // The same as a wait, so that flows written for `parhelion mcp`
                // also run where the clock is real.
                failure = wait(seconds).map { .init(step: index, message: $0) }
            case .command(.replay):
                failure = .init(step: index, message: "A flow cannot replay another flow.")
            case .command(let command):
                let reply = execute(command)
                if !reply.ok { failure = .init(step: index, message: reply.message) }
            case .expect(let expected):
                update()
                let actual = root.outline()
                guard actual != expected else { break }
                if updatingCheckpoints {
                    steps[index] = .expect(outline: actual)
                    updated += 1
                } else {
                    failure = .init(
                        step: index, message: "The screen is not the one the flow recorded.",
                        diff: LineDiff.unified(expected: expected, actual: actual))
                }
            }
            if failure != nil { break }
        }
        var updatedFlow: Flow?
        if updatingCheckpoints, failure == nil {
            updatedFlow = flow
            updatedFlow?.steps = steps
        }
        return FlowReport(
            stepCount: flow.steps.count, stepsRun: run, updatedCheckpoints: updated,
            failure: failure, updatedFlow: updatedFlow)
    }

    /// Moves the clock on for a wait step, or returns why it cannot.
    private func wait(_ seconds: TimeInterval) -> String? {
        guard seconds.isFinite, seconds >= 0, seconds <= Self.longestAdvance else {
            return "The time to wait must be in 0...\(Int(Self.longestAdvance)) seconds."
        }
        advanceClock(by: seconds)
        return nil
    }
}

extension FlowReport {
    /// A sentence for a tool's reply.
    var summary: String {
        if let failure {
            return "Step \(failure.step + 1) of \(stepCount) failed: \(failure.message)"
        }
        var text = "Ran all \(stepCount) steps."
        if updatedCheckpoints > 0 {
            text +=
                " Rewrote \(updatedCheckpoints) checkpoint\(updatedCheckpoints == 1 ? "" : "s")."
        }
        return text
    }
}
