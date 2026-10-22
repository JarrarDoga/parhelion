import Foundation
import Testing

@testable import ParhelionTooling

@Suite("Watching sources with inotify")
struct InotifyWatcherTests {
    private func makeRoot() throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("parhelion-inotify-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(
            atPath: root + "/Sources/App", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            atPath: root + "/.build/debug", withIntermediateDirectories: true)
        try "let a = 1".write(
            toFile: root + "/Sources/App/A.swift", atomically: true, encoding: .utf8)
        return root
    }

    @Test("A save is seen at once, as one change")
    func save() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let watcher = SourceWatcher(root: root)
        #if os(Linux)
        #expect(watcher.usesInotify)
        #endif
        #expect(!watcher.waitForChanges(timeout: 0.05))
        // Foundation's atomic write is a temporary file and a rename, like
        // many editors' saves.
        try "let a = 2".write(
            toFile: root + "/Sources/App/A.swift", atomically: true, encoding: .utf8)
        let start = Date()
        #expect(watcher.waitForChanges(timeout: 2))
        #expect(Date().timeIntervalSince(start) < 0.5)
        #expect(!watcher.checkForChanges(), "One save is one change")
    }

    @Test("A source in a new directory is seen, and later edits there too")
    func newDirectory() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let watcher = SourceWatcher(root: root)
        try FileManager.default.createDirectory(
            atPath: root + "/Sources/App/Views", withIntermediateDirectories: true)
        #expect(!watcher.waitForChanges(timeout: 0.1), "An empty directory is no change")
        try "let v = 1".write(
            toFile: root + "/Sources/App/Views/V.swift", atomically: false, encoding: .utf8)
        #expect(watcher.waitForChanges(timeout: 2))
        try "let v = 2".write(
            toFile: root + "/Sources/App/Views/V.swift", atomically: false, encoding: .utf8)
        #expect(watcher.waitForChanges(timeout: 2))
    }

    @Test("Build output, hidden files, and other files are ignored")
    func ignored() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let watcher = SourceWatcher(root: root)
        try "x".write(toFile: root + "/.build/debug/B.swift", atomically: false, encoding: .utf8)
        try "x".write(toFile: root + "/Sources/App/notes.md", atomically: false, encoding: .utf8)
        try "x".write(
            toFile: root + "/Sources/App/.A.swift.swp", atomically: false, encoding: .utf8)
        #expect(!watcher.waitForChanges(timeout: 0.2))
        try FileManager.default.removeItem(atPath: root + "/Sources/App/A.swift")
        #expect(watcher.waitForChanges(timeout: 2), "Removing a source is a change")
    }
}
