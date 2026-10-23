import Foundation
import ParhelionPreview

#if canImport(Glibc)
import Glibc
#endif

/// The newest frame the web preview has, as RGBA pixels. Each frame from
/// the app updates only its damaged rectangle.
struct FrameBuffer {
    private(set) var width = 0
    private(set) var height = 0
    private(set) var pixels: [UInt8] = []

    var isEmpty: Bool { pixels.isEmpty }

    /// The whole frame as a rectangle.
    var bounds: PixelRect { PixelRect(x: 0, y: 0, width: width, height: height) }

    /// Copies the damaged rectangle of a frame from `source`, row-major RGBA
    /// of `width` × `height` pixels, and returns the part of the buffer that
    /// changed: the damage, or the whole frame when its size changed.
    mutating func update(
        width: Int, height: Int, damage: PixelRect, from source: UnsafeRawBufferPointer
    ) -> PixelRect {
        guard width > 0, height > 0, source.count >= width * height * 4 else {
            return PixelRect(x: 0, y: 0, width: 0, height: 0)
        }
        var changed = damage.clamped(width: width, height: height)
        if width != self.width || height != self.height {
            self.width = width
            self.height = height
            pixels = [UInt8](repeating: 0, count: width * height * 4)
            changed = bounds
        }
        let rowBytes = changed.width * 4
        pixels.withUnsafeMutableBytes { destination in
            for row in changed.y..<(changed.y + changed.height) {
                let offset = (row * width + changed.x) * 4
                (destination.baseAddress! + offset).copyMemory(
                    from: source.baseAddress! + offset, byteCount: rowBytes)
            }
        }
        return changed
    }

    /// The pixels of a rectangle inside the frame, row by row.
    func region(_ rect: PixelRect) -> [UInt8] {
        let rowBytes = rect.width * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * rect.height)
        bytes.withUnsafeMutableBytes { destination in
            pixels.withUnsafeBytes { source in
                for row in 0..<rect.height {
                    (destination.baseAddress! + row * rowBytes).copyMemory(
                        from: source.baseAddress! + ((rect.y + row) * width + rect.x) * 4,
                        byteCount: rowBytes)
                }
            }
        }
        return bytes
    }
}

/// What one page has drawn: a copy of its canvas, kept on the host so
/// that each frame can be sent as the change from it.
///
/// Scrolling moves most of a frame's rows without changing them. When the
/// rows of a rectangle match the page's rows some distance above or below,
/// the page copies them within its canvas, and only the rows that still
/// differ travel, compressed. A fling then costs the rows it uncovers
/// instead of the whole scroll view.
struct PageImage {
    private(set) var width = 0
    private(set) var height = 0
    private var pixels: [UInt8] = []

    /// The fewest rows a copy must save to be worth sending.
    static let minimumCopiedRows = 16
    /// Changed rows closer together than this go in one part, so the page
    /// decompresses fewer, larger parts.
    static let mergeGap = 8
    /// The most rows in one part. Parts are compressed in parallel on the
    /// host and decompressed in parallel on the page.
    static let maximumPartRows = 256
    /// A row that appears more often than this in the page's rectangle,
    /// such as a row of plain background, says nothing about how far the
    /// content moved.
    static let maximumCandidates = 4

    /// The parts that turn the page's rectangle `rect` into `new`, its
    /// pixels row by row, in a frame of `frameWidth` × `frameHeight`
    /// pixels. Afterwards the image holds what the page will show.
    mutating func parts(
        for rect: PixelRect, new: [UInt8], frameWidth: Int, frameHeight: Int
    ) -> [FrameMessage.Part] {
        if frameWidth != width || frameHeight != height {
            // A page clears its canvas when the frame's size changes.
            width = frameWidth
            height = frameHeight
            pixels = [UInt8](repeating: 0, count: frameWidth * frameHeight * 4)
        }
        guard !rect.isEmpty else { return [] }
        let rowBytes = rect.width * 4
        let imageRowBytes = width * 4
        let rows = rect.height
        let origin = rect.y * imageRowBytes + rect.x * 4
        var parts: [FrameMessage.Part] = []
        pixels.withUnsafeMutableBytes { image in
            new.withUnsafeBytes { fresh in
                func newRow(_ row: Int) -> UnsafeRawPointer {
                    fresh.baseAddress! + row * rowBytes
                }
                func oldRow(_ row: Int) -> UnsafeRawPointer {
                    UnsafeRawPointer(image.baseAddress! + origin + row * imageRowBytes)
                }
                let newHashes = (0..<rows).map { RowHash.of(newRow($0), count: rowBytes) }
                let oldHashes = (0..<rows).map { RowHash.of(oldRow($0), count: rowBytes) }
                /// Whether new row `row` equals old row `source`.
                func matches(_ row: Int, _ source: Int) -> Bool {
                    newHashes[row] == oldHashes[source]
                        && memcmp(newRow(row), oldRow(source), rowBytes) == 0
                }
                let unchanged = (0..<rows).map { matches($0, $0) }
                let shift = Self.shift(
                    rows: rows, newHashes: newHashes, oldHashes: oldHashes, unchanged: unchanged,
                    matches: matches)
                if let shift {
                    parts.append(
                        .copy(
                            PixelRect(
                                x: rect.x, y: rect.y + shift.rows.lowerBound, width: rect.width,
                                height: shift.rows.count),
                            fromX: rect.x, fromY: rect.y + shift.rows.lowerBound + shift.distance))
                }
                var changed: [Range<Int>] = []
                for row in 0..<rows {
                    let same =
                        if let shift, shift.rows.contains(row) {
                            matches(row, row + shift.distance)
                        } else {
                            unchanged[row]
                        }
                    guard !same else { continue }
                    if let last = changed.last, row - last.upperBound < Self.mergeGap {
                        changed[changed.count - 1] = last.lowerBound..<(row + 1)
                    } else {
                        changed.append(row..<(row + 1))
                    }
                }
                let bands = changed.flatMap { run in
                    stride(from: run.lowerBound, to: run.upperBound, by: Self.maximumPartRows).map {
                        $0..<min($0 + Self.maximumPartRows, run.upperBound)
                    }
                }
                parts += FrameMessage.pixels(
                    bands.map { band in
                        (
                            PixelRect(
                                x: rect.x, y: rect.y + band.lowerBound, width: rect.width,
                                height: band.count),
                            UnsafeRawBufferPointer(
                                rebasing: fresh[
                                    (band.lowerBound * rowBytes)..<(band.upperBound * rowBytes)])
                        )
                    })
                // The page's rectangle now matches the new pixels.
                for row in 0..<rows {
                    (image.baseAddress! + origin + row * imageRowBytes).copyMemory(
                        from: newRow(row), byteCount: rowBytes)
                }
            }
        }
        return parts
    }

    /// The distance that most changed rows moved, and the rows to copy from
    /// that distance, or `nil` if copying would not save enough rows. A
    /// positive distance means the content moved up, as when scrolling
    /// toward the end.
    private static func shift(
        rows: Int, newHashes: [UInt32], oldHashes: [UInt32], unchanged: [Bool],
        matches: (Int, Int) -> Bool
    ) -> (distance: Int, rows: Range<Int>)? {
        guard unchanged.count(where: { !$0 }) >= minimumCopiedRows else { return nil }
        var sources: [UInt32: [Int]] = [:]
        for row in 0..<rows { sources[oldHashes[row], default: []].append(row) }
        var votes: [Int: Int] = [:]
        for row in 0..<rows where !unchanged[row] {
            guard let candidates = sources[newHashes[row]],
                candidates.count <= maximumCandidates
            else { continue }
            for source in candidates where source != row { votes[source - row, default: 0] += 1 }
        }
        guard
            let best = votes.max(by: {
                $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key)
            }),
            best.value >= minimumCopiedRows
        else { return nil }
        let distance = best.key
        let candidates = max(0, -distance)..<min(rows, rows - distance)
        let copied = candidates.filter { matches($0, $0 + distance) }
        guard let first = copied.first, let last = copied.last else { return nil }
        // Rows the copy covers that already matched where they were.
        let band = first..<(last + 1)
        let kept = band.count(where: { unchanged[$0] })
        guard copied.count - kept >= minimumCopiedRows else { return nil }
        return (distance, band)
    }
}

/// Hashes of rows of pixels, to find rows that match.
enum RowHash {
    static func of(_ row: UnsafeRawPointer, count: Int) -> UInt32 {
        if let crc = Zlib.crc32(row, count: count) { return crc }
        // FNV-1a over whole words, for when zlib is missing.
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        var offset = 0
        while offset + 8 <= count {
            hash =
                (hash ^ row.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
                &* 0x0000_0100_0000_01B3
            offset += 8
        }
        while offset < count {
            hash =
                (hash ^ UInt64(row.load(fromByteOffset: offset, as: UInt8.self)))
                &* 0x0000_0100_0000_01B3
            offset += 1
        }
        return UInt32(truncatingIfNeeded: hash ^ hash >> 32)
    }
}

/// The binary WebSocket message that carries a frame to the page.
///
/// It starts with a 12-byte header: the kind (1), a reserved byte, the
/// sequence number that the page acknowledges, the frame's width and
/// height in pixels, and the number of parts. The page applies the parts
/// in order. Each part has a 13-byte header: the encoding, the rectangle
/// it changes, and four more bytes. For pixels, those are the length of
/// the pixels that follow, row-major RGBA; for a copy, the position in the
/// page's canvas to copy the rectangle from. Integers are big-endian.
enum FrameMessage {
    static let kind: UInt8 = 1

    /// How a part is encoded.
    enum Encoding: UInt8 {
        /// Uncompressed pixels.
        case raw = 0
        /// Pixels as a zlib stream, which the page decompresses with
        /// `DecompressionStream("deflate")`.
        case zlib = 1
        /// No pixels: the page copies the rectangle from elsewhere in its
        /// own canvas.
        case copy = 2
    }

    /// One change to a rectangle of the page's canvas.
    enum Part: Equatable {
        case pixels(PixelRect, Encoding, [UInt8])
        case copy(PixelRect, fromX: Int, fromY: Int)

        var rect: PixelRect {
            switch self {
            case .pixels(let rect, _, _), .copy(let rect, _, _): rect
            }
        }
    }

    /// The zlib level frames are compressed at. On the rows a fling
    /// changes, level 4 made 20% fewer bytes than level 1 for about three
    /// times the time; see `docs/architecture.md`.
    static let compressionLevel: Int32 = 4

    /// A rectangle's pixels, compressed if zlib is available and makes them
    /// smaller.
    static func pixels(_ rect: PixelRect, _ pixels: UnsafeRawBufferPointer) -> Part {
        if let compressed = Zlib.compress(pixels, level: compressionLevel),
            compressed.count < pixels.count
        {
            return .pixels(rect, .zlib, compressed)
        }
        return .pixels(rect, .raw, Array(pixels))
    }

    /// Several rectangles' pixels, compressed in parallel.
    static func pixels(_ rects: [(PixelRect, UnsafeRawBufferPointer)]) -> [Part] {
        guard rects.count > 1 else { return rects.map { pixels($0.0, $0.1) } }
        let results = PartList(count: rects.count)
        // The buffers stay valid: concurrentPerform returns after every iteration.
        let shared = UncheckedSendable(rects)
        DispatchQueue.concurrentPerform(iterations: rects.count) { index in
            let (rect, bytes) = shared.value[index]
            results.set(index, pixels(rect, bytes))
        }
        return results.parts
    }

    /// The message for a frame of `width` × `height` pixels.
    static func encode(sequence: UInt32, width: Int, height: Int, parts: [Part]) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(
            12
                + parts.reduce(0) {
                    if case .pixels(_, _, let pixels) = $1 { return $0 + 13 + pixels.count }
                    return $0 + 13
                })
        bytes.append(kind)
        bytes.append(0)
        bytes.appendBigEndian(sequence)
        bytes.appendBigEndian(UInt16(width))
        bytes.appendBigEndian(UInt16(height))
        bytes.appendBigEndian(UInt16(parts.count))
        for part in parts {
            let rect = part.rect
            switch part {
            case .pixels(_, let encoding, _): bytes.append(encoding.rawValue)
            case .copy: bytes.append(Encoding.copy.rawValue)
            }
            bytes.appendBigEndian(UInt16(rect.x))
            bytes.appendBigEndian(UInt16(rect.y))
            bytes.appendBigEndian(UInt16(rect.width))
            bytes.appendBigEndian(UInt16(rect.height))
            switch part {
            case .pixels(_, _, let pixels):
                bytes.appendBigEndian(UInt32(pixels.count))
                bytes += pixels
            case .copy(_, let fromX, let fromY):
                bytes.appendBigEndian(UInt16(fromX))
                bytes.appendBigEndian(UInt16(fromY))
            }
        }
        return bytes
    }
}

/// A value that may cross threads because its owner keeps the threads from
/// sharing it unsafely.
private struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

/// Parts that threads fill in at their own indices.
private final class PartList: @unchecked Sendable {
    private let lock = NSLock()
    private var slots: [FrameMessage.Part?]

    init(count: Int) {
        slots = Array(repeating: nil, count: count)
    }

    func set(_ index: Int, _ part: FrameMessage.Part) {
        lock.withLock { slots[index] = part }
    }

    var parts: [FrameMessage.Part] {
        lock.withLock { slots.compactMap { $0 } }
    }
}

extension PixelRect {
    var isEmpty: Bool { width <= 0 || height <= 0 }

    /// The rectangle limited to a frame of `width` × `height` pixels.
    func clamped(width frameWidth: Int, height frameHeight: Int) -> PixelRect {
        let left = min(max(x, 0), frameWidth)
        let top = min(max(y, 0), frameHeight)
        let right = min(max(x + width, left), frameWidth)
        let bottom = min(max(y + height, top), frameHeight)
        return PixelRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// The smallest rectangle that contains both.
    func union(_ other: PixelRect) -> PixelRect {
        if isEmpty { return other }
        if other.isEmpty { return self }
        let left = min(x, other.x)
        let top = min(y, other.y)
        return PixelRect(
            x: left, y: top, width: max(x + width, other.x + other.width) - left,
            height: max(y + height, other.y + other.height) - top)
    }
}

extension [UInt8] {
    mutating func appendBigEndian(_ value: UInt16) {
        append(UInt8(value >> 8))
        append(UInt8(value & 0xFF))
    }

    mutating func appendBigEndian(_ value: UInt32) {
        append(UInt8(value >> 24))
        append(UInt8(value >> 16 & 0xFF))
        append(UInt8(value >> 8 & 0xFF))
        append(UInt8(value & 0xFF))
    }
}
