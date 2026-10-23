import Foundation
import ParhelionPreview
import Testing

@testable import ParhelionTooling

/// A page's canvas, updated the way the page's script applies a frame
/// message.
struct ReferencePage {
    var width = 0
    var height = 0
    var pixels: [UInt8] = []

    /// Applies a message and returns its sequence number.
    @discardableResult
    mutating func apply(_ message: [UInt8]) throws -> UInt32 {
        func u16(_ offset: Int) -> Int { Int(message[offset]) << 8 | Int(message[offset + 1]) }
        func u32(_ offset: Int) -> Int { u16(offset) << 16 | u16(offset + 2) }
        try #require(message[0] == FrameMessage.kind)
        let sequence = UInt32(u32(2))
        if u16(6) != width || u16(8) != height {
            width = u16(6)
            height = u16(8)
            pixels = [UInt8](repeating: 0, count: width * height * 4)
        }
        var offset = 12
        for _ in 0..<u16(10) {
            let encoding = try #require(FrameMessage.Encoding(rawValue: message[offset]))
            let (x, y, w, h) = (u16(offset + 1), u16(offset + 3), u16(offset + 5), u16(offset + 7))
            if encoding == .copy {
                let (fromX, fromY) = (u16(offset + 9), u16(offset + 11))
                offset += 13
                let source = pixels
                for row in 0..<h {
                    let from = ((fromY + row) * width + fromX) * 4
                    let to = ((y + row) * width + x) * 4
                    pixels.replaceSubrange(to..<(to + w * 4), with: source[from..<(from + w * 4)])
                }
                continue
            }
            let length = u32(offset + 9)
            offset += 13
            var bytes = Array(message[offset..<(offset + length)])
            offset += length
            if encoding == .zlib {
                bytes = try #require(Zlib.decompress(bytes, size: w * h * 4))
            }
            try #require(bytes.count == w * h * 4)
            for row in 0..<h {
                let to = ((y + row) * width + x) * 4
                pixels.replaceSubrange(
                    to..<(to + w * 4), with: bytes[(row * w * 4)..<((row + 1) * w * 4)])
            }
        }
        try #require(offset == message.count)
        return sequence
    }
}

/// A frame of rows that each differ, like lines of text, scrolled by
/// `offset` rows, with a fixed bar at the top.
func scrolledFrame(width: Int, height: Int, offset: Int, bar: Int = 10) -> [UInt8] {
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for row in 0..<height {
        let content = row + offset
        for column in 0..<width {
            let index = (row * width + column) * 4
            if row < bar {
                pixels[index] = 30
                pixels[index + 1] = 30
                pixels[index + 2] = 30
            } else if (column + content * 7) % 23 < 5 {
                pixels[index] = UInt8(truncatingIfNeeded: content * 13)
                pixels[index + 1] = UInt8(truncatingIfNeeded: content * 29 + column)
                pixels[index + 2] = UInt8(truncatingIfNeeded: content)
            }
        }
    }
    return pixels
}

@Suite("Web frame encoding")
struct WebFrameTests {
    @Test("Zlib is available, so frames are compressed")
    func zlib() throws {
        #expect(Zlib.isAvailable)
        let bytes = [UInt8](repeating: 9, count: 10_000)
        let compressed = try #require(bytes.withUnsafeBytes { Zlib.compress($0, level: 4) })
        #expect(compressed.count < 100)
        #expect(
            compressed.first == 0x78, "a zlib stream, which DecompressionStream(\"deflate\") reads")
        #expect(Zlib.decompress(compressed, size: bytes.count) == bytes)
        #expect(Zlib.decompress(compressed, size: bytes.count + 1) == nil)
    }

    @Test("The frame buffer copies only the damaged rectangle")
    func frameBuffer() {
        var buffer = FrameBuffer()
        let first = [UInt8](repeating: 1, count: 4 * 3 * 4)
        let changed = first.withUnsafeBytes {
            buffer.update(
                width: 4, height: 3, damage: PixelRect(x: 1, y: 1, width: 1, height: 1), from: $0)
        }
        #expect(changed == PixelRect(x: 0, y: 0, width: 4, height: 3), "a new size is all new")
        let second = [UInt8](repeating: 2, count: 4 * 3 * 4)
        let damage = second.withUnsafeBytes {
            buffer.update(
                width: 4, height: 3, damage: PixelRect(x: 1, y: 1, width: 2, height: 9), from: $0)
        }
        #expect(damage == PixelRect(x: 1, y: 1, width: 2, height: 2), "clamped to the frame")
        #expect(
            buffer.region(PixelRect(x: 0, y: 1, width: 4, height: 1)) == [1, 1, 1, 1]
                + [UInt8](repeating: 2, count: 8) + [1, 1, 1, 1])
        #expect(
            buffer.region(PixelRect(x: 0, y: 0, width: 4, height: 1))
                == [UInt8](repeating: 1, count: 16))
    }

    @Test("Rectangles clamp and combine")
    func rectangles() {
        let rect = PixelRect(x: -5, y: 2, width: 20, height: 3)
        #expect(rect.clamped(width: 10, height: 4) == PixelRect(x: 0, y: 2, width: 10, height: 2))
        #expect(PixelRect(x: 20, y: 20, width: 5, height: 5).clamped(width: 10, height: 10).isEmpty)
        #expect(
            PixelRect(x: 1, y: 1, width: 2, height: 2).union(
                PixelRect(x: 5, y: 0, width: 1, height: 1))
                == PixelRect(x: 1, y: 0, width: 5, height: 3))
        #expect(
            PixelRect(x: 0, y: 0, width: 0, height: 0).union(
                PixelRect(x: 5, y: 6, width: 1, height: 1))
                == PixelRect(x: 5, y: 6, width: 1, height: 1))
    }

    @Test("A frame message lays out its header and parts as the page reads them")
    func messageLayout() {
        let message = FrameMessage.encode(
            sequence: 0x0102_0304, width: 300, height: 2,
            parts: [
                .copy(PixelRect(x: 1, y: 2, width: 3, height: 4), fromX: 5, fromY: 6),
                .pixels(PixelRect(x: 7, y: 0, width: 1, height: 1), .raw, [9, 8, 7, 6]),
            ])
        #expect(Array(message[0..<12]) == [1, 0, 1, 2, 3, 4, 1, 44, 0, 2, 0, 2])
        #expect(Array(message[12..<25]) == [2, 0, 1, 0, 2, 0, 3, 0, 4, 0, 5, 0, 6])
        #expect(Array(message[25...]) == [0, 0, 7, 0, 0, 0, 1, 0, 1, 0, 0, 0, 4, 9, 8, 7, 6])
    }

    @Test("A page gets every row once, then only the rows that change")
    func changedRows() throws {
        let (width, height) = (40, 60)
        var image = PageImage()
        var page = ReferencePage()
        let bounds = PixelRect(x: 0, y: 0, width: width, height: height)
        let first = scrolledFrame(width: width, height: height, offset: 0)
        try page.apply(
            FrameMessage.encode(
                sequence: 1, width: width, height: height,
                parts: image.parts(for: bounds, new: first, frameWidth: width, frameHeight: height))
        )
        #expect(page.pixels == first)

        #expect(
            image.parts(for: bounds, new: first, frameWidth: width, frameHeight: height).isEmpty)

        var second = first
        for index in ((30 * width) * 4)..<((31 * width) * 4) { second[index] = 0 }
        let parts = image.parts(for: bounds, new: second, frameWidth: width, frameHeight: height)
        #expect(parts.map(\.rect) == [PixelRect(x: 0, y: 30, width: width, height: 1)])
        try page.apply(FrameMessage.encode(sequence: 2, width: width, height: height, parts: parts))
        #expect(page.pixels == second)
    }

    @Test("Content that scrolled by whole pixels is copied on the page")
    func scrolledRows() throws {
        let (width, height) = (64, 200)
        var image = PageImage()
        var page = ReferencePage()
        // The damage is the scroll view, below the bar.
        let damage = PixelRect(x: 0, y: 10, width: width, height: height - 10)
        var frame = FrameBuffer()
        for (index, offset) in [0, 17, 40, 12].enumerated() {
            let pixels = scrolledFrame(width: width, height: height, offset: offset)
            _ = pixels.withUnsafeBytes {
                frame.update(width: width, height: height, damage: damage, from: $0)
            }
            let rect = index == 0 ? frame.bounds : damage
            let parts = image.parts(
                for: rect, new: frame.region(rect), frameWidth: width, frameHeight: height)
            if index > 0 {
                let copied = parts.compactMap { part -> PixelRect? in
                    if case .copy(let rect, _, _) = part { return rect }
                    return nil
                }
                #expect(copied.count == 1, "frame \(index)")
                let sent =
                    parts.reduce(0) { $0 + ($1.rect.height) } - copied.reduce(0) { $0 + $1.height }
                #expect(sent < 60, "frame \(index) sends \(sent) rows")
            }
            try page.apply(
                FrameMessage.encode(
                    sequence: UInt32(index + 1), width: width, height: height, parts: parts))
            #expect(page.pixels == pixels, "frame \(index)")
        }
    }

    @Test("A new frame size starts the page over")
    func resize() throws {
        var image = PageImage()
        var page = ReferencePage()
        for (width, height) in [(8, 8), (12, 6)] {
            let pixels = scrolledFrame(width: width, height: height, offset: 3, bar: 2)
            let parts = image.parts(
                for: PixelRect(x: 0, y: 0, width: width, height: height), new: pixels,
                frameWidth: width, frameHeight: height)
            try page.apply(
                FrameMessage.encode(sequence: 1, width: width, height: height, parts: parts))
            #expect(page.pixels == pixels)
        }
    }

    @Test("Long runs of changed rows split into parts compressed in parallel")
    func parallelParts() throws {
        let (width, height) = (16, PageImage.maximumPartRows * 2 + 10)
        var image = PageImage()
        var page = ReferencePage()
        let pixels = scrolledFrame(width: width, height: height, offset: 0, bar: 0)
        let parts = image.parts(
            for: PixelRect(x: 0, y: 0, width: width, height: height), new: pixels,
            frameWidth: width, frameHeight: height)
        #expect(
            parts.map(\.rect.height) == [PageImage.maximumPartRows, PageImage.maximumPartRows, 10])
        try page.apply(FrameMessage.encode(sequence: 1, width: width, height: height, parts: parts))
        #expect(page.pixels == pixels)
    }
}
