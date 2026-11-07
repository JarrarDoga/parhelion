import Foundation
import ParhelionRender
import ParhelionUI
import Testing

/// What a snapshot check does when it finds a reference, or does not.
///
/// The names and meanings follow `swift-snapshot-testing`. The environment
/// variable `PARHELION_RECORD_SNAPSHOTS` chooses one; the default is
/// ``missing``.
public enum SnapshotRecordMode: String, Sendable, CaseIterable {
    /// Rewrite every reference, whether or not it matches.
    case all
    /// Rewrite the references that do not match, or do not exist. For tests
    /// that have a tolerance.
    case failed
    /// Write a reference that does not exist yet, and compare the rest.
    case missing
    /// Never write. A missing reference fails the test. Use this in CI so
    /// that a retry cannot pass by recording what it just saw.
    case never

    /// The name of the environment variable that chooses the mode.
    public static let environmentVariable = "PARHELION_RECORD_SNAPSHOTS"

    /// The mode the environment chooses, or `nil` when it names none.
    ///
    /// An unset or empty variable gives ``missing``. A value that is not a
    /// mode gives `nil`, so that a typo does not silently rewrite references.
    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SnapshotRecordMode? {
        guard let value = environment[environmentVariable], !value.isEmpty else { return .missing }
        return SnapshotRecordMode(rawValue: value)
    }
}

/// The result of comparing a render with its stored PNG.
public enum SnapshotOutcome: Sendable {
    /// The render matches the reference, byte for byte or within the tolerances.
    case matched
    /// The reference was written, so there was nothing to check. This fails
    /// the test, like `swift-snapshot-testing`, so that recording is never
    /// mistaken for passing.
    case recorded(message: String)
    /// There is no reference, and the mode forbids writing one.
    case missingReference(message: String)
    /// The render differs from the reference by more than the tolerances.
    case differs(message: String, diffPNG: [UInt8])
    /// The reference could not be read as a PNG.
    case unreadableReference(message: String)

    /// Whether the check passed.
    public var passed: Bool {
        if case .matched = self { return true }
        return false
    }
}

/// Comparison of renders with stored PNGs, without Swift Testing.
public enum Snapshots {
    /// Where the reference for a snapshot lives:
    /// `Tests/__Snapshots__/<test file name>/<test name>.<snapshot name>.png`.
    ///
    /// The folder is next to the test targets' folders, not inside one, so
    /// SwiftPM does not warn about unhandled files and the PNGs are not
    /// resources (see ADR 0003). `filePath` is a test file's `#filePath`,
    /// which is `Tests/<target>/<file>.swift`.
    public static func referenceURL(
        filePath: String, testName: String, snapshotName: String
    ) -> URL {
        let file = URL(fileURLWithPath: filePath)
        let suite = file.deletingPathExtension().lastPathComponent
        return file.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__", isDirectory: true)
            .appendingPathComponent(suite, isDirectory: true)
            .appendingPathComponent("\(sanitize(testName)).\(sanitize(snapshotName)).png")
    }

    /// Compares a render with the PNG at `url`, and writes it as the
    /// reference when `record` says so.
    ///
    /// - Parameters:
    ///   - channelTolerance: How far a channel may differ, 0 to 255, before
    ///     its pixel counts as differing. The default is 0 because x86-64
    ///     renders are byte-stable.
    ///   - pixelTolerance: The share of pixels, 0 to 1, that may differ.
    public static func check(
        _ frame: RenderedFrame,
        against url: URL,
        record: SnapshotRecordMode,
        channelTolerance: Int = 0,
        pixelTolerance: Double = 0
    ) -> SnapshotOutcome {
        let actual = Data(frame.pngData())
        let existing = try? Data(contentsOf: url)

        func write(_ reason: String) -> SnapshotOutcome {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try actual.write(to: url)
            } catch {
                return .unreadableReference(
                    message: "Could not write the reference \(url.path): \(error).")
            }
            return .recorded(
                message:
                    "\(reason) Wrote \(url.path). Run the test again without "
                    + "\(SnapshotRecordMode.environmentVariable)=all to compare against it.")
        }

        if record == .all { return write("Recording every snapshot.") }
        guard let existing else {
            switch record {
            case .never:
                return .missingReference(
                    message:
                        "No reference at \(url.path), and \(SnapshotRecordMode.environmentVariable)"
                        + "=never does not write one.")
            default:
                return write("No reference existed.")
            }
        }
        // The fast path: a render compared with its own recording is the same bytes.
        if existing == actual { return .matched }

        let reference: Bitmap
        do {
            reference = try Bitmap(pngData: [UInt8](existing))
        } catch {
            if record == .failed {
                return write("The reference was not a readable PNG (\(error)).")
            }
            return .unreadableReference(
                message: "The reference \(url.path) is not a readable PNG: \(error).")
        }
        let rendered = Bitmap(
            width: frame.pixelWidth, height: frame.pixelHeight, pixels: frame.pixels)
        let difference = rendered.difference(from: reference, channelTolerance: channelTolerance)
        if difference.sizesMatch && difference.fraction <= pixelTolerance { return .matched }

        let summary =
            "The render differs from \(url.path). \(difference.summary) "
            + "The tolerances are \(channelTolerance) per channel and "
            + "\((pixelTolerance * 100000).rounded() / 1000)% of pixels."
        if record == .failed { return write(summary) }
        let diff = rendered.differenceImage(from: reference, channelTolerance: channelTolerance)
        return .differs(message: summary, diffPNG: diff.pngData())
    }

    /// A name that is safe in a file name: letters, digits, `-`, `_`, and `.`.
    static func sanitize(_ name: String) -> String {
        let mapped = name.unicodeScalars.map { scalar -> Character in
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9", "-", "_", ".": return Character(scalar)
            default: return "-"
            }
        }
        return String(mapped)
    }
}

extension ViewHost {
    /// Records a Swift Testing issue unless the current screen matches a
    /// stored PNG.
    ///
    /// The reference is `Tests/__Snapshots__/<test file>/<test>.<name>.png`
    /// next to the test target folders, or `reference` when given. A failure
    /// attaches the actual image and an image of the differences; they are
    /// written when `swift test` runs with `--attachments-path`.
    ///
    /// Set `PARHELION_RECORD_SNAPSHOTS` to `missing` (the default), `failed`,
    /// `all`, or `never`; CI uses `never`. Recording a reference fails the
    /// test, so that it is never mistaken for a pass.
    ///
    /// - Parameters:
    ///   - name: Tells the snapshots of one test apart.
    ///   - scale: Pixels per point.
    ///   - chrome: The system interface to draw over the screen.
    ///   - channelTolerance: How far a channel may differ, 0 to 255, before
    ///     its pixel counts as differing. The default 0 asks for equal pixels.
    ///   - pixelTolerance: The share of pixels, 0 to 1, that may differ.
    ///   - record: Overrides the environment's record mode.
    ///   - reference: A PNG to compare with, in place of the usual path.
    public func expectSnapshot(
        named name: String,
        scale: Double = 2,
        chrome: DeviceChrome = .none,
        channelTolerance: Int = 0,
        pixelTolerance: Double = 0,
        record: SnapshotRecordMode? = nil,
        reference: URL? = nil,
        filePath: String = #filePath,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let mode: SnapshotRecordMode
        if let record {
            mode = record
        } else if let fromEnvironment = SnapshotRecordMode.fromEnvironment() {
            mode = fromEnvironment
        } else {
            let modes = SnapshotRecordMode.allCases.map(\.rawValue).joined(separator: ", ")
            Issue.record(
                "\(SnapshotRecordMode.environmentVariable) must be one of \(modes).",
                sourceLocation: sourceLocation)
            return
        }
        let testName =
            (Test.current?.name ?? "snapshot")
            .split(separator: "(", maxSplits: 1).first.map(String.init) ?? "snapshot"
        let url =
            reference
            ?? Snapshots.referenceURL(
                filePath: filePath, testName: testName, snapshotName: name)
        let frame = render(scale: scale, chrome: chrome)
        let outcome = Snapshots.check(
            frame, against: url, record: mode, channelTolerance: channelTolerance,
            pixelTolerance: pixelTolerance)
        switch outcome {
        case .matched:
            return
        case .recorded(let message), .missingReference(let message),
            .unreadableReference(let message):
            Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
        case .differs(let message, let diffPNG):
            Attachment.record(
                [UInt8](frame.pngData()), named: "\(name)-actual.png",
                sourceLocation: sourceLocation)
            Attachment.record(diffPNG, named: "\(name)-diff.png", sourceLocation: sourceLocation)
            Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
        }
    }
}
