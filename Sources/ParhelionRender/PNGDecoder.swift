#if canImport(Foundation)
import Foundation
#endif

extension Bitmap {
    /// Why PNG data could not be decoded.
    public enum PNGError: Error, Equatable {
        /// The data does not start with the PNG signature.
        case notPNG
        /// The data ended before the image did.
        case truncated
        /// The image uses a feature the PNG standard does not define.
        case invalid(String)
    }

    /// Decodes a PNG image.
    ///
    /// Every standard color type and bit depth is read: grayscale, RGB,
    /// palette, grayscale with alpha, and RGBA, at 1 to 16 bits, with
    /// transparency from `tRNS`, all five row filters, and Adam7
    /// interlacing. Sixteen-bit samples keep their high byte. Gamma and
    /// color profiles are ignored, so colors are taken as sRGB.
    public init(pngData data: [UInt8]) throws(PNGError) {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.count >= 8, Array(data[0..<8]) == signature else { throw .notPNG }
        var header: PNGHeader?
        var palette: [RGBA] = []
        var transparency: [UInt8] = []
        var compressed: [UInt8] = []
        var offset = 8
        func uint32(at index: Int) -> Int {
            Int(data[index]) << 24 | Int(data[index + 1]) << 16 | Int(data[index + 2]) << 8
                | Int(data[index + 3])
        }
        chunks: while true {
            guard offset + 8 <= data.count else { throw .truncated }
            let length = uint32(at: offset)
            let type = String(decoding: data[(offset + 4)..<(offset + 8)], as: UTF8.self)
            let start = offset + 8
            guard length >= 0, start + length + 4 <= data.count else { throw .truncated }
            let body = data[start..<(start + length)]
            switch type {
            case "IHDR":
                header = try PNGHeader(body)
            case "PLTE":
                guard length % 3 == 0 else { throw .invalid("bad palette length") }
                palette = stride(from: body.startIndex, to: body.endIndex, by: 3).map {
                    RGBA(red: data[$0], green: data[$0 + 1], blue: data[$0 + 2])
                }
            case "tRNS":
                transparency = Array(body)
            case "IDAT":
                compressed += body
            case "IEND":
                break chunks
            default:
                break
            }
            offset = start + length + 4
        }
        guard let header else { throw .invalid("no IHDR chunk") }
        guard header.colorType != 3 || !palette.isEmpty else { throw .invalid("no palette") }
        let raw: [UInt8]
        do {
            raw = try Inflate.zlib(compressed, expectedSize: header.rawSize)
        } catch .truncated {
            throw .truncated
        } catch {
            throw .invalid("bad image data")
        }
        var output = [UInt8](repeating: 0, count: header.width * header.height * 4)
        var cursor = 0
        // An interlaced image is seven smaller images, each a pass over a
        // grid of pixels.
        let passes: [(x: Int, y: Int, dx: Int, dy: Int)] =
            header.interlaced
            ? [
                (0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2),
                (0, 1, 1, 2),
            ]
            : [(0, 0, 1, 1)]
        for pass in passes {
            let columns = (header.width - pass.x + pass.dx - 1) / pass.dx
            let rows = (header.height - pass.y + pass.dy - 1) / pass.dy
            guard columns > 0, rows > 0 else { continue }
            let rowBytes = (columns * header.bitsPerPixel + 7) / 8
            let pixels = try Self.unfilter(
                raw, at: cursor, rows: rows, rowBytes: rowBytes,
                bytesPerPixel: max(header.bitsPerPixel / 8, 1))
            cursor += rows * (rowBytes + 1)
            for row in 0..<rows {
                for column in 0..<columns {
                    let color = header.color(
                        in: pixels, row: row, column: column, rowBytes: rowBytes, palette: palette,
                        transparency: transparency)
                    let index =
                        ((pass.y + row * pass.dy) * header.width + pass.x + column * pass.dx) * 4
                    output[index] = color.red
                    output[index + 1] = color.green
                    output[index + 2] = color.blue
                    output[index + 3] = color.alpha
                }
            }
        }
        self.init(width: header.width, height: header.height, pixels: output)
    }

    /// Reverses the row filters of one image: each row starts with a filter
    /// byte, and the rows come back without them.
    private static func unfilter(
        _ data: [UInt8], at start: Int, rows: Int, rowBytes: Int, bytesPerPixel: Int
    ) throws(PNGError) -> [UInt8] {
        guard start + rows * (rowBytes + 1) <= data.count else { throw .truncated }
        var result = [UInt8](repeating: 0, count: rows * rowBytes)
        for row in 0..<rows {
            let filter = data[start + row * (rowBytes + 1)]
            let source = start + row * (rowBytes + 1) + 1
            let base = row * rowBytes
            for index in 0..<rowBytes {
                let value = data[source + index]
                let left = index >= bytesPerPixel ? Int(result[base + index - bytesPerPixel]) : 0
                let up = row > 0 ? Int(result[base - rowBytes + index]) : 0
                let upLeft =
                    row > 0 && index >= bytesPerPixel
                    ? Int(result[base - rowBytes + index - bytesPerPixel]) : 0
                let predicted: Int
                switch filter {
                case 0: predicted = 0
                case 1: predicted = left
                case 2: predicted = up
                case 3: predicted = (left + up) / 2
                case 4:
                    let estimate = left + up - upLeft
                    let distances = (
                        abs(estimate - left), abs(estimate - up), abs(estimate - upLeft)
                    )
                    predicted =
                        distances.0 <= distances.1 && distances.0 <= distances.2
                        ? left : distances.1 <= distances.2 ? up : upLeft
                default: throw .invalid("unknown filter \(filter)")
                }
                result[base + index] = value &+ UInt8(truncatingIfNeeded: predicted)
            }
        }
        return result
    }
}

/// The fields of a PNG image's `IHDR` chunk.
private struct PNGHeader {
    var width: Int
    var height: Int
    var bitDepth: Int
    var colorType: Int
    var interlaced: Bool

    init(_ body: ArraySlice<UInt8>) throws(Bitmap.PNGError) {
        guard body.count == 13 else { throw .invalid("bad IHDR length") }
        let bytes = Array(body)
        func uint32(_ index: Int) -> Int {
            Int(bytes[index]) << 24 | Int(bytes[index + 1]) << 16 | Int(bytes[index + 2]) << 8
                | Int(bytes[index + 3])
        }
        width = uint32(0)
        height = uint32(4)
        bitDepth = Int(bytes[8])
        colorType = Int(bytes[9])
        interlaced = bytes[12] == 1
        let depths: [Int: Set<Int>] = [
            0: [1, 2, 4, 8, 16], 2: [8, 16], 3: [1, 2, 4, 8], 4: [8, 16], 6: [8, 16],
        ]
        guard width > 0, height > 0, width <= 1 << 24, height <= 1 << 24 else {
            throw .invalid("bad size")
        }
        guard depths[colorType]?.contains(bitDepth) == true else {
            throw .invalid("bad color type \(colorType) at \(bitDepth) bits")
        }
        guard bytes[10] == 0, bytes[11] == 0, bytes[12] <= 1 else {
            throw .invalid("unknown compression, filter, or interlace method")
        }
    }

    /// Samples per pixel.
    var channels: Int {
        switch colorType {
        case 2: 3
        case 4: 2
        case 6: 4
        default: 1
        }
    }

    var bitsPerPixel: Int { channels * bitDepth }

    /// The size of the decompressed data, for reserving it.
    var rawSize: Int { height * ((width * bitsPerPixel + 7) / 8 + 1) }

    /// The color of one pixel of an unfiltered image.
    func color(
        in pixels: [UInt8], row: Int, column: Int, rowBytes: Int, palette: [RGBA],
        transparency: [UInt8]
    ) -> RGBA {
        let base = row * rowBytes
        /// A sample at the image's bit depth, as a number.
        func sample(_ channel: Int) -> Int {
            let bit = (column * channels + channel) * bitDepth
            switch bitDepth {
            case 16:
                return Int(pixels[base + bit / 8]) << 8 | Int(pixels[base + bit / 8 + 1])
            case 8:
                return Int(pixels[base + bit / 8])
            default:
                let byte = Int(pixels[base + bit / 8])
                return byte >> (8 - bitDepth - bit % 8) & ((1 << bitDepth) - 1)
            }
        }
        /// A sample scaled to 8 bits.
        func byte(_ value: Int) -> UInt8 {
            switch bitDepth {
            case 16: UInt8(value >> 8)
            case 8: UInt8(value)
            default: UInt8(value * 255 / ((1 << bitDepth) - 1))
            }
        }
        /// The 16-bit value of a `tRNS` entry.
        func key(_ index: Int) -> Int? {
            guard transparency.count >= index * 2 + 2 else { return nil }
            return Int(transparency[index * 2]) << 8 | Int(transparency[index * 2 + 1])
        }
        switch colorType {
        case 0:
            let gray = sample(0)
            let alpha: UInt8 = key(0) == gray ? 0 : 255
            return RGBA(red: byte(gray), green: byte(gray), blue: byte(gray), alpha: alpha)
        case 2:
            let red = sample(0)
            let green = sample(1)
            let blue = sample(2)
            let isKey = key(0) == red && key(1) == green && key(2) == blue
            return RGBA(
                red: byte(red), green: byte(green), blue: byte(blue), alpha: isKey ? 0 : 255)
        case 3:
            let index = sample(0)
            guard index < palette.count else { return .clear }
            var color = palette[index]
            if index < transparency.count { color.alpha = transparency[index] }
            return color
        case 4:
            let gray = byte(sample(0))
            return RGBA(red: gray, green: gray, blue: gray, alpha: byte(sample(1)))
        default:
            return RGBA(
                red: byte(sample(0)), green: byte(sample(1)), blue: byte(sample(2)),
                alpha: byte(sample(3)))
        }
    }
}

extension Bitmap {
    /// The width and height of a PNG image from its header, without
    /// decoding it, or `nil` if the data does not start like a PNG image.
    public static func pngSize(_ data: [UInt8]) -> (width: Int, height: Int)? {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.count >= 24, Array(data[0..<8]) == signature,
            String(decoding: data[12..<16], as: UTF8.self) == "IHDR"
        else { return nil }
        func uint32(_ index: Int) -> Int {
            Int(data[index]) << 24 | Int(data[index + 1]) << 16 | Int(data[index + 2]) << 8
                | Int(data[index + 3])
        }
        let width = uint32(16)
        let height = uint32(20)
        return width > 0 && height > 0 ? (width, height) : nil
    }
}
