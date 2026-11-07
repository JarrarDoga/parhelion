import Foundation
import ParhelionRender
import ParhelionTesting
import Testing

@testable import ParhelionUI

/// A screen sized like Rustle's design boards, with a few controls.
private struct SnapshotScreen: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Now Playing").font(.largeTitle)
            Text("A snapshot of this screen is stored in Tests/__Snapshots__.")
            Button("Play") {}
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

/// A frame of one flat color, for tests of the comparison.
@MainActor
private func frame(_ red: UInt8, scale: Double = 1) -> RenderedFrame {
    let host = ViewHost(Color(red: Double(red) / 255, green: 0, blue: 0), device: .iPhone16)
    return host.render(scale: scale)
}

@MainActor
@Suite("Snapshot tests")
struct SnapshotTests {
    @Test("A screen matches its stored PNG")
    func storedScreen() {
        ViewHost(SnapshotScreen(), device: .iPhone18ProMax)
            .expectSnapshot(named: "now-playing", scale: 1, chrome: .systemBars)
    }

    @Test("The same screen in dark mode matches its stored PNG")
    func storedDarkScreen() {
        ViewHost(SnapshotScreen().preferredColorScheme(.dark), device: .iPhone18ProMax)
            .expectSnapshot(named: "now-playing-dark", scale: 1, chrome: .systemBars)
    }

    @Test("References live in Tests/__Snapshots__, in a folder named after the test file")
    func referencePath() {
        let url = Snapshots.referenceURL(
            filePath: "/repo/Tests/ParhelionUITests/ListTests.swift",
            testName: "row: 1/2", snapshotName: "Dark mode")
        #expect(url.path == "/repo/Tests/__Snapshots__/ListTests/row--1-2.Dark-mode.png")
    }

    @Test("The record mode comes from the environment")
    func recordModeFromEnvironment() {
        let variable = SnapshotRecordMode.environmentVariable
        #expect(variable == "PARHELION_RECORD_SNAPSHOTS")
        #expect(SnapshotRecordMode.fromEnvironment([:]) == .missing)
        #expect(SnapshotRecordMode.fromEnvironment([variable: ""]) == .missing)
        for mode in SnapshotRecordMode.allCases {
            #expect(SnapshotRecordMode.fromEnvironment([variable: mode.rawValue]) == mode)
        }
        // A typo must not choose a mode, or `alll` could quietly mean `missing`.
        #expect(SnapshotRecordMode.fromEnvironment([variable: "alll"]) == nil)
    }

    @Test("A missing reference is written and fails, unless the mode is never")
    func missingReference() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("nested/red.png")
        let red = frame(200)

        let never = Snapshots.check(red, against: url, record: .never)
        guard case .missingReference = never else {
            Issue.record("Expected a missing reference, got \(never).")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))

        let recorded = Snapshots.check(red, against: url, record: .missing)
        guard case .recorded = recorded else {
            Issue.record("Expected a recording, got \(recorded).")
            return
        }
        #expect(try Data(contentsOf: url) == Data(red.pngData()))

        #expect(Snapshots.check(red, against: url, record: .never).passed)
        #expect(Snapshots.check(red, against: url, record: .missing).passed)
    }

    @Test("A different render fails with a diff image that marks the difference")
    func mismatch() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("red.png")
        _ = Snapshots.check(frame(200), against: url, record: .all)

        let outcome = Snapshots.check(frame(100), against: url, record: .never)
        guard case .differs(let message, let diffPNG) = outcome else {
            Issue.record("Expected a difference, got \(outcome).")
            return
        }
        #expect(message.contains("differ"))
        #expect(message.contains("up to 100 in a channel"))
        let diff = try Bitmap(pngData: diffPNG)
        #expect(diff.width == frame(100).pixelWidth)
        #expect(
            diff.pixel(x: diff.width / 2, y: diff.height / 2) == RGBA(red: 255, green: 0, blue: 0))
        #expect(try Data(contentsOf: url) == Data(frame(200).pngData()))
    }

    @Test("Tolerances accept small differences")
    func tolerance() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("red.png")
        _ = Snapshots.check(frame(200), against: url, record: .all)

        func passes(channel: Int, pixels: Double) -> Bool {
            Snapshots.check(
                frame(205), against: url, record: .never, channelTolerance: channel,
                pixelTolerance: pixels
            ).passed
        }
        #expect(!passes(channel: 0, pixels: 0))
        #expect(!passes(channel: 4, pixels: 0))
        #expect(passes(channel: 5, pixels: 0))
        // Every pixel the color covers differs by 5, so only a pixel tolerance of
        // their share admits that.
        let share = bitmap(of: frame(205)).difference(from: bitmap(of: frame(200))).fraction
        #expect(share > 0.5)
        #expect(!passes(channel: 4, pixels: share / 2))
        #expect(passes(channel: 4, pixels: share))
    }

    @Test("A different size fails whatever the tolerances")
    func differentSize() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("red.png")
        _ = Snapshots.check(frame(200, scale: 1), against: url, record: .all)
        let outcome = Snapshots.check(
            frame(200, scale: 2), against: url, record: .never, channelTolerance: 255,
            pixelTolerance: 1)
        #expect(!outcome.passed)
    }

    @Test("The failed mode rewrites only references that do not match")
    func failedMode() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("red.png")
        _ = Snapshots.check(frame(200), against: url, record: .all)

        #expect(Snapshots.check(frame(200), against: url, record: .failed).passed)
        let rewritten = Snapshots.check(frame(100), against: url, record: .failed)
        guard case .recorded = rewritten else {
            Issue.record("Expected a recording, got \(rewritten).")
            return
        }
        #expect(try Data(contentsOf: url) == Data(frame(100).pngData()))
    }

    @Test("A reference that is not a PNG is reported, not overwritten")
    func unreadableReference() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("red.png")
        try Data("not a png".utf8).write(to: url)
        let outcome = Snapshots.check(frame(200), against: url, record: .missing)
        guard case .unreadableReference = outcome else {
            Issue.record("Expected an unreadable reference, got \(outcome).")
            return
        }
        #expect(try Data(contentsOf: url) == Data("not a png".utf8))
    }

    @Test("A recompressed reference with the same pixels still matches")
    func recompressedReference() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("red.png")
        let red = frame(200)
        // Another encoder would write other bytes for the same pixels. Stored
        // deflate blocks stand in for one.
        try storedDeflatePNG(width: red.pixelWidth, height: red.pixelHeight, rgba: red.pixels)
            .write(to: url)
        #expect(try Data(contentsOf: url) != Data(red.pngData()))
        #expect(Snapshots.check(red, against: url, record: .never).passed)
    }

    private func bitmap(of frame: RenderedFrame) -> Bitmap {
        Bitmap(width: frame.pixelWidth, height: frame.pixelHeight, pixels: frame.pixels)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("parhelion-snapshots-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// A PNG whose image data is stored, uncompressed, in deflate blocks.
private func storedDeflatePNG(width: Int, height: Int, rgba: [UInt8]) -> Data {
    var raw: [UInt8] = []
    for row in 0..<height {
        raw.append(0)
        raw += rgba[(row * width * 4)..<((row + 1) * width * 4)]
    }
    var zlib: [UInt8] = [0x78, 0x01]
    var offset = 0
    repeat {
        let count = min(65535, raw.count - offset)
        let final = offset + count >= raw.count
        zlib += [final ? 1 : 0, UInt8(count & 0xFF), UInt8(count >> 8)]
        zlib += [UInt8(~count & 0xFF), UInt8((~count >> 8) & 0xFF)]
        zlib += raw[offset..<(offset + count)]
        offset += count
    } while offset < raw.count
    var a: UInt32 = 1
    var b: UInt32 = 0
    for byte in raw {
        a = (a + UInt32(byte)) % 65521
        b = (b + a) % 65521
    }
    zlib += bigEndian(b << 16 | a)

    var png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    func chunk(_ type: String, _ body: [UInt8]) {
        let typed = Array(type.utf8) + body
        png += bigEndian(UInt32(body.count)) + typed + bigEndian(crc32(typed))
    }
    chunk("IHDR", bigEndian(UInt32(width)) + bigEndian(UInt32(height)) + [8, 6, 0, 0, 0])
    chunk("IDAT", zlib)
    chunk("IEND", [])
    return Data(png)
}

private func bigEndian(_ value: UInt32) -> [UInt8] {
    [
        UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF),
        UInt8(value & 0xFF),
    ]
}

private func crc32(_ bytes: [UInt8]) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in bytes {
        crc ^= UInt32(byte)
        for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
    }
    return ~crc
}
