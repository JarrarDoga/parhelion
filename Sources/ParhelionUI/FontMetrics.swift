#if canImport(Foundation)
import Foundation
#endif

/// The horizontal metrics of a font: the advance width of each character and
/// the line metrics, in font units.
///
/// The metrics of the bundled typeface are generated from its TrueType file
/// by `Scripts/generate-font-metrics.swift`. Parhelion measures text with
/// these metrics alone. It does not apply kerning or shaping, so measured
/// widths can differ slightly from text drawn by a shaping engine. The
/// renderer must draw with the same font file, `Fonts/Inter-Regular.ttf`, so
/// that layout and pixels agree.
struct FontMetrics: Sendable {
    let unitsPerEm: Int
    let ascender: Int
    let descender: Int
    let lineGap: Int
    private let missingGlyphAdvance: Int
    private let scalars: [UInt32]
    private let advances: [UInt16]

    /// - Parameters:
    ///   - scalars: The Unicode scalar values the font maps, in ascending order.
    ///   - advances: The advance width of each scalar in `scalars`.
    init(
        unitsPerEm: Int,
        ascender: Int,
        descender: Int,
        lineGap: Int,
        missingGlyphAdvance: Int,
        scalars: [UInt32],
        advances: [UInt16]
    ) {
        precondition(scalars.count == advances.count, "Every scalar needs one advance.")
        self.unitsPerEm = unitsPerEm
        self.ascender = ascender
        self.descender = descender
        self.lineGap = lineGap
        self.missingGlyphAdvance = missingGlyphAdvance
        self.scalars = scalars
        self.advances = advances
    }

    /// The advance width of a character, in font units. Characters the font
    /// does not contain use the advance of the missing-glyph symbol.
    func advance(of scalar: Unicode.Scalar) -> Int {
        var low = 0
        var high = scalars.count - 1
        while low <= high {
            let middle = (low + high) / 2
            if scalars[middle] == scalar.value { return Int(advances[middle]) }
            if scalars[middle] < scalar.value { low = middle + 1 } else { high = middle - 1 }
        }
        return missingGlyphAdvance
    }

    /// The width of a string at the given point size.
    func width(of text: Substring, size: CGFloat) -> CGFloat {
        let units = text.unicodeScalars.reduce(0) { $0 + advance(of: $1) }
        return CGFloat(units) * size / CGFloat(unitsPerEm)
    }

    /// The distance between the baselines of two lines at the given point
    /// size.
    func lineHeight(size: CGFloat) -> CGFloat {
        CGFloat(ascender - descender + lineGap) * size / CGFloat(unitsPerEm)
    }
}
