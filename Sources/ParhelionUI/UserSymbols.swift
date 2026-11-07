import ParhelionRender

#if canImport(Foundation)
import Foundation
#endif

/// The user's own SF Symbols: the SVG exports in the folder that
/// ``SymbolTemplate/activeDirectory`` names.
///
/// Parhelion contains no SF Symbols. This reads files that a person put on
/// their own machine, one file per symbol, the first time a name is drawn.
enum UserSymbols {
    /// Whether the folder has a file for the name.
    static func has(_ name: String) -> Bool {
        store.outlines(for: name) != nil
    }

    /// The outline of a symbol in a square of side 1, in the weight closest
    /// to the one asked for.
    static func outline(_ name: String, weight: Font.Weight, fill: Bool) -> Path? {
        let names = name.hasSuffix(".fill") || !fill ? [name] : [name + ".fill", name]
        for candidate in names {
            guard let outlines = store.outlines(for: candidate), !outlines.isEmpty else {
                continue
            }
            let wanted = SymbolTemplate.weightIndex(forValue: weight.value)
            let index = outlines.keys.min { abs($0 - wanted) < abs($1 - wanted) } ?? wanted
            return outlines[index]
        }
        return nil
    }

    private static let store = Store()

    /// Outlines read from the folder, by name, normalized to the unit square.
    private final class Store: @unchecked Sendable {
        private let lock = NSLock()
        /// Keyed by folder and name, so that a different folder is read
        /// afresh. A name with no file is cached too.
        private var entries: [String: [Int: Path]?] = [:]

        func outlines(for name: String) -> [Int: Path]? {
            guard let directory = SymbolTemplate.activeDirectory, !directory.isEmpty,
                !name.isEmpty, !name.contains("/"), !name.contains("\0"), !name.hasPrefix(".")
            else { return nil }
            let key = directory + "\n" + name
            lock.lock()
            defer { lock.unlock() }
            if let cached = entries[key] { return cached }
            let loaded = load(directory + "/" + name + ".svg")
            entries[key] = .some(loaded)
            return loaded
        }

        private func load(_ file: String) -> [Int: Path]? {
            guard let data = FileManager.default.contents(atPath: file),
                let svg = String(data: data, encoding: .utf8)
            else { return nil }
            let outlines = SymbolTemplate.outlines(inSVG: svg)
            guard !outlines.isEmpty else { return nil }
            // A symbol of the medium scale is drawn at the size of its font,
            // which an export draws at 100 units to the em. Each weight is
            // centered on its own bounds.
            let unit = 1.0 / 100
            return outlines.compactMapValues { path in
                guard let box = path.boundingRect else { return nil }
                return path.applying(
                    scaleX: unit, scaleY: unit,
                    translateX: 0.5 - Double(box.midX) * unit,
                    translateY: 0.5 - Double(box.midY) * unit)
            }
        }
    }
}
