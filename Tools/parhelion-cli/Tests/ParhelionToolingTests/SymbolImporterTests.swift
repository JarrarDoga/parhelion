import Foundation
import Testing

@testable import ParhelionTooling

/// A stand-in for an export of the SF Symbols app, with nothing from Apple.
private func export(_ weights: [String]) -> String {
    var svg = "<svg>"
    for weight in weights {
        svg += "<g id=\"\(weight)-M\"><path d=\"M0 0H10V-10H0Z\"/></g>"
        svg += "<g id=\"\(weight)-S\"><path d=\"M0 0H5V-5H0Z\"/></g>"
    }
    return svg + "</svg>"
}

private func temporaryFolder() throws -> String {
    let path = NSTemporaryDirectory() + "parhelion-import-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
}

@Suite("Importing SF Symbols exports")
struct SymbolImporterTests {
    @Test("Copies the medium outlines of each export, from nested folders")
    func importFolder() throws {
        let source = try temporaryFolder()
        let destination = try temporaryFolder() + "/symbols"
        defer {
            try? FileManager.default.removeItem(atPath: source)
            try? FileManager.default.removeItem(atPath: destination)
        }
        try FileManager.default.createDirectory(
            atPath: source + "/nested", withIntermediateDirectories: true)
        try export(["Regular", "Bold"]).write(
            toFile: source + "/test.one.svg", atomically: true, encoding: .utf8)
        try export(["Regular"]).write(
            toFile: source + "/nested/test.two.svg", atomically: true, encoding: .utf8)
        try "<svg><circle/></svg>".write(
            toFile: source + "/logo.svg", atomically: true, encoding: .utf8)
        try "ignored".write(toFile: source + "/notes.txt", atomically: true, encoding: .utf8)

        let report = try SymbolImporter.import(from: source, to: destination)
        #expect(report.imported == 2)
        #expect(report.skipped == ["logo"])
        #expect(SymbolImporter.count(in: destination) == 2)

        let one = try String(contentsOfFile: destination + "/test.one.svg", encoding: .utf8)
        #expect(one.contains("Regular-M") && one.contains("Bold-M"))
        // The small scale is not kept.
        #expect(!one.contains("-S"))
    }

    @Test("Takes one SVG file")
    func importFile() throws {
        let source = try temporaryFolder()
        let destination = try temporaryFolder()
        defer {
            try? FileManager.default.removeItem(atPath: source)
            try? FileManager.default.removeItem(atPath: destination)
        }
        try export(["Regular"]).write(
            toFile: source + "/test.single.svg", atomically: true, encoding: .utf8)
        let report = try SymbolImporter.import(
            from: source + "/test.single.svg", to: destination)
        #expect(report.imported == 1)
        #expect(FileManager.default.fileExists(atPath: destination + "/test.single.svg"))
    }

    @Test("Explains what to do with an application or a disk image")
    func unsupported() throws {
        let source = try temporaryFolder()
        defer { try? FileManager.default.removeItem(atPath: source) }
        for name in ["SF Symbols.app", "SF-Symbols.dmg"] {
            let path = source + "/" + name
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            #expect(throws: SymbolImporter.Failure.unsupported(path)) {
                try SymbolImporter.import(from: path, to: source + "/out")
            }
        }
        #expect(
            SymbolImporter.Failure.unsupported("x.app").description.contains("File > Export"))
    }

    @Test("Fails on a missing path and on a folder without exports")
    func failures() throws {
        let source = try temporaryFolder()
        defer { try? FileManager.default.removeItem(atPath: source) }
        #expect(throws: SymbolImporter.Failure.missing(source + "/none")) {
            try SymbolImporter.import(from: source + "/none", to: source + "/out")
        }
        #expect(throws: SymbolImporter.Failure.empty(source)) {
            try SymbolImporter.import(from: source, to: source + "/out")
        }
        #expect(!FileManager.default.fileExists(atPath: source + "/out"))
    }

    @Test("Never writes inside a Git repository")
    func repository() throws {
        let source = try temporaryFolder()
        let repository = try temporaryFolder()
        defer {
            try? FileManager.default.removeItem(atPath: source)
            try? FileManager.default.removeItem(atPath: repository)
        }
        try FileManager.default.createDirectory(
            atPath: repository + "/.git", withIntermediateDirectories: true)
        try export(["Regular"]).write(
            toFile: source + "/test.one.svg", atomically: true, encoding: .utf8)
        let destination = repository + "/Sources/symbols"
        #expect(throws: SymbolImporter.Failure.destinationInsideRepository(destination)) {
            try SymbolImporter.import(from: source, to: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: destination))
    }
}
