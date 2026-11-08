import Foundation
import Testing

@testable import ParhelionRender

/// The pieces a renderer uses to draw a scrolled view by moving the last frame's pixels.
@Suite("Moving rows of pixels")
struct ScrollPixelsTests {
    private func patterned() -> Canvas {
        var canvas = Canvas(width: 40, height: 30, scale: 1)
        for y in 0..<30 {
            for x in 0..<40 {
                canvas.fill(
                    CGRect(x: x, y: y, width: 1, height: 1),
                    color: RGBA(red: UInt8(x * 6), green: UInt8(y * 8), blue: 90))
            }
        }
        return canvas
    }

    @Test("A flat box is found, and a box with a different pixel is not")
    func uniform() {
        var canvas = Canvas(
            width: 300, height: 400, scale: 1, background: RGBA(red: 9, green: 8, blue: 7))
        let box = PixelBox(minX: 3, minY: 5, maxX: 297, maxY: 395)
        #expect(canvas.uniformPixel(in: box) == RGBA(red: 9, green: 8, blue: 7).packed)
        // A pixel in each part of the box that a thread or a vector reads.
        for (x, y) in [(3, 5), (296, 394), (150, 200), (101, 300), (7, 11)] {
            var changed = canvas
            changed.fill(
                CGRect(x: x, y: y, width: 1, height: 1), color: RGBA(red: 1, green: 2, blue: 3))
            #expect(changed.uniformPixel(in: box) == nil, "at \(x), \(y)")
        }
        // Outside the box nothing matters.
        canvas.fill(CGRect(x: 0, y: 0, width: 300, height: 4), color: .black)
        #expect(canvas.uniformPixel(in: box) != nil)
    }

    @Test("Copied rows come back moved down or up, and the rest stay")
    func moved() {
        let source = patterned()
        let box = PixelBox(minX: 4, minY: 3, maxX: 36, maxY: 27)
        var words: [UInt32] = []
        source.copyPixels(in: box, into: &words)
        #expect(words.count == box.area)
        for rows in [5, -7, 0] {
            var target = Canvas(width: 40, height: 30, scale: 1, background: .black)
            target.replacePixels(in: box, with: words, movedDownBy: rows)
            for y in 0..<30 {
                for x in 0..<40 {
                    let moved =
                        x >= box.minX && x < box.maxX && y - rows >= box.minY
                        && y - rows < box.maxY && y >= box.minY && y < box.maxY
                    let expected =
                        moved ? source.pixel(x: x, y: y - rows) : RGBA.black
                    #expect(target.pixel(x: x, y: y) == expected, "rows \(rows) at \(x), \(y)")
                }
            }
        }
    }

    @Test("A box is filled with a pixel as is")
    func filled() {
        var canvas = patterned()
        canvas.fill(PixelBox(minX: 2, minY: 2, maxX: 10, maxY: 6), pixel: 0x7F01_0203)
        #expect(canvas.pixel(x: 9, y: 5) == RGBA(red: 3, green: 2, blue: 1, alpha: 127))
        #expect(canvas.pixel(x: 10, y: 5) == patterned().pixel(x: 10, y: 5))
    }

    @Test("A clip rectangle and the pixels it covers go both ways")
    func clips() {
        let canvas = Canvas(width: 100, height: 50, scale: 3)
        let box = PixelBox(minX: 30, minY: 60, maxX: 210, maxY: 120)
        var clipped = canvas
        clipped.clipRect = canvas.clipRect(for: box)
        #expect(clipped.pixelClip == (30, 60, 210, 120))
        #expect(canvas.pixelBox(clippedTo: canvas.clipRect(for: box)) == box)
    }

    @Test("Ranges cover the work once, in pieces, or all at once for little work")
    func ranges() {
        for count in [0, 1, 7, 100, 1001] {
            for minimum in [1, 16, 5000] {
                var seen = [Int32](repeating: 0, count: count)
                seen.withUnsafeMutableBufferPointer { seen in
                    let shared = Unshared(seen.baseAddress)
                    forEachRange(of: count, minimum: minimum) { range in
                        for index in range { shared.value![index] += 1 }
                    }
                }
                #expect(seen.allSatisfy { $0 == 1 }, "\(count) in pieces of \(minimum)")
            }
        }
    }

    @Test("A shadow is the same under any clip")
    func shadowUnderClips() {
        var layer = Canvas(width: 60, height: 60, scale: 2, background: .clear)
        layer.fill(CGRect(x: 0, y: 0, width: 30, height: 30), cornerRadius: 8, color: .black)
        func shadow(clip: CGRect?) -> Canvas {
            var canvas = Canvas(width: 200, height: 200, scale: 2)
            canvas.clipRect = clip
            canvas.drawShadow(
                ofLayer: layer, atPixelX: 150, y: 150,
                color: RGBA(red: 0, green: 0, blue: 0, alpha: 150),
                offset: CGSize(width: 3, height: 5),
                blur: 14)
            return canvas
        }
        let whole = shadow(clip: nil)
        // Clips that begin in the middle of the shadow's reach, at points that
        // are not at a multiple of its sample size.
        for top in [61.0, 62.5, 70.0, 77.5, 83.0] {
            let clip = CGRect(x: 0, y: top, width: 200, height: 40)
            let part = shadow(clip: clip)
            let box = part.pixelBox(clippedTo: clip)
            for y in box.minY..<box.maxY {
                for x in 0..<400 {
                    #expect(part.pixel(x: x, y: y) == whole.pixel(x: x, y: y), "\(top): \(x), \(y)")
                }
            }
        }
    }

    @Test(
        "A layer's shadow skipped under its opaque pixels leaves the same canvas once it is drawn")
    func shadowSkippedUnderOpaque() {
        var layer = Canvas(width: 90, height: 70, scale: 2, background: .clear)
        layer.fill(
            CGRect(x: 0, y: 0, width: 45, height: 35), cornerRadius: 10,
            color: RGBA(red: 0, green: 0, blue: 255))
        // A hole in the middle, which the shadow must still show through.
        layer.fill(CGRect(x: 18, y: 12, width: 8, height: 8), color: .clear)
        for offset in [CGSize.zero, CGSize(width: 4, height: 6)] {
            func draw(skipping: Bool) -> Canvas {
                var canvas = Canvas(width: 150, height: 130, scale: 2)
                canvas.drawShadow(
                    ofLayer: layer, atPixelX: 60, y: 50,
                    color: RGBA(red: 0, green: 0, blue: 0, alpha: 140), offset: offset, blur: 16,
                    skipsUnderOpaque: skipping)
                canvas.draw(layer: layer, atPixelX: 60, y: 50)
                return canvas
            }
            let skipped = draw(skipping: true)
            let drawn = draw(skipping: false)
            var differing: [String] = []
            for y in 0..<skipped.height {
                for x in 0..<skipped.width
                where skipped.pixel(x: x, y: y) != drawn.pixel(x: x, y: y) {
                    differing.append(
                        "(\(x),\(y)) \(skipped.pixel(x: x, y: y)) vs \(drawn.pixel(x: x, y: y))")
                }
            }
            #expect(differing.isEmpty, "\(differing.count): \(differing.prefix(5))")
        }
    }
}
