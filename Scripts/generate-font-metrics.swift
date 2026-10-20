// Generates Sources/ParhelionUI/InterRegularMetrics.swift from a TrueType font.
//
// Usage:
//   swift Scripts/generate-font-metrics.swift Fonts/Inter-Regular.ttf \
//     > Sources/ParhelionUI/InterRegularMetrics.swift
//   swift format --in-place Sources/ParhelionUI/InterRegularMetrics.swift
//
// The script reads the `head`, `hhea`, `hmtx`, and `cmap` tables and writes
// the advance width of every character the font maps. Parhelion embeds these
// metrics as source because it cannot ship SwiftPM resources (see
// Package.swift).

import Foundation

enum ParseError: Error {
    case missingTable(String)
    case truncated
    case unsupportedCharacterMap
}

struct ByteReader {
    let bytes: [UInt8]

    func uint16(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= bytes.count else { throw ParseError.truncated }
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
            guard record + 16 <= bytes.count else { throw ParseError.truncated }
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
        guard let format4 else { throw ParseError.unsupportedCharacterMap }
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

func generate(fontPath: String) throws -> String {
    let reader = ByteReader(bytes: [UInt8](try Data(contentsOf: URL(fileURLWithPath: fontPath))))
    let tables = try reader.tableDirectory()
    func table(_ tag: String) throws -> Int {
        guard let offset = tables[tag] else { throw ParseError.missingTable(tag) }
        return offset
    }

    let head = try table("head")
    let unitsPerEm = try reader.uint16(at: head + 18)
    let hhea = try table("hhea")
    let ascender = try reader.int16(at: hhea + 4)
    let descender = try reader.int16(at: hhea + 6)
    let lineGap = try reader.int16(at: hhea + 8)
    let metricCount = Int(try reader.uint16(at: hhea + 34))
    let hmtx = try table("hmtx")
    let glyphAdvances = try (0..<metricCount).map { try reader.uint16(at: hmtx + $0 * 4) }
    func advance(ofGlyph glyph: UInt16) -> UInt16 {
        glyphAdvances[min(Int(glyph), glyphAdvances.count - 1)]
    }

    let map = try reader.characterMap(at: try table("cmap"))
    let scalars = map.keys.sorted()
    let advances = scalars.map { advance(ofGlyph: map[$0]!) }

    func list<T>(_ values: [T]) -> String {
        stride(from: 0, to: values.count, by: 12).map { start in
            "        "
                + values[start..<min(start + 12, values.count)].map { "\($0)," }
                .joined(separator: " ")
        }.joined(separator: "\n")
    }

    let fontName = URL(fileURLWithPath: fontPath).lastPathComponent
    return """
        // Generated by Scripts/generate-font-metrics.swift from Fonts/\(fontName).
        // Do not edit this file by hand.

        extension FontMetrics {
            /// The metrics of Inter Regular, the typeface Parhelion lays out text with.
            static let interRegular = FontMetrics(
                unitsPerEm: \(unitsPerEm),
                ascender: \(ascender),
                descender: \(descender),
                lineGap: \(lineGap),
                missingGlyphAdvance: \(advance(ofGlyph: 0)),
                scalars: interRegularScalars,
                advances: interRegularAdvances
            )
        }

        private let interRegularScalars: [UInt32] = [
        \(list(scalars))
        ]

        private let interRegularAdvances: [UInt16] = [
        \(list(advances))
        ]

        """
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: generate-font-metrics.swift FONT.ttf\n".utf8))
    exit(2)
}
do {
    print(try generate(fontPath: CommandLine.arguments[1]), terminator: "")
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
