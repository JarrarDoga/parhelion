import Foundation
import ParhelionPreview

/// Reading flow files and describing how a replay went, for `parhelion test`.
public enum FlowFiles {
    /// Why a flow file could not be used.
    public struct Failure: Error, CustomStringConvertible {
        public var description: String
    }

    /// Reads the flow in a file.
    public static func load(_ path: String) throws -> Flow {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw Failure(description: "\(path): cannot read the file.")
        }
        do {
            return try Flow.decode(from: data)
        } catch {
            throw Failure(description: "\(path): \(error)")
        }
    }

    /// Writes a flow to a file in the format the recorder uses.
    public static func write(_ flow: Flow, to path: String) throws {
        try flow.encoded().write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    /// The lines `parhelion test` prints for one flow.
    ///
    /// - Parameter updated: Whether the flow file was rewritten.
    public static func describe(
        path: String, report: FlowReport, updated: Bool = false
    ) -> [String] {
        if let failure = report.failure {
            var lines = [
                "FAIL \(path)",
                "  step \(failure.step + 1) of \(report.stepCount): \(failure.message)",
            ]
            if let diff = failure.diff, !diff.isEmpty {
                lines.append("  - the flow expects, + the screen has:")
                lines += diff.split(separator: "\n", omittingEmptySubsequences: false)
                    .map { "    \($0)" }
            }
            return lines
        }
        var line = "PASS \(path) (\(report.stepCount) step\(report.stepCount == 1 ? "" : "s"))"
        if updated {
            let count = report.updatedCheckpoints
            line += ", rewrote \(count) checkpoint\(count == 1 ? "" : "s")"
        }
        return [line]
    }
}
