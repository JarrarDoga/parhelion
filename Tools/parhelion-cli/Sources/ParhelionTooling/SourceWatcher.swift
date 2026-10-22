import Foundation

#if canImport(Glibc)
import Glibc
#endif

/// Detects changes to the Swift sources and manifest of a package.
///
/// On Linux it asks the kernel with inotify, which reports a save within a
/// millisecond and costs nothing while nothing changes. Where inotify is
/// missing or out of watches, it compares modification times instead,
/// twice a second.
///
/// Use a watcher from one thread at a time.
public final class SourceWatcher: @unchecked Sendable {
    public let root: String
    #if canImport(Glibc)
    private let notifier: Inotify?
    #endif
    private var lastSnapshot: [String: Date] = [:]

    /// Directories that never contain the app's sources.
    static let ignoredDirectories: Set<String> = [
        ".build", ".git", ".swiftpm", "xtool", "node_modules",
    ]

    /// How often the fallback compares modification times.
    static let pollInterval = 0.5
    /// How long a change waits for the rest of a save, such as an editor's
    /// rename after writing a temporary file, so one save is one change.
    static let settleTime = 0.05

    public init(root: String) {
        self.root = root
        #if canImport(Glibc)
        notifier = Inotify(root: root)
        if notifier != nil { return }
        #endif
        lastSnapshot = Self.snapshot(of: root)
    }

    /// Whether the watcher uses inotify rather than comparing modification
    /// times.
    public var usesInotify: Bool {
        #if canImport(Glibc)
        return notifier != nil
        #else
        return false
        #endif
    }

    /// Whether any source was added, removed, or modified since the last
    /// call, without waiting. The first call compares against the state at
    /// initialization.
    public func checkForChanges() -> Bool {
        #if canImport(Glibc)
        if let notifier { return notifier.readEvents() }
        #endif
        let current = Self.snapshot(of: root)
        defer { lastSnapshot = current }
        return current != lastSnapshot
    }

    /// Waits until a source changes, up to `timeout` seconds, or
    /// indefinitely when `timeout` is `nil`. Returns `false` on timeout.
    public func waitForChanges(timeout: Double?) -> Bool {
        let deadline = timeout.map { Date().addingTimeInterval($0) }
        #if canImport(Glibc)
        if let notifier {
            while true {
                let remaining = deadline.map { max($0.timeIntervalSinceNow, 0) }
                guard notifier.wait(timeout: remaining) else { return false }
                if notifier.readEvents() {
                    // Take the rest of the save with it.
                    while notifier.wait(timeout: Self.settleTime) { _ = notifier.readEvents() }
                    return true
                }
                if let deadline, deadline.timeIntervalSinceNow <= 0 { return false }
            }
        }
        #endif
        while true {
            if checkForChanges() { return true }
            if let deadline, deadline.timeIntervalSinceNow <= 0 { return false }
            let pause = deadline.map { min(Self.pollInterval, max($0.timeIntervalSinceNow, 0)) }
            Thread.sleep(forTimeInterval: pause ?? Self.pollInterval)
        }
    }

    /// Whether a file name is one whose change should rebuild the app.
    static func isSource(_ name: String) -> Bool {
        name.hasSuffix(".swift") && !name.hasPrefix(".")
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
            guard isSource(url.lastPathComponent) else { continue }
            result[url.path] = values?.contentModificationDate ?? .distantPast
        }
        return result
    }

    /// The directories under `root` to watch, `root` included, skipping
    /// hidden and ignored ones.
    static func directories(under root: String) -> [String] {
        var result = [root]
        guard
            let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else { return result }
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { continue }
            if ignoredDirectories.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            result.append(url.path)
        }
        return result
    }
}

#if canImport(Glibc)
/// An inotify instance that watches every source directory of a package.
/// inotify watches single directories, so each directory gets a watch, and
/// directories created later get one when they appear.
final class Inotify {
    private let descriptor: Int32
    /// The directory of each watch.
    private var directories: [Int32: String] = [:]

    private static let mask = UInt32(
        IN_CLOSE_WRITE | IN_MOVED_TO | IN_MOVED_FROM | IN_CREATE | IN_DELETE)

    /// Watches `root` and its directories, or returns `nil` if inotify is not
    /// available or runs out of watches.
    init?(root: String) {
        descriptor = inotify_init1(Int32(IN_NONBLOCK | IN_CLOEXEC))
        guard descriptor >= 0 else { return nil }
        for directory in SourceWatcher.directories(under: root) {
            guard add(directory) else {
                Glibc.close(descriptor)
                return nil
            }
        }
    }

    deinit {
        Glibc.close(descriptor)
    }

    /// Adds a watch for one directory. Returns `false` if the system is out
    /// of watches. A directory that vanished meanwhile is not an error.
    private func add(_ directory: String) -> Bool {
        let watch = inotify_add_watch(descriptor, directory, Self.mask)
        if watch < 0 { return errno != ENOSPC }
        directories[watch] = directory
        return true
    }

    /// Waits until events are ready to read, up to `timeout` seconds, or
    /// indefinitely when `timeout` is `nil`.
    func wait(timeout: Double?) -> Bool {
        var entry = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        let milliseconds = timeout.map { Int32(($0 * 1000).rounded(.up)) } ?? -1
        while true {
            let result = poll(&entry, 1, milliseconds)
            if result < 0, errno == EINTR { continue }
            return result > 0
        }
    }

    /// Reads every queued event without waiting. Returns whether any of
    /// them concerns a source file or a directory that may hold some.
    func readEvents() -> Bool {
        var relevant = false
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                read(descriptor, $0.baseAddress, $0.count)
            }
            guard count > 0 else { return relevant }
            var offset = 0
            // Each event is a 16-byte header (watch, mask, cookie, name
            // length) and a name padded with zeros to that length.
            while offset + 16 <= count {
                let (watch, mask, nameLength) = buffer.withUnsafeBytes {
                    (
                        $0.loadUnaligned(fromByteOffset: offset, as: Int32.self),
                        $0.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self),
                        Int($0.loadUnaligned(fromByteOffset: offset + 12, as: UInt32.self))
                    )
                }
                let nameBytes = buffer[(offset + 16)..<min(offset + 16 + nameLength, count)]
                let name = String(decoding: nameBytes.prefix { $0 != 0 }, as: UTF8.self)
                offset += 16 + nameLength
                if handle(watch: watch, mask: mask, name: name) { relevant = true }
            }
        }
    }

    /// Applies one event. Returns whether it is relevant.
    private func handle(watch: Int32, mask: UInt32, name: String) -> Bool {
        if mask & UInt32(IN_Q_OVERFLOW) != 0 { return true }
        if mask & UInt32(IN_IGNORED) != 0 {
            directories[watch] = nil
            return false
        }
        guard mask & UInt32(IN_ISDIR) != 0 else { return SourceWatcher.isSource(name) }
        guard let parent = directories[watch], !name.hasPrefix("."),
            !SourceWatcher.ignoredDirectories.contains(name)
        else { return false }
        let path = parent + "/" + name
        if mask & UInt32(IN_CREATE | IN_MOVED_TO) != 0 {
            // A directory moved in may already hold sources.
            for directory in SourceWatcher.directories(under: path) { _ = add(directory) }
            return !SourceWatcher.snapshot(of: path).isEmpty
        }
        // A directory removed or moved away may have held sources.
        return true
    }
}
#endif
