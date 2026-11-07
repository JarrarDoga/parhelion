#if canImport(Foundation)
import Foundation
#endif

/// The name of the environment variable that makes an app record a flow
/// while a window host shows it. Its value is the path of the file to write.
/// `parhelion run --record` sets it for the first launch only.
public let previewRecordFlowEnvironmentKey = "PARHELION_RECORD_FLOW"

/// A recorded run through an app: the commands a person or an agent sent, the
/// time between them, and the screens they saw.
///
/// The app records a flow (`parhelion run --record FLOW.json`), and
/// `ViewHost.replay(_:)` plays it back, from `parhelion test` or from a Swift
/// Testing test. The file is JSON, so that it can be reviewed in a diff and
/// written by hand or by an agent:
///
/// ```json
/// {
///   "device" : "iPhone 16",
///   "steps" : [
///     { "expect" : ["Root", "└─ VStack", "   └─ Text \"Count: 0\""] },
///     { "command" : { "tapButton" : { "label" : "Increase" } } },
///     { "wait" : 0.5 },
///     { "expect" : [ … ] }
///   ],
///   "version" : 1
/// }
/// ```
///
/// A command is a ``PreviewCommand`` as the preview protocol spells it, so
/// the commands of the agent tools work in flows too. ``version`` numbers the
/// file's own format, apart from the protocol's.
public struct Flow: Codable, Equatable, Sendable {
    /// The newest version of the file format this build reads and writes.
    public static let currentVersion = 1

    public var version: Int
    /// The name of the device the flow was recorded on, such as "iPhone 16".
    /// `parhelion test` starts the app on it.
    public var device: String?
    public var steps: [FlowStep]

    public init(
        version: Int = Flow.currentVersion, device: String? = nil, steps: [FlowStep] = []
    ) {
        self.version = version
        self.device = device
        self.steps = steps
    }

    /// Why a flow file could not be read.
    public enum ReadError: Error, CustomStringConvertible, Equatable {
        case invalid(String)
        case unsupportedVersion(Int)

        public var description: String {
            switch self {
            case .invalid(let reason):
                "The flow file is not valid: \(reason)"
            case .unsupportedVersion(let version):
                "The flow file has version \(version), but this Parhelion reads versions up to "
                    + "\(Flow.currentVersion). Update Parhelion."
            }
        }
    }

    /// Reads a flow from the bytes of a file.
    public static func decode(from data: Data) throws -> Flow {
        let flow: Flow
        do {
            flow = try JSONDecoder().decode(Flow.self, from: data)
        } catch {
            throw ReadError.invalid("\(error)")
        }
        guard flow.version >= 1, flow.version <= currentVersion else {
            throw ReadError.unsupportedVersion(flow.version)
        }
        return flow
    }

    /// The bytes of the file: indented JSON with sorted keys and a final
    /// newline, so that the same flow always gives the same file.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data("\n".utf8)
    }
}

/// One step of a ``Flow``.
public enum FlowStep: Equatable, Sendable {
    /// Sends a command to the app, as a tool would. The step fails when the
    /// app's reply says the command did not work.
    case command(PreviewCommand)
    /// Moves the app's clock on by `seconds`, as `parhelion mcp`'s `wait` does.
    case wait(seconds: Double)
    /// A checkpoint: the screen's outline, without identifiers or frames,
    /// must be equal to this one. Structure, text, and attributes are what a
    /// flow asserts; frames would fail on every layout tweak.
    case expect(outline: String)
}

extension FlowStep: Codable {
    private enum CodingKeys: String, CodingKey {
        case command, wait, expect
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.allKeys.count == 1, let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "A step has exactly one of command, wait, or expect."))
        }
        switch key {
        case .command:
            self = .command(try container.decode(PreviewCommand.self, forKey: .command))
        case .wait:
            self = .wait(seconds: try container.decode(Double.self, forKey: .wait))
        case .expect:
            // A checkpoint is a list of lines, which diffs well. A single
            // string works too, for flows written by hand.
            if let lines = try? container.decode([String].self, forKey: .expect) {
                self = .expect(outline: lines.joined(separator: "\n"))
            } else {
                self = .expect(outline: try container.decode(String.self, forKey: .expect))
            }
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .command(let command):
            try container.encode(command, forKey: .command)
        case .wait(let seconds):
            try container.encode(seconds, forKey: .wait)
        case .expect(let outline):
            try container.encode(
                outline.split(separator: "\n", omittingEmptySubsequences: false).map(String.init),
                forKey: .expect)
        }
    }
}

/// How a replay of a ``Flow`` went.
public struct FlowReport: Codable, Equatable, Sendable {
    /// Why a replay stopped.
    public struct Failure: Codable, Equatable, Sendable {
        /// The position of the step in the flow, from 0.
        public var step: Int
        /// What went wrong: the app's reply to a command, or that a
        /// checkpoint did not match.
        public var message: String
        /// For a checkpoint that did not match, the lines that differ, with
        /// `-` before lines the flow expects and `+` before lines the screen
        /// has.
        public var diff: String?

        public init(step: Int, message: String, diff: String? = nil) {
            self.step = step
            self.message = message
            self.diff = diff
        }
    }

    /// How many steps the flow has.
    public var stepCount: Int
    /// How many steps ran, including the one that failed.
    public var stepsRun: Int
    /// How many checkpoints were rewritten to match the screen, when the
    /// replay was asked to update them.
    public var updatedCheckpoints: Int
    public var failure: Failure?
    /// The flow with its checkpoints rewritten, when the replay was asked to
    /// update them and ran to the end.
    public var updatedFlow: Flow?

    public var passed: Bool { failure == nil }

    public init(
        stepCount: Int, stepsRun: Int, updatedCheckpoints: Int = 0, failure: Failure? = nil,
        updatedFlow: Flow? = nil
    ) {
        self.stepCount = stepCount
        self.stepsRun = stepsRun
        self.updatedCheckpoints = updatedCheckpoints
        self.failure = failure
        self.updatedFlow = updatedFlow
    }
}

/// A line-by-line difference between two texts.
public enum LineDiff {
    /// The lines that differ between `expected` and `actual`, in order: `-`
    /// before a line only `expected` has, `+` before a line only `actual` has,
    /// and two spaces before up to `context` unchanged lines around each
    /// change. Returns an empty string when the texts are equal.
    public static func unified(expected: String, actual: String, context: Int = 2) -> String {
        let old = expected.split(separator: "\n", omittingEmptySubsequences: false)
        let new = actual.split(separator: "\n", omittingEmptySubsequences: false)
        // The longest common subsequence, by dynamic programming. Outlines
        // have tens of lines, so the quadratic table is small.
        var table = [[Int]](
            repeating: [Int](repeating: 0, count: new.count + 1), count: old.count + 1)
        for i in stride(from: old.count - 1, through: 0, by: -1) {
            for j in stride(from: new.count - 1, through: 0, by: -1) {
                table[i][j] =
                    old[i] == new[j]
                    ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var lines: [(mark: Character, text: Substring)] = []
        var i = 0
        var j = 0
        while i < old.count || j < new.count {
            if i < old.count, j < new.count, old[i] == new[j] {
                lines.append((" ", old[i]))
                i += 1
                j += 1
            } else if j == new.count || (i < old.count && table[i + 1][j] >= table[i][j + 1]) {
                lines.append(("-", old[i]))
                i += 1
            } else {
                lines.append(("+", new[j]))
                j += 1
            }
        }
        guard lines.contains(where: { $0.mark != " " }) else { return "" }
        var keep = [Bool](repeating: false, count: lines.count)
        for (index, line) in lines.enumerated() where line.mark != " " {
            for near in max(index - context, 0)...min(index + context, lines.count - 1) {
                keep[near] = true
            }
        }
        var output: [String] = []
        var skipped = false
        for (index, line) in lines.enumerated() {
            guard keep[index] else {
                skipped = true
                continue
            }
            if skipped, !output.isEmpty { output.append("  …") }
            skipped = false
            output.append("\(line.mark) \(line.text)")
        }
        return output.joined(separator: "\n")
    }
}
