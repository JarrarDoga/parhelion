#if canImport(Foundation)
import Foundation
#endif

/// Reads the SVG files that the SF Symbols app exports, and finds the folder
/// where Parhelion keeps the user's own copy.
///
/// Parhelion never contains SF Symbols. A person who has the SF Symbols app
/// exports symbols as SVG templates and points Parhelion at the folder, or
/// imports it with `parhelion symbols import`. An export has one group per
/// weight and scale, named `Regular-M`, `Bold-S`, and so on, each holding the
/// outline as path data. Parhelion reads the medium-scale group of each
/// weight, because a symbol's frame already has the size of its image scale.
public enum SymbolTemplate {
    /// The weights of a template, from lightest to heaviest, as the groups
    /// of an export spell them.
    public static let weightNames = [
        "Ultralight", "Thin", "Light", "Regular", "Medium", "Semibold", "Bold", "Heavy", "Black",
    ]

    /// The index in ``weightNames`` of the weight closest to a weight on the
    /// scale of CSS and OpenType, where regular is 400.
    public static func weightIndex(forValue value: Int) -> Int {
        min(max((value + 50) / 100 - 1, 0), weightNames.count - 1)
    }

    /// The outlines of an export, by index in ``weightNames``, each in the
    /// export's coordinates: x to the right, y down, and the origin at the
    /// symbol's baseline and left edge. A weight the export lacks, or whose
    /// data is malformed, is missing from the result.
    public static func outlines(inSVG svg: String) -> [Int: Path] {
        var result: [Int: Path] = [:]
        for (index, data) in pathData(inSVG: svg) {
            if let path = Path(svgPathData: data) { result[index] = path }
        }
        return result
    }

    /// The path data of each weight's medium-scale group, by index in
    /// ``weightNames``.
    public static func pathData(inSVG svg: String) -> [Int: String] {
        var result: [Int: String] = [:]
        for (index, weight) in weightNames.enumerated() {
            guard let group = groupContents(id: weight + "-M", in: svg) else { continue }
            var parts: [String] = []
            var rest = Substring(group)
            while let start = rest.range(of: "<path") {
                guard let end = rest[start.upperBound...].firstIndex(of: ">") else { break }
                if let data = attribute("d", inTag: rest[start.upperBound..<end]) {
                    parts.append(data)
                }
                rest = rest[end...]
            }
            if !parts.isEmpty { result[index] = parts.joined(separator: " ") }
        }
        return result
    }

    /// A small SVG with only the medium-scale outlines that
    /// ``pathData(inSVG:)`` found, which is what `parhelion symbols import`
    /// keeps of an export.
    public static func trimmedSVG(_ data: [Int: String]) -> String {
        var svg = "<svg xmlns=\"http://www.w3.org/2000/svg\">\n"
        for index in data.keys.sorted() {
            svg += "<g id=\"\(weightNames[index])-M\"><path d=\"\(data[index] ?? "")\"/></g>\n"
        }
        return svg + "</svg>\n"
    }

    /// What is inside the `g` element with an id, including nested groups.
    private static func groupContents(id: String, in svg: String) -> Substring? {
        var from = svg.startIndex
        while let found = svg.range(of: "id=\"\(id)\"", range: from..<svg.endIndex)
            ?? svg.range(of: "id='\(id)'", range: from..<svg.endIndex)
        {
            from = found.upperBound
            // The id must be on a `g` element: the `<` before it starts `<g`.
            guard let open = svg[..<found.lowerBound].lastIndex(of: "<"),
                svg[open...].hasPrefix("<g"),
                let tagEnd = svg[found.upperBound...].firstIndex(of: ">")
            else { continue }
            if svg[svg.index(before: tagEnd)] == "/" { return "" }
            let start = svg.index(after: tagEnd)
            var depth = 1
            var cursor = start
            while depth > 0 {
                guard let tag = svg[cursor...].firstIndex(of: "<") else { return svg[start...] }
                let rest = svg[tag...]
                if rest.hasPrefix("</g") {
                    depth -= 1
                    if depth == 0 { return svg[start..<tag] }
                } else if rest.hasPrefix("<g"),
                    rest.dropFirst(2).first.map({ " \t\n\r>".contains($0) }) == true
                {
                    let close = rest.firstIndex(of: ">") ?? svg.endIndex
                    if close < svg.endIndex, svg[svg.index(before: close)] != "/" { depth += 1 }
                }
                cursor = svg.index(after: tag)
            }
            return svg[start...]
        }
        return nil
    }

    /// The value of an attribute in the text of a tag.
    private static func attribute(_ name: String, inTag tag: Substring) -> String? {
        for quote in ["\"", "'"] {
            for lead in [" ", "\n", "\t", "\r"] {
                guard let start = tag.range(of: "\(lead)\(name)=\(quote)") else { continue }
                let value = tag[start.upperBound...]
                if let end = value.firstIndex(of: Character(quote)) { return String(value[..<end]) }
            }
        }
        return nil
    }

    // MARK: - Where the user's copy is

    /// The environment variable that names a folder of exports, which takes
    /// the place of ``defaultDirectory``.
    public static let environmentVariable = "PARHELION_SF_SYMBOLS"

    /// The folder `parhelion symbols import` writes to:
    /// `$XDG_DATA_HOME/parhelion/symbols`, or `~/.local/share/parhelion/symbols`.
    public static var defaultDirectory: String? {
        if let data = environment("XDG_DATA_HOME"), data.hasPrefix("/") {
            return data + "/parhelion/symbols"
        }
        guard let home = environment("HOME"), !home.isEmpty else { return nil }
        return home + "/.local/share/parhelion/symbols"
    }

    /// The folder Parhelion reads the user's symbols from: the one the
    /// environment variable names, or ``defaultDirectory``.
    public static var activeDirectory: String? {
        if let named = environment(environmentVariable), !named.isEmpty { return named }
        return defaultDirectory
    }

    private static func environment(_ name: String) -> String? {
        #if canImport(Foundation)
        return getenv(name).map { String(cString: $0) }
        #else
        return nil
        #endif
    }
}
