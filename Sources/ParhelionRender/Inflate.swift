#if canImport(Foundation)
import Foundation
#endif

/// Decompression of deflate data (RFC 1951) and of zlib streams (RFC 1950),
/// for reading PNG images.
///
/// It handles all three kinds of deflate blocks: stored, fixed Huffman,
/// and dynamic Huffman. Each Huffman code is decoded through a table
/// indexed by as many bits as its longest code, so a symbol takes one
/// lookup.
enum Inflate {
    enum Error: Swift.Error, Equatable {
        /// The data ended in the middle of the stream.
        case truncated
        /// The stream is not valid deflate or zlib data.
        case invalid(String)
    }

    /// The data a zlib stream holds. The checksum at its end must match.
    static func zlib(_ data: [UInt8], expectedSize: Int = 0) throws(Error) -> [UInt8] {
        guard data.count >= 6 else { throw .truncated }
        let method = data[0] & 0x0F
        guard method == 8, (UInt16(data[0]) << 8 | UInt16(data[1])) % 31 == 0 else {
            throw .invalid("not a zlib stream")
        }
        guard data[1] & 0x20 == 0 else { throw .invalid("preset dictionaries are not supported") }
        var reader = BitReader(data, start: 2)
        let output = try inflate(&reader, expectedSize: expectedSize)
        let end = reader.byteOffsetAfterAligning
        guard end + 4 <= data.count else { throw .truncated }
        let stored =
            UInt32(data[end]) << 24 | UInt32(data[end + 1]) << 16 | UInt32(data[end + 2]) << 8
            | UInt32(data[end + 3])
        guard stored == PNGEncoder.adler32(output) else { throw .invalid("checksum mismatch") }
        return output
    }

    /// The data a raw deflate stream holds.
    static func deflate(_ data: [UInt8], expectedSize: Int = 0) throws(Error) -> [UInt8] {
        var reader = BitReader(data, start: 0)
        return try inflate(&reader, expectedSize: expectedSize)
    }

    private static func inflate(
        _ reader: inout BitReader, expectedSize: Int
    ) throws(Error)
        -> [UInt8]
    {
        var output: [UInt8] = []
        output.reserveCapacity(expectedSize)
        var isFinal = false
        while !isFinal {
            isFinal = try reader.bits(1) == 1
            switch try reader.bits(2) {
            case 0:
                try copyStored(&reader, into: &output)
            case 1:
                try inflateBlock(
                    &reader, literals: fixedLiterals, distances: fixedDistances, into: &output)
            case 2:
                let (literals, distances) = try readDynamicCodes(&reader)
                try inflateBlock(&reader, literals: literals, distances: distances, into: &output)
            default:
                throw .invalid("reserved block type")
            }
        }
        return output
    }

    private static func copyStored(
        _ reader: inout BitReader, into output: inout [UInt8]
    )
        throws(Error)
    {
        let start = reader.byteOffsetAfterAligning
        guard start + 4 <= reader.data.count else { throw .truncated }
        let length = Int(reader.data[start]) | Int(reader.data[start + 1]) << 8
        let complement = Int(reader.data[start + 2]) | Int(reader.data[start + 3]) << 8
        guard length == ~complement & 0xFFFF else { throw .invalid("bad stored block length") }
        guard start + 4 + length <= reader.data.count else { throw .truncated }
        output += reader.data[(start + 4)..<(start + 4 + length)]
        reader.restart(at: start + 4 + length)
    }

    // MARK: - Huffman codes

    /// A canonical Huffman code as a lookup table: indexed by the next
    /// `bits` bits of input, least significant first, each entry is the
    /// symbol shifted left by 4 and the length of its code.
    struct Code {
        let table: [UInt32]
        let bits: Int

        /// The code with the given length for each symbol; 0 means the
        /// symbol does not occur.
        init(lengths: [Int]) throws(Error) {
            guard let code = Code(checking: lengths) else {
                throw .invalid("oversubscribed Huffman code")
            }
            self = code
        }

        /// The code for lengths, or `nil` if they give more codes of some
        /// length than there are.
        init?(checking lengths: [Int]) {
            let longest = lengths.max() ?? 0
            bits = max(longest, 1)
            var counts = [Int](repeating: 0, count: 16)
            for length in lengths where length > 0 { counts[length] += 1 }
            // The first code of each length, as RFC 1951 section 3.2.2 builds them.
            var next = [Int](repeating: 0, count: 16)
            var code = 0
            for length in 1...15 {
                code = (code + counts[length - 1]) << 1
                next[length] = code
            }
            var table = [UInt32](repeating: 0, count: 1 << bits)
            for (symbol, length) in lengths.enumerated() where length > 0 {
                let value = next[length]
                next[length] += 1
                guard value < 1 << length else { return nil }
                // Codes are stored most significant bit first; the input is
                // read least significant bit first.
                var reversed = 0
                for bit in 0..<length where value & (1 << bit) != 0 {
                    reversed |= 1 << (length - 1 - bit)
                }
                let entry = UInt32(symbol) << 4 | UInt32(length)
                var index = reversed
                while index < 1 << bits {
                    table[index] = entry
                    index += 1 << length
                }
            }
            self.table = table
        }

        @inline(__always)
        func decode(_ reader: inout BitReader) throws(Error) -> Int {
            let entry = table[Int(reader.peek(bits))]
            let length = Int(entry & 0xF)
            guard length > 0 else { throw .invalid("unknown Huffman code") }
            try reader.consume(length)
            return Int(entry >> 4)
        }
    }

    private static let fixedLiterals: Code = {
        var lengths = [Int](repeating: 8, count: 288)
        for symbol in 144..<256 { lengths[symbol] = 9 }
        for symbol in 256..<280 { lengths[symbol] = 7 }
        // The fixed lengths form a complete code.
        return Code(checking: lengths)!
    }()

    private static let fixedDistances = Code(checking: [Int](repeating: 5, count: 30))!

    /// Reads a dynamic block's literal and length code and its distance
    /// code.
    private static func readDynamicCodes(_ reader: inout BitReader) throws(Error) -> (Code, Code) {
        let literalCount = try reader.bits(5) + 257
        let distanceCount = try reader.bits(5) + 1
        let lengthCodeCount = try reader.bits(4) + 4
        let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
        var lengthLengths = [Int](repeating: 0, count: 19)
        for index in 0..<lengthCodeCount {
            lengthLengths[order[index]] = try reader.bits(3)
        }
        let lengthCode = try Code(lengths: lengthLengths)
        var lengths: [Int] = []
        lengths.reserveCapacity(literalCount + distanceCount)
        while lengths.count < literalCount + distanceCount {
            let symbol = try lengthCode.decode(&reader)
            switch symbol {
            case 0...15:
                lengths.append(symbol)
            case 16:
                guard let previous = lengths.last else { throw .invalid("repeat with no length") }
                lengths += repeatElement(previous, count: try reader.bits(2) + 3)
            case 17:
                lengths += repeatElement(0, count: try reader.bits(3) + 3)
            default:
                lengths += repeatElement(0, count: try reader.bits(7) + 11)
            }
        }
        guard lengths.count == literalCount + distanceCount else {
            throw .invalid("code lengths overrun")
        }
        guard lengths[256] > 0 else { throw .invalid("no end-of-block code") }
        return (
            try Code(lengths: Array(lengths[..<literalCount])),
            try Code(lengths: Array(lengths[literalCount...]))
        )
    }

    private static let lengthBases = [
        3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
        35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258,
    ]
    private static let lengthExtraBits = [
        0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
        3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
    ]
    private static let distanceBases = [
        1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
        257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
    ]
    private static let distanceExtraBits = [
        0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
        7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13,
    ]

    private static func inflateBlock(
        _ reader: inout BitReader, literals: Code, distances: Code, into output: inout [UInt8]
    ) throws(Error) {
        while true {
            let symbol = try literals.decode(&reader)
            if symbol < 256 {
                output.append(UInt8(symbol))
                continue
            }
            if symbol == 256 { return }
            let lengthIndex = symbol - 257
            guard lengthIndex < lengthBases.count else { throw .invalid("bad length symbol") }
            let length = lengthBases[lengthIndex] + (try reader.bits(lengthExtraBits[lengthIndex]))
            let distanceIndex = try distances.decode(&reader)
            guard distanceIndex < distanceBases.count else { throw .invalid("bad distance symbol") }
            let distance =
                distanceBases[distanceIndex] + (try reader.bits(distanceExtraBits[distanceIndex]))
            guard distance <= output.count else { throw .invalid("distance too far back") }
            let start = output.count - distance
            if distance >= length {
                output.append(contentsOf: output[start..<(start + length)])
            } else {
                // The match overlaps what it copies, so it repeats.
                for offset in 0..<length { output.append(output[start + offset]) }
            }
        }
    }
}

/// Reads bits least significant first, as deflate stores them.
struct BitReader {
    let data: [UInt8]
    private var position: Int
    private var buffer: UInt64 = 0
    private var count = 0

    init(_ data: [UInt8], start: Int) {
        self.data = data
        position = start
    }

    /// Keeps at least 32 bits in the buffer while there is input.
    @inline(__always)
    private mutating func refill() {
        while count <= 56, position < data.count {
            buffer |= UInt64(data[position]) << UInt64(count)
            position += 1
            count += 8
        }
    }

    /// The next `n` bits without consuming them; past the end of the input
    /// they are zero.
    @inline(__always)
    mutating func peek(_ n: Int) -> UInt64 {
        if count < n { refill() }
        return buffer & ((1 << UInt64(n)) - 1)
    }

    @inline(__always)
    mutating func consume(_ n: Int) throws(Inflate.Error) {
        if count < n { refill() }
        guard count >= n else { throw .truncated }
        buffer >>= UInt64(n)
        count -= n
    }

    /// Reads `n` bits, up to 32, as a number.
    @inline(__always)
    mutating func bits(_ n: Int) throws(Inflate.Error) -> Int {
        guard n > 0 else { return 0 }
        let value = Int(peek(n))
        try consume(n)
        return value
    }

    /// Skips to the next whole byte, and returns the offset of that byte in
    /// the input.
    var byteOffsetAfterAligning: Int {
        mutating get {
            let skip = count % 8
            buffer >>= UInt64(skip)
            count -= skip
            return position - count / 8
        }
    }

    /// Continues reading from a byte offset, forgetting buffered bits.
    mutating func restart(at offset: Int) {
        position = offset
        buffer = 0
        count = 0
    }
}
