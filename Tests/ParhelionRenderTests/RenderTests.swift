import Foundation
import Testing

@testable import ParhelionRender

@Suite("Font")
struct FontTests {
    let font = TrueTypeFont.interRegular

    @Test("The embedded font parses with plausible metrics")
    func metrics() {
        #expect(font.unitsPerEm == 2048)
        #expect(font.ascender > 0)
        #expect(font.descender < 0)
        #expect(
            font.advance(ofGlyph: font.glyph(for: "M"))
                > font.advance(ofGlyph: font.glyph(for: "i")))
    }

    @Test("Letters have outlines and spaces do not")
    func outlines() {
        #expect(!font.outline(ofGlyph: font.glyph(for: "A")).isEmpty)
        #expect(font.outline(ofGlyph: font.glyph(for: " ")).isEmpty)
    }

    @Test("Composite glyphs, such as accented letters, have outlines")
    func compositeGlyphs() {
        let plain = font.outline(ofGlyph: font.glyph(for: "e")).polygons(tolerance: 1)
        let accented = font.outline(ofGlyph: font.glyph(for: "é")).polygons(tolerance: 1)
        #expect(accented.count > plain.count)
    }

    @Test("Characters the font lacks use the missing glyph")
    func missingGlyph() {
        #expect(font.glyph(for: "\u{10FFFD}") == 0)
    }

    @Test("The cap height comes from the OS/2 table")
    func capHeight() {
        #expect(font.capHeight > 0 && font.capHeight < font.ascender)
        #expect(abs(font.capHeight(size: 2048) - Double(font.capHeight)) < 1e-9)
    }

    @Test("SemiBold glyphs are wider than Regular ones")
    func semiBold() {
        let semiBold = TrueTypeFont.interSemiBold
        #expect(semiBold.unitsPerEm == font.unitsPerEm)
        #expect(semiBold.width(of: "9:41", size: 17) > font.width(of: "9:41", size: 17))
    }
}

@Suite("Rasterizer")
struct RasterizerTests {
    @Test("A pixel-aligned rectangle covers its pixels exactly")
    func alignedRectangle() throws {
        let coverage = try #require(
            Rasterizer.coverage(
                of: Path(CGRect(x: 2, y: 3, width: 4, height: 2)).polygons(tolerance: 0.2),
                clipWidth: 10,
                clipHeight: 10
            )
        )
        #expect(coverage.originX == 2 && coverage.originY == 3)
        #expect(coverage.width == 4 && coverage.height == 2)
        #expect(coverage.values.allSatisfy { abs($0 - 1) < 0.0001 })
    }

    @Test("A half-covered pixel gets half coverage")
    func halfPixel() throws {
        let coverage = try #require(
            Rasterizer.coverage(
                of: Path(CGRect(x: 0.5, y: 0, width: 1, height: 1)).polygons(tolerance: 0.2),
                clipWidth: 10,
                clipHeight: 10
            )
        )
        #expect(coverage.values.count == 2)
        #expect(coverage.values.allSatisfy { abs($0 - 0.5) < 0.0001 })
    }

    @Test("Shapes outside the target are clipped")
    func clipping() throws {
        let partial = try #require(
            Rasterizer.coverage(
                of: Path(CGRect(x: -5, y: -5, width: 10, height: 10)).polygons(tolerance: 0.2),
                clipWidth: 3,
                clipHeight: 3
            )
        )
        #expect(partial.width == 3 && partial.height == 3)
        #expect(partial.values.allSatisfy { abs($0 - 1) < 0.0001 })

        let outside = Rasterizer.coverage(
            of: Path(CGRect(x: 20, y: 20, width: 5, height: 5)).polygons(tolerance: 0.2),
            clipWidth: 10,
            clipHeight: 10
        )
        #expect(outside == nil)
    }

    @Test("A reversed inner ellipse cuts a hole")
    func ringHole() throws {
        var ring = Path(ellipseIn: CGRect(x: 0, y: 0, width: 20, height: 20))
        ring.addPath(Path(ellipseIn: CGRect(x: 5, y: 5, width: 10, height: 10), reversed: true))
        let coverage = try #require(
            Rasterizer.coverage(of: ring.polygons(tolerance: 0.1), clipWidth: 20, clipHeight: 20)
        )
        #expect(coverage.values[10 * coverage.width + 10] < 0.01)  // The center is empty.
        #expect(coverage.values[10 * coverage.width + 2] > 0.99)  // The ring is filled.
    }

    @Test("A reversed inner rounded rectangle cuts a hole")
    func roundedRingHole() throws {
        var ring = Path(roundedRect: CGRect(x: 0, y: 0, width: 20, height: 20), cornerRadius: 4)
        ring.addPath(
            Path(
                roundedRect: CGRect(x: 5, y: 5, width: 10, height: 10), cornerRadius: 2,
                reversed: true))
        let coverage = try #require(
            Rasterizer.coverage(of: ring.polygons(tolerance: 0.1), clipWidth: 20, clipHeight: 20)
        )
        #expect(coverage.values[10 * coverage.width + 10] < 0.01)  // The center is empty.
        #expect(coverage.values[10 * coverage.width + 2] > 0.99)  // The ring is filled.
        // The hole is round at its corners, so the corner pixel is mostly filled.
        #expect(coverage.values[5 * coverage.width + 5] > 0.5)
    }
}

@Suite("Canvas")
struct CanvasTests {
    @Test("A canvas has scale × size pixels and starts with its background")
    func dimensions() {
        let canvas = Canvas(width: 10, height: 5, scale: 2, background: .white)
        #expect(canvas.width == 20 && canvas.height == 10)
        #expect(canvas.pixel(x: 19, y: 9) == .white)
    }

    @Test("Filling a rectangle colors exactly its pixels")
    func fillRectangle() {
        var canvas = Canvas(width: 10, height: 10, scale: 1, background: .white)
        let red = RGBA(red: 255, green: 0, blue: 0)
        canvas.fill(CGRect(x: 2, y: 2, width: 3, height: 3), color: red)
        #expect(canvas.pixel(x: 3, y: 3) == red)
        #expect(canvas.pixel(x: 1, y: 3) == .white)
        #expect(canvas.pixel(x: 5, y: 3) == .white)
    }

    @Test("Translucent colors blend with what is underneath")
    func blending() {
        var canvas = Canvas(width: 1, height: 1, scale: 1, background: .white)
        canvas.fill(
            CGRect(x: 0, y: 0, width: 1, height: 1),
            color: RGBA(red: 0, green: 0, blue: 0, alpha: 128))
        let pixel = canvas.pixel(x: 0, y: 0)
        #expect((126...128).contains(pixel.red))
        #expect(pixel.alpha == 255)
    }

    @Test("A translucent fill over several colors blends each run correctly")
    func translucentRuns() {
        var canvas = Canvas(width: 6, height: 1, scale: 1, background: .white)
        canvas.fill(CGRect(x: 3, y: 0, width: 3, height: 1), color: RGBA(red: 0, green: 0, blue: 0))
        var expected = canvas
        let gray = RGBA(red: 0, green: 0, blue: 0, alpha: 128)
        canvas.fill(CGRect(x: 0, y: 0, width: 6, height: 1), color: gray)
        for x in 0..<6 {
            expected.fill(CGRect(x: x, y: 0, width: 1, height: 1), color: gray)
        }
        #expect(canvas.pixels == expected.pixels)
    }

    @Test(
        "A rounded rectangle matches the general rasterizer, without seams",
        arguments: [1.0, 2.0, 3.0])
    func roundedRectangle(scale: Double) {
        let rect = CGRect(x: 3.3, y: 2.7, width: 40.2, height: 25.9)
        let color = RGBA(red: 0, green: 0, blue: 255)
        var fast = Canvas(width: 50, height: 32, scale: scale, background: .white)
        fast.fill(rect, cornerRadius: 8, color: color)
        var general = Canvas(width: 50, height: 32, scale: scale, background: .white)
        general.fill(Path(roundedRect: rect, cornerRadius: 8), color: color)
        let largest = zip(fast.pixels, general.pixels).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(largest <= 3)
    }

    @Test("Text draws ink inside its line box and none outside it")
    func text() {
        let font = TrueTypeFont.interRegular
        var canvas = Canvas(width: 100, height: 30, scale: 2, background: .white)
        canvas.drawText("Hello", font: font, size: 17, origin: CGPoint(x: 0, y: 20), color: .black)
        let width = Int((font.width(of: "Hello", size: 17) * 2).rounded(.up))
        var inkInside = 0
        var inkOutside = 0
        for y in 0..<canvas.height {
            for x in 0..<canvas.width where canvas.pixel(x: x, y: y) != .white {
                if x <= width { inkInside += 1 } else { inkOutside += 1 }
            }
        }
        #expect(inkInside > 100)
        #expect(inkOutside == 0)
    }
}

@Suite("PNG")
struct PNGTests {
    @Test("Encoded images decode back to the same pixels")
    func roundTrip() throws {
        var canvas = Canvas(width: 40, height: 30, scale: 1, background: .white)
        canvas.fill(
            CGRect(x: 5, y: 5, width: 20, height: 10), color: RGBA(red: 0, green: 122, blue: 255))
        canvas.drawText(
            "Hi", font: .interRegular, size: 17, origin: CGPoint(x: 2, y: 25), color: .black)

        let decoded = try PNGDecoder.decode(canvas.pngData())
        #expect(decoded.width == 40 && decoded.height == 30)
        #expect(decoded.rgba == canvas.pixels)
    }

    @Test("Flat images compress well")
    func compression() {
        let canvas = Canvas(width: 393, height: 852, scale: 2, background: .white)
        #expect(canvas.pngData().count < canvas.pixels.count / 100)
    }
}

/// A minimal PNG decoder for tests: it supports exactly what `PNGEncoder`
/// writes, fixed-Huffman deflate and the None, Sub, and Up filters, and
/// checks every CRC and the Adler-32 checksum.
enum PNGDecoder {
    struct Image {
        var width: Int
        var height: Int
        var rgba: [UInt8]
    }

    enum DecodeError: Error {
        case invalid(String)
    }

    static func decode(_ png: [UInt8]) throws -> Image {
        guard png.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) else {
            throw DecodeError.invalid("signature")
        }
        var offset = 8
        var width = 0
        var height = 0
        var compressed: [UInt8] = []
        func uint32(_ at: Int) -> Int {
            Int(png[at]) << 24 | Int(png[at + 1]) << 16 | Int(png[at + 2]) << 8 | Int(png[at + 3])
        }
        while offset < png.count {
            let length = uint32(offset)
            let type = String(decoding: png[offset + 4..<offset + 8], as: UTF8.self)
            let body = Array(png[offset + 8..<offset + 8 + length])
            let crc = UInt32(uint32(offset + 8 + length))
            guard CRC32.checksum(Array(png[offset + 4..<offset + 8 + length])) == crc else {
                throw DecodeError.invalid("CRC of \(type)")
            }
            switch type {
            case "IHDR":
                width = Int(body[0]) << 24 | Int(body[1]) << 16 | Int(body[2]) << 8 | Int(body[3])
                height = Int(body[4]) << 24 | Int(body[5]) << 16 | Int(body[6]) << 8 | Int(body[7])
            case "IDAT": compressed += body
            default: break
            }
            offset += 12 + length
        }

        let filtered = try inflate(Array(compressed.dropFirst(2).dropLast(4)))
        let checksum = compressed.suffix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard PNGEncoder.adler32(filtered) == checksum else {
            throw DecodeError.invalid("Adler-32")
        }

        let rowLength = width * 4
        var rgba = [UInt8](repeating: 0, count: rowLength * height)
        for row in 0..<height {
            let filter = filtered[row * (rowLength + 1)]
            for index in 0..<rowLength {
                let raw = filtered[row * (rowLength + 1) + 1 + index]
                let left: UInt8 = index >= 4 ? rgba[row * rowLength + index - 4] : 0
                let up: UInt8 = row > 0 ? rgba[(row - 1) * rowLength + index] : 0
                switch filter {
                case 0: rgba[row * rowLength + index] = raw
                case 1: rgba[row * rowLength + index] = raw &+ left
                case 2: rgba[row * rowLength + index] = raw &+ up
                default: throw DecodeError.invalid("filter \(filter)")
                }
            }
        }
        return Image(width: width, height: height, rgba: rgba)
    }

    private static func inflate(_ data: [UInt8]) throws -> [UInt8] {
        var bitIndex = 0
        func bits(_ count: Int) -> Int {
            var value = 0
            for bit in 0..<count {
                let byte = data[(bitIndex + bit) / 8]
                value |= Int((byte >> UInt8((bitIndex + bit) % 8)) & 1) << bit
            }
            bitIndex += count
            return value
        }
        func huffman(_ count: Int) -> Int {
            var value = 0
            for _ in 0..<count { value = value << 1 | bits(1) }
            return value
        }
        func symbol() -> Int {
            let seven = huffman(7)
            if seven <= 0b0010111 { return 256 + seven }
            let eight = seven << 1 | bits(1)
            if (0b0011_0000...0b1011_1111).contains(eight) { return eight - 0b0011_0000 }
            if (0b1100_0000...0b1100_0111).contains(eight) { return 280 + eight - 0b1100_0000 }
            let nine = eight << 1 | bits(1)
            return 144 + nine - 0b1_1001_0000
        }
        let lengthBases = [
            3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
            35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258,
        ]
        let lengthExtra = [
            0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
        ]

        guard bits(1) == 1, bits(2) == 1 else { throw DecodeError.invalid("block type") }
        var output: [UInt8] = []
        while true {
            let next = symbol()
            if next < 256 {
                output.append(UInt8(next))
            } else if next == 256 {
                break
            } else {
                let code = next - 257
                let length = lengthBases[code] + bits(lengthExtra[code])
                guard huffman(5) == 0 else { throw DecodeError.invalid("distance") }
                for _ in 0..<length { output.append(output[output.count - 1]) }
            }
        }
        return output
    }
}
