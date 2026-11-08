import Foundation
import ParhelionRender

/// Copies the user's own SF Symbols exports into the per-user folder that
/// Parhelion reads, keeping only the outlines it draws.
///
/// Parhelion contains no SF Symbols and downloads none. The files come from
/// a copy that the person already has, and go to a folder under their home,
/// never into a repository or a build.
public enum SymbolImporter {
    public struct Report: Equatable, Sendable {
        /// Symbols written.
        public var imported = 0
        /// SVG files with no outline Parhelion could read, such as icons
        /// that are not SF Symbols exports.
        public var skipped: [String] = []
        public var destination: String
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case missing(String)
        case unsupported(String)
        case empty(String)
        case destinationInsideRepository(String)

        public var description: String {
            switch self {
            case .missing(let path):
                "\(path) does not exist."
            case .unsupported(let path):
                """
                \(path) is an application, disk image, or archive. Parhelion cannot read symbols \
                out of those: the SF Symbols app keeps them in files that only Apple's frameworks \
                open. In the SF Symbols app, select the symbols you want, choose File > Export \
                Symbol, save them as SVG into a folder, and import that folder.
                """
            case .empty(let path):
                "\(path) has no SVG exports of SF Symbols (files with Regular-S, Regular-M, and similar groups)."
            case .destinationInsideRepository(let path):
                "\(path) is inside a Git repository. SF Symbols must not be committed, so Parhelion won't write them there."
            }
        }
    }

    /// Imports `source`, which is a folder of SVG exports (searched
    /// recursively), or one SVG file.
    public static func `import`(from source: String, to destination: String) throws -> Report {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: source, isDirectory: &isDirectory) else {
            throw Failure.missing(source)
        }
        let ext = (source as NSString).pathExtension.lowercased()
        if ["app", "dmg", "pkg", "zip", "xar", "7z", "tar", "gz"].contains(ext) {
            throw Failure.unsupported(source)
        }
        if try isInsideRepository(destination) {
            throw Failure.destinationInsideRepository(destination)
        }

        var files: [String] = []
        if isDirectory.boolValue {
            let walker = manager.enumerator(atPath: source)
            while let relative = walker?.nextObject() as? String {
                if relative.lowercased().hasSuffix(".svg") { files.append(source + "/" + relative) }
            }
        } else if ext == "svg" {
            files = [source]
        } else {
            throw Failure.empty(source)
        }

        var report = Report(destination: destination)
        var written: [String: String] = [:]
        for file in files.sorted() {
            let name = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
            guard let data = manager.contents(atPath: file),
                let svg = String(data: data, encoding: .utf8)
            else {
                report.skipped.append(name)
                continue
            }
            let paths = SymbolTemplate.pathData(inSVG: svg)
            // A path that does not parse is no use to the renderer.
            let readable = paths.filter { Path(svgPathData: $0.value) != nil }
            if readable.isEmpty || name.contains("/") || name.hasPrefix(".") {
                report.skipped.append(name)
            } else {
                written[name] = SymbolTemplate.trimmedSVG(
                    readable, scale: SymbolTemplate.scaleName(inSVG: svg) ?? "M")
            }
        }
        guard !written.isEmpty else { throw Failure.empty(source) }

        try manager.createDirectory(atPath: destination, withIntermediateDirectories: true)
        for (name, svg) in written {
            try svg.write(
                toFile: destination + "/" + name + ".svg", atomically: true, encoding: .utf8)
        }
        report.imported = written.count
        return report
    }

    /// The number of symbols in a folder.
    public static func count(in directory: String) -> Int {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        return names.filter { $0.hasSuffix(".svg") }.count
    }

    /// Whether a folder, or the nearest folder above it that exists, is
    /// inside a Git working tree. A repository at the home folder, such as one
    /// that holds dotfiles, does not count: the default folder is under it.
    static func isInsideRepository(_ path: String) throws -> Bool {
        var url = URL(fileURLWithPath: path).standardizedFileURL
        let manager = FileManager.default
        let home = ProcessInfo.processInfo.environment["HOME"].map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        }
        while true {
            if url.path == home { return false }
            if manager.fileExists(atPath: url.appendingPathComponent(".git").path) { return true }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { return false }
            url = parent
        }
    }
}
