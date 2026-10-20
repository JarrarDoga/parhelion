extension Canvas {
    /// The canvas encoded as a PNG image.
    ///
    /// Rows are filtered so that flat areas become runs of zeros, and the
    /// runs are compressed with fixed-Huffman deflate. Screenshots of user
    /// interfaces, which are mostly flat color, compress well this way
    /// without a compression library.
    public func pngData() -> [UInt8] {
        PNGEncoder.encode(width: width, height: height, rgba: pixels)
    }
}

enum PNGEncoder {
    static func encode(width: Int, height: Int, rgba: [UInt8]) -> [UInt8] {
        var png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

        var header: [UInt8] = []
        header.appendBigEndian(UInt32(width))
        header.appendBigEndian(UInt32(height))
        header += [8, 6, 0, 0, 0]  // 8-bit RGBA, deflate, adaptive filtering, no interlace
        appendChunk("IHDR", header, to: &png)

        appendChunk("IDAT", zlib(filteredRows(width: width, height: height, rgba: rgba)), to: &png)
        appendChunk("IEND", [], to: &png)
        return png
    }

    /// Each row with its filter byte: "Up" when the row repeats the previous
    /// one, otherwise "Sub". Both turn flat color into zeros.
    static func filteredRows(width: Int, height: Int, rgba: [UInt8]) -> [UInt8] {
        let rowLength = width * 4
        var output: [UInt8] = []
        output.reserveCapacity((rowLength + 1) * height)
        for row in 0..<height {
            let start = row * rowLength
            let previousStart = start - rowLength
            let repeatsPrevious =
                row > 0 && rgba[start..<start + rowLength] == rgba[previousStart..<start]
            if repeatsPrevious {
                output.append(2)
                output += [UInt8](repeating: 0, count: rowLength)
            } else {
                output.append(1)
                for index in 0..<rowLength {
                    let left: UInt8 = index >= 4 ? rgba[start + index - 4] : 0
                    output.append(rgba[start + index] &- left)
                }
            }
        }
        return output
    }

    private static func appendChunk(_ type: String, _ data: [UInt8], to png: inout [UInt8]) {
        png.appendBigEndian(UInt32(data.count))
        let typeAndData = Array(type.utf8) + data
        png += typeAndData
        png.appendBigEndian(CRC32.checksum(typeAndData))
    }

    /// A zlib stream: header, deflate data, and Adler-32 checksum.
    static func zlib(_ data: [UInt8]) -> [UInt8] {
        var output: [UInt8] = [0x78, 0x01]
        output += Deflate.compress(data)
        output.appendBigEndian(adler32(data))
        return output
    }

    static func adler32(_ data: [UInt8]) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        var index = 0
        while index < data.count {
            // 5552 is the largest block that cannot overflow before the modulo.
            let end = min(index + 5552, data.count)
            while index < end {
                a += UInt32(data[index])
                b += a
                index += 1
            }
            a %= 65521
            b %= 65521
        }
        return b << 16 | a
    }
}

/// Deflate compression with the fixed Huffman code, using literals and
/// run-length matches at distance 1.
enum Deflate {
    static func compress(_ data: [UInt8]) -> [UInt8] {
        var writer = BitWriter()
        writer.write(1, bitCount: 1)  // Final block.
        writer.write(1, bitCount: 2)  // Fixed Huffman codes.

        var index = 0
        while index < data.count {
            // A run of the previous byte can be sent as a match at distance 1.
            if index > 0 {
                var length = 0
                let previous = data[index - 1]
                while length < 258, index + length < data.count, data[index + length] == previous {
                    length += 1
                }
                if length >= 3 {
                    writeLength(length, to: &writer)
                    writer.write(0, bitCount: 5)  // Distance code 0: distance 1.
                    index += length
                    continue
                }
            }
            writeLiteral(Int(data[index]), to: &writer)
            index += 1
        }
        writeLiteral(256, to: &writer)  // End of block.
        return writer.finish()
    }

    /// Writes a literal or length symbol with the fixed Huffman code.
    private static func writeLiteral(_ symbol: Int, to writer: inout BitWriter) {
        switch symbol {
        case 0...143: writer.writeHuffman(UInt32(0x30 + symbol), bitCount: 8)
        case 144...255: writer.writeHuffman(UInt32(0x190 + symbol - 144), bitCount: 9)
        case 256...279: writer.writeHuffman(UInt32(symbol - 256), bitCount: 7)
        default: writer.writeHuffman(UInt32(0xC0 + symbol - 280), bitCount: 8)
        }
    }

    private static let lengthBases = [
        3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
        35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258,
    ]
    private static let lengthExtraBits = [
        0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
        3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
    ]

    private static func writeLength(_ length: Int, to writer: inout BitWriter) {
        var code = lengthBases.count - 1
        while lengthBases[code] > length { code -= 1 }
        writeLiteral(257 + code, to: &writer)
        writer.write(UInt32(length - lengthBases[code]), bitCount: lengthExtraBits[code])
    }
}

/// Packs bits least-significant first, as deflate requires.
struct BitWriter {
    private var bytes: [UInt8] = []
    private var buffer: UInt32 = 0
    private var bufferedBits = 0

    mutating func write(_ value: UInt32, bitCount: Int) {
        guard bitCount > 0 else { return }
        buffer |= value << UInt32(bufferedBits)
        bufferedBits += bitCount
        while bufferedBits >= 8 {
            bytes.append(UInt8(truncatingIfNeeded: buffer))
            buffer >>= 8
            bufferedBits -= 8
        }
    }

    /// Writes a Huffman code, which deflate stores most-significant bit first.
    mutating func writeHuffman(_ code: UInt32, bitCount: Int) {
        var reversed: UInt32 = 0
        for bit in 0..<bitCount where code & (1 << UInt32(bit)) != 0 {
            reversed |= 1 << UInt32(bitCount - 1 - bit)
        }
        write(reversed, bitCount: bitCount)
    }

    mutating func finish() -> [UInt8] {
        if bufferedBits > 0 { bytes.append(UInt8(truncatingIfNeeded: buffer)) }
        buffer = 0
        bufferedBits = 0
        return bytes
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            crc = crc & 1 != 0 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1
        }
        return crc
    }

    static func checksum(_ data: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

extension Array where Element == UInt8 {
    mutating func appendBigEndian(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value >> 24))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value))
    }
}
