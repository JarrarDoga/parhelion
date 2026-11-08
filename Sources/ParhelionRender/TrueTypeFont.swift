#if canImport(Foundation)
import Foundation
#endif

/// A TrueType font: its metrics, character map, and glyph outlines.
///
/// Parhelion reads the `head`, `hhea`, `maxp`, `hmtx`, `cmap`, `loca`, and
/// `glyf` tables, and the cap height from `OS/2`. It does not apply kerning, ligatures, or hinting, so layout
/// and drawing both place each glyph at its advance width, plus
/// ``tracking(size:)``, and stay in agreement.
///
/// A font keeps the outlines it has parsed, so that drawing a glyph again
/// in a later frame does not read the `glyf` table again.
public struct TrueTypeFont: Sendable {
    public enum ParseError: Error, Equatable {
        case missingTable(String)
        case truncated
        case unsupportedCharacterMap
        case unsupportedOutlines
    }

    /// Font design units per em. Multiply a value in font units by
    /// `size / unitsPerEm` to get points.
    public let unitsPerEm: Int
    /// The distance from the baseline to the top of the line, in font units.
    public let ascender: Int
    /// The distance from the baseline to the bottom of the line, in font
    /// units. Negative below the baseline.
    public let descender: Int
    /// Extra space between lines, in font units.
    public let lineGap: Int
    /// The height of capital letters above the baseline, in font units.
    public let capHeight: Int

    private let bytes: [UInt8]
    private let advances: [UInt16]
    private let glyphs: [UInt32: UInt16]
    private let glyphOffsets: [Int]
    private let glyfOffset: Int
    private let outlines = OutlineCache()
    private let coverages = CoverageCache()

    public init(bytes: [UInt8]) throws {
        let reader = ByteReader(bytes: bytes)
        let tables = try reader.tableDirectory()
        func table(_ tag: String) throws -> Int {
            guard let offset = tables[tag] else { throw ParseError.missingTable(tag) }
            return offset
        }

        let head = try table("head")
        unitsPerEm = Int(try reader.uint16(at: head + 18))
        let longOffsets = try reader.int16(at: head + 50) == 1

        let hhea = try table("hhea")
        ascender = Int(try reader.int16(at: hhea + 4))
        descender = Int(try reader.int16(at: hhea + 6))
        lineGap = Int(try reader.int16(at: hhea + 8))
        let metricCount = Int(try reader.uint16(at: hhea + 34))

        // Version 2 and later of the OS/2 table record the cap height. Older
        // fonts get an estimate.
        if let os2 = tables["OS/2"], try reader.uint16(at: os2) >= 2 {
            capHeight = Int(try reader.int16(at: os2 + 88))
        } else {
            capHeight = ascender * 7 / 10
        }

        let hmtx = try table("hmtx")
        advances = try (0..<metricCount).map { try reader.uint16(at: hmtx + $0 * 4) }

        glyphs = try reader.characterMap(at: try table("cmap"))

        guard tables["glyf"] != nil, tables["loca"] != nil else {
            throw ParseError.unsupportedOutlines
        }
        let glyphCount = Int(try reader.uint16(at: try table("maxp") + 4))
        let loca = try table("loca")
        glyphOffsets = try (0...glyphCount).map { index in
            longOffsets
                ? Int(try reader.uint32(at: loca + index * 4))
                : Int(try reader.uint16(at: loca + index * 2)) * 2
        }
        glyfOffset = try table("glyf")
        self.bytes = bytes
    }

    /// Inter Regular, the typeface Parhelion uses for regular-weight text.
    public static let interRegular = embedded(interRegularFontBase64, name: "Inter Regular")

    /// Inter Medium, for medium-weight text.
    public static let interMedium = embedded(interMediumFontBase64, name: "Inter Medium")

    /// Inter SemiBold, for semibold text such as headlines and the status
    /// bar's clock.
    public static let interSemiBold = embedded(interSemiBoldFontBase64, name: "Inter SemiBold")

    /// Inter Bold, for bold text such as large navigation titles.
    public static let interBold = embedded(interBoldFontBase64, name: "Inter Bold")

    private static func embedded(_ base64: String, name: String) -> TrueTypeFont {
        guard
            let data = Data(base64Encoded: base64),
            let font = try? TrueTypeFont(bytes: [UInt8](data))
        else {
            fatalError("The embedded \(name) font data is unreadable.")
        }
        return font
    }

    // MARK: - Metrics

    /// The glyph for a character, or glyph 0 (the missing-glyph symbol) if the
    /// font does not contain it.
    public func glyph(for scalar: Unicode.Scalar) -> UInt16 {
        glyphs[scalar.value] ?? 0
    }

    /// The advance width of a glyph, in font units.
    public func advance(ofGlyph glyph: UInt16) -> Int {
        guard !advances.isEmpty else { return 0 }
        return Int(advances[min(Int(glyph), advances.count - 1)])
    }

    /// The width of a string at the given point size, with ``tracking(size:)``
    /// after every character.
    public func width(of text: some StringProtocol, size: Double) -> Double {
        var units = 0
        var count = 0
        for scalar in text.unicodeScalars {
            units += advance(ofGlyph: glyph(for: scalar))
            count += 1
        }
        return Double(units) * size / Double(unitsPerEm) + Double(count) * tracking(size: size)
    }

    /// The space added after every character at a point size, in points, to
    /// bring Inter's widths closer to San Francisco's.
    ///
    /// Inter's own dynamic metrics: a tracking of
    /// `-0.0223 + 0.185 * exp(-0.1745 * size)` em, which is nearly none at
    /// 12 points, about -0.2 points at 17, and -0.02 em from 28 points up.
    /// See docs/adr/0019-layout-and-glyph-caches-and-letter-spacing.md.
    public func tracking(size: Double) -> Double {
        return (Self.trackingA + Self.trackingB * exp(Self.trackingC * size)) * size
    }

    private static let trackingA = -0.0223
    private static let trackingB = 0.185
    private static let trackingC = -0.1745

    /// The height of capital letters at the given point size.
    public func capHeight(size: Double) -> Double {
        Double(capHeight) * size / Double(unitsPerEm)
    }

    /// The distance between the baselines of two lines at the given point size.
    public func lineHeight(size: Double) -> Double {
        Double(ascender - descender + lineGap) * size / Double(unitsPerEm)
    }

    // MARK: - Outlines

    /// The outline of a glyph in font units, with y pointing up.
    public func outline(ofGlyph glyph: UInt16) -> Path {
        if let path = outlines[glyph] { return path }
        var path = Path()
        appendOutline(ofGlyph: glyph, to: &path, transform: .identity, depth: 0)
        outlines[glyph] = path
        return path
    }

    /// The anti-aliased coverage of a glyph with its origin at a quarter
    /// pixel, `phaseX` and `phaseY` in `0..<4` quarters right of and below a
    /// pixel corner, at `pixelSize` pixels per em. Coordinates in the
    /// result are relative to that corner, with y pointing down. `nil` for a
    /// glyph with no ink, such as a space.
    ///
    /// Kept for the next time the same glyph is drawn at the same size and
    /// phase, which a line of text does for most of its letters.
    func coverage(
        ofGlyph glyph: UInt16, pixelSize: Double, phaseX: Int, phaseY: Int
    ) -> Coverage? {
        let key = CoverageCache.Key(
            glyph: glyph, pixelSize: pixelSize, phaseX: UInt8(phaseX), phaseY: UInt8(phaseY))
        if let kept = coverages[key] { return kept.coverage }
        var coverage: Coverage?
        let outline = outline(ofGlyph: glyph)
        if !outline.isEmpty {
            let scale = pixelSize / Double(unitsPerEm)
            let placed = outline.applying(
                scaleX: scale, scaleY: -scale, translateX: Double(phaseX) / 4,
                translateY: Double(phaseY) / 4)
            // No clip: the coverage is cropped to the canvas when it is drawn.
            coverage = Rasterizer.coverage(
                of: placed.polygons(tolerance: 0.2), clip: (-16384, -16384, 16384, 16384))
        }
        coverages[key] = CoverageCache.Entry(coverage: coverage)
        return coverage
    }

    /// The coverage made so far, by glyph, size, and position in a pixel.
    private final class CoverageCache: @unchecked Sendable {
        struct Key: Hashable {
            var glyph: UInt16
            var pixelSize: Double
            var phaseX: UInt8
            var phaseY: UInt8
        }

        struct Entry {
            var coverage: Coverage?
        }

        /// A cache that fills starts over.
        static let limit = 24_000

        private let lock = NSLock()
        private var entries: [Key: Entry] = [:]

        subscript(key: Key) -> Entry? {
            get {
                lock.lock()
                defer { lock.unlock() }
                return entries[key]
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                if entries.count >= Self.limit { entries.removeAll(keepingCapacity: true) }
                entries[key] = newValue
            }
        }
    }

    /// The outlines parsed so far, by glyph. A reference type so that the
    /// font stays a value and every copy shares the cache.
    private final class OutlineCache: @unchecked Sendable {
        private let lock = NSLock()
        private var paths: [UInt16: Path] = [:]

        subscript(glyph: UInt16) -> Path? {
            get {
                lock.lock()
                defer { lock.unlock() }
                return paths[glyph]
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                paths[glyph] = newValue
            }
        }
    }

    private func appendOutline(
        ofGlyph glyph: UInt16,
        to path: inout Path,
        transform: AffineTransform2D,
        depth: Int
    ) {
        let index = Int(glyph)
        guard depth < 8, index + 1 < glyphOffsets.count else { return }
        let start = glyfOffset + glyphOffsets[index]
        let end = glyfOffset + glyphOffsets[index + 1]
        guard end > start else { return }  // An empty glyph, such as a space.
        let reader = ByteReader(bytes: bytes)
        guard let contourCount = try? reader.int16(at: start) else { return }
        if contourCount >= 0 {
            try? appendSimpleGlyph(
                at: start,
                contourCount: Int(contourCount),
                to: &path,
                transform: transform
            )
        } else {
            try? appendCompositeGlyph(at: start, to: &path, transform: transform, depth: depth)
        }
    }

    private struct OutlinePoint {
        var x: Double
        var y: Double
        var onCurve: Bool
    }

    private func appendSimpleGlyph(
        at start: Int,
        contourCount: Int,
        to path: inout Path,
        transform: AffineTransform2D
    ) throws {
        let reader = ByteReader(bytes: bytes)
        var endPoints: [Int] = []
        for contour in 0..<contourCount {
            endPoints.append(Int(try reader.uint16(at: start + 10 + contour * 2)))
        }
        let pointCount = (endPoints.last ?? -1) + 1
        let instructionLength = Int(try reader.uint16(at: start + 10 + contourCount * 2))
        var offset = start + 12 + contourCount * 2 + instructionLength

        var flags: [UInt8] = []
        while flags.count < pointCount {
            let flag = try reader.uint8(at: offset)
            offset += 1
            flags.append(flag)
            if flag & 0x08 != 0 {
                let repeats = Int(try reader.uint8(at: offset))
                offset += 1
                flags += [UInt8](repeating: flag, count: repeats)
            }
        }
        flags = Array(flags.prefix(pointCount))

        func coordinates(shortBit: UInt8, sameBit: UInt8) throws -> [Double] {
            var value = 0
            var result: [Double] = []
            for flag in flags {
                if flag & shortBit != 0 {
                    let delta = Int(try reader.uint8(at: offset))
                    offset += 1
                    value += flag & sameBit != 0 ? delta : -delta
                } else if flag & sameBit == 0 {
                    value += Int(try reader.int16(at: offset))
                    offset += 2
                }
                result.append(Double(value))
            }
            return result
        }
        let xs = try coordinates(shortBit: 0x02, sameBit: 0x10)
        let ys = try coordinates(shortBit: 0x04, sameBit: 0x20)

        var contourStart = 0
        for contourEnd in endPoints {
            guard contourEnd >= contourStart, contourEnd < pointCount else { break }
            let points = (contourStart...contourEnd).map { index in
                let point = transform.apply(CGPoint(x: xs[index], y: ys[index]))
                return OutlinePoint(
                    x: Double(point.x),
                    y: Double(point.y),
                    onCurve: flags[index] & 0x01 != 0
                )
            }
            appendContour(points, to: &path)
            contourStart = contourEnd + 1
        }
    }

    /// Converts a contour of on- and off-curve points to path elements. Two
    /// consecutive off-curve points imply an on-curve point midway between
    /// them.
    private func appendContour(_ points: [OutlinePoint], to path: inout Path) {
        guard !points.isEmpty else { return }
        func midpoint(_ a: OutlinePoint, _ b: OutlinePoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        func cgPoint(_ point: OutlinePoint) -> CGPoint {
            CGPoint(x: point.x, y: point.y)
        }

        // Start at an on-curve point. If there is none, start midway between
        // the first two off-curve points.
        let firstOnCurve = points.firstIndex(where: \.onCurve)
        let startIndex: Int
        let startPoint: CGPoint
        if let firstOnCurve {
            startIndex = firstOnCurve
            startPoint = cgPoint(points[firstOnCurve])
        } else {
            startIndex = 0
            startPoint = midpoint(points[0], points[points.count > 1 ? 1 : 0])
        }
        path.move(to: startPoint)

        var control: OutlinePoint?
        for step in 1...points.count {
            let point = points[(startIndex + step) % points.count]
            if point.onCurve {
                if let pending = control {
                    path.addQuadCurve(to: cgPoint(point), control: cgPoint(pending))
                    control = nil
                } else {
                    path.addLine(to: cgPoint(point))
                }
            } else if let pending = control {
                path.addQuadCurve(to: midpoint(pending, point), control: cgPoint(pending))
                control = point
            } else {
                control = point
            }
        }
        if let pending = control {
            path.addQuadCurve(to: startPoint, control: cgPoint(pending))
        }
        path.closeSubpath()
    }

    private func appendCompositeGlyph(
        at start: Int,
        to path: inout Path,
        transform: AffineTransform2D,
        depth: Int
    ) throws {
        let reader = ByteReader(bytes: bytes)
        var offset = start + 10
        while true {
            let flags = try reader.uint16(at: offset)
            let component = try reader.uint16(at: offset + 2)
            offset += 4

            var dx = 0.0
            var dy = 0.0
            if flags & 0x0001 != 0 {
                dx = Double(try reader.int16(at: offset))
                dy = Double(try reader.int16(at: offset + 2))
                offset += 4
            } else {
                dx = Double(Int8(bitPattern: try reader.uint8(at: offset)))
                dy = Double(Int8(bitPattern: try reader.uint8(at: offset + 1)))
                offset += 2
            }
            // Components positioned by matching points (flag 0x0002 clear)
            // are rare in modern fonts; Parhelion places them at the origin.
            if flags & 0x0002 == 0 {
                dx = 0
                dy = 0
            }

            func f2dot14(_ offset: Int) throws -> Double {
                Double(try reader.int16(at: offset)) / 16384
            }
            var a = 1.0
            var b = 0.0
            var c = 0.0
            var d = 1.0
            if flags & 0x0008 != 0 {
                a = try f2dot14(offset)
                d = a
                offset += 2
            } else if flags & 0x0040 != 0 {
                a = try f2dot14(offset)
                d = try f2dot14(offset + 2)
                offset += 4
            } else if flags & 0x0080 != 0 {
                a = try f2dot14(offset)
                b = try f2dot14(offset + 2)
                c = try f2dot14(offset + 4)
                d = try f2dot14(offset + 6)
                offset += 8
            }

            let local = AffineTransform2D(a: a, b: b, c: c, d: d, tx: dx, ty: dy)
            appendOutline(
                ofGlyph: component,
                to: &path,
                transform: transform.concatenating(local),
                depth: depth + 1
            )
            guard flags & 0x0020 != 0 else { break }
        }
    }
}

/// A 2D affine transform: `x' = a*x + c*y + tx`, `y' = b*x + d*y + ty`.
struct AffineTransform2D: Sendable {
    var a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double

    static let identity = AffineTransform2D(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    func apply(_ point: CGPoint) -> CGPoint {
        let x = Double(point.x)
        let y = Double(point.y)
        return CGPoint(x: a * x + c * y + tx, y: b * x + d * y + ty)
    }

    /// The transform that applies `inner` first, then `self`.
    func concatenating(_ inner: AffineTransform2D) -> AffineTransform2D {
        AffineTransform2D(
            a: a * inner.a + c * inner.b,
            b: b * inner.a + d * inner.b,
            c: a * inner.c + c * inner.d,
            d: b * inner.c + d * inner.d,
            tx: a * inner.tx + c * inner.ty + tx,
            ty: b * inner.tx + d * inner.ty + ty
        )
    }
}

/// Reads big-endian values from a font file, with bounds checks.
private struct ByteReader {
    let bytes: [UInt8]

    func uint8(at offset: Int) throws -> UInt8 {
        guard offset >= 0, offset < bytes.count else { throw TrueTypeFont.ParseError.truncated }
        return bytes[offset]
    }

    func uint16(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= bytes.count else {
            throw TrueTypeFont.ParseError.truncated
        }
        return UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    func int16(at offset: Int) throws -> Int16 {
        Int16(bitPattern: try uint16(at: offset))
    }

    func uint32(at offset: Int) throws -> UInt32 {
        UInt32(try uint16(at: offset)) << 16 | UInt32(try uint16(at: offset + 2))
    }

    /// The offset of each table, keyed by its four-letter tag.
    func tableDirectory() throws -> [String: Int] {
        let count = Int(try uint16(at: 4))
        var tables: [String: Int] = [:]
        for index in 0..<count {
            let record = 12 + index * 16
            guard record + 16 <= bytes.count else { throw TrueTypeFont.ParseError.truncated }
            let tag = String(decoding: bytes[record..<record + 4], as: UTF8.self)
            tables[tag] = Int(try uint32(at: record + 8))
        }
        return tables
    }

    /// The character-to-glyph map, from a format 12 subtable if the font has
    /// one, otherwise from a format 4 subtable.
    func characterMap(at cmap: Int) throws -> [UInt32: UInt16] {
        let count = Int(try uint16(at: cmap + 2))
        var format4: Int?
        for index in 0..<count {
            let record = cmap + 4 + index * 8
            let platform = try uint16(at: record)
            let encoding = try uint16(at: record + 2)
            let subtable = cmap + Int(try uint32(at: record + 4))
            let format = try uint16(at: subtable)
            if format == 12, (platform == 3 && encoding == 10) || platform == 0 {
                return try format12(at: subtable)
            }
            if format == 4, (platform == 3 && encoding == 1) || platform == 0 {
                format4 = subtable
            }
        }
        guard let format4 else { throw TrueTypeFont.ParseError.unsupportedCharacterMap }
        return try self.format4(at: format4)
    }

    private func format12(at offset: Int) throws -> [UInt32: UInt16] {
        let groupCount = Int(try uint32(at: offset + 12))
        var map: [UInt32: UInt16] = [:]
        for index in 0..<groupCount {
            let group = offset + 16 + index * 12
            let start = try uint32(at: group)
            let end = try uint32(at: group + 4)
            let firstGlyph = try uint32(at: group + 8)
            guard start <= end, end - start < 0x10000 else { continue }
            for scalar in start...end {
                map[scalar] = UInt16(truncatingIfNeeded: firstGlyph + (scalar - start))
            }
        }
        return map
    }

    private func format4(at offset: Int) throws -> [UInt32: UInt16] {
        let segmentCount = Int(try uint16(at: offset + 6)) / 2
        let endCodes = offset + 14
        let startCodes = endCodes + segmentCount * 2 + 2
        let deltas = startCodes + segmentCount * 2
        let rangeOffsets = deltas + segmentCount * 2
        var map: [UInt32: UInt16] = [:]
        for segment in 0..<segmentCount {
            let end = try uint16(at: endCodes + segment * 2)
            let start = try uint16(at: startCodes + segment * 2)
            let delta = try uint16(at: deltas + segment * 2)
            let rangeOffsetPosition = rangeOffsets + segment * 2
            let rangeOffset = Int(try uint16(at: rangeOffsetPosition))
            guard start <= end, start != 0xFFFF else { continue }
            for code in start...end {
                var glyph: UInt16
                if rangeOffset == 0 {
                    glyph = code &+ delta
                } else {
                    let address = rangeOffsetPosition + rangeOffset + Int(code - start) * 2
                    glyph = try uint16(at: address)
                    if glyph != 0 { glyph = glyph &+ delta }
                }
                if glyph != 0 { map[UInt32(code)] = glyph }
            }
        }
        return map
    }
}
