import Foundation

/// Detects changes to the Swift sources and manifest of a package by
/// comparing modification times.
///
/// Polling is simple, needs no platform APIs, and is fast enough for app
/// packages: one check reads the metadata of each source file.
public struct SourceWatcher: Sendable {
    public let root: String
    private var lastSnapshot: [String: Date]

    /// Directories that never contain the app's sources.
    static let ignoredDirectories: Set<String> = [
        ".build", ".git", ".swiftpm", "xtool", "node_modules",
    ]

    public init(root: String) {
        self.root = root
        lastSnapshot = Self.snapshot(of: root)
    }

    /// Whether any source was added, removed, or modified since the last
    /// call. The first call compares against the state at initialization.
    public mutating func checkForChanges() -> Bool {
        let current = Self.snapshot(of: root)
        defer { lastSnapshot = current }
        return current != lastSnapshot
    }

    /// The modification time of every Swift file and `Package.swift` under
    /// `root`.
    static func snapshot(of root: String) -> [String: Date] {
        let fileManager = FileManager.default
        var result: [String: Date] = [:]
        guard
            let enumerator = fileManager.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else { return result }
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [
                .contentModificationDateKey, .isDirectoryKey,
            ])
            if values?.isDirectory == true {
                if ignoredDirectories.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard url.pathExtension == "swift" else { continue }
            result[url.path] = values?.contentModificationDate ?? .distantPast
        }
        return result
    }
}
